"""The socket's building blocks: message format, channels, rate limits, replies, presence."""

import json

from django.core.cache import cache
from django.test import SimpleTestCase, TestCase, override_settings

from accounts.models import User
from realtime import limits, presence, protocol, topics
from realtime.protocol import ProtocolError


class ProtocolTests(SimpleTestCase):
    def test_a_good_request(self):
        request = protocol.parse('{"v":1,"type":"subscribe","req_id":"a-1","data":{"channel":"user/1"}}')
        self.assertEqual(request, protocol.Request("subscribe", "a-1", {"channel": "user/1"}))

    def test_req_id_and_data_are_optional(self):
        self.assertEqual(protocol.parse('{"v":1,"type":"ping"}'), protocol.Request("ping", None, {}))

    def test_refused_messages_have_stable_codes(self):
        cases = {
            "not json": "invalid_message",
            "[1, 2]": "invalid_message",
            '{"type":"ping"}': "unsupported_version",
            '{"v":2,"type":"ping"}': "unsupported_version",
            '{"v":1}': "invalid_message",
            '{"v":1,"type":"Ping"}': "invalid_message",
            '{"v":1,"type":"ping","req_id":5}': "invalid_message",
            '{"v":1,"type":"ping","req_id":"has space"}': "invalid_message",
            '{"v":1,"type":"ping","data":[1]}': "invalid_message",
        }
        for text, code in cases.items():
            with self.subTest(text), self.assertRaises(ProtocolError) as caught:
                protocol.parse(text)
            self.assertEqual(caught.exception.code, code)

    def test_req_id_of_a_broken_message_is_kept_for_the_error_reply(self):
        self.assertEqual(protocol.req_id_of('{"v":9,"req_id":"r1"}'), "r1")
        self.assertIsNone(protocol.req_id_of("nope"))

    def test_server_messages(self):
        self.assertEqual(protocol.ack("r", {"a": 1}), {"v": 1, "type": "ack", "req_id": "r", "data": {"a": 1}})
        self.assertEqual(protocol.error("r", "bad")["code"], "bad")
        self.assertEqual(
            protocol.event("game/x", "token_moved", {"to": 5}, version=42),
            {"v": 1, "type": "token_moved", "channel": "game/x", "data": {"to": 5}, "version": 42},
        )
        self.assertNotIn("version", protocol.event("user/1", "balances_changed", {}))
        json.dumps(protocol.pong("r"))  # JSON-safe


class TopicTests(TestCase):
    def test_channel_names(self):
        topic, channel = topics.resolve("user/112156630")
        self.assertIsInstance(topic, topics.UserTopic)
        self.assertEqual(channel.name, "user/112156630")
        self.assertEqual(channel.group, "v1.user.112156630")

    def test_unknown_or_malformed_channels(self):
        for name in [None, 5, "", "user", "user/", "user/12", "user/1/2", "chat/abc",
                     "room/not-a-uuid", "game/abc", "game/0", "game/-1", "x" * 100]:
            with self.subTest(name), self.assertRaises(ProtocolError) as caught:
                topics.resolve(name)
            self.assertEqual(caught.exception.code, "unknown_channel")

    def test_uuid_keys_are_lowercased(self):
        _, channel = topics.resolve("room/2F6C0A6E-1B2C-4D3E-8F90-123456789ABC")
        self.assertEqual(channel.key, "2f6c0a6e-1b2c-4d3e-8f90-123456789abc")

    def test_only_you_may_subscribe_to_your_user_and_notifications_channels(self):
        me, other = User.objects.create_guest(), User.objects.create_guest()
        for kind in ("user", "notifications"):
            topic, channel = topics.resolve(f"{kind}/{me.player_id}")
            topic.authorize(me, channel.key)
            with self.assertRaises(ProtocolError) as caught:
                topic.authorize(other, channel.key)
            self.assertEqual(caught.exception.code, "forbidden")

    def test_user_channel_starts_with_the_balances(self):
        me = User.objects.create_guest()
        topic, channel = topics.resolve(f"user/{me.player_id}")
        [first] = topic.initial_events(me, channel.key)
        self.assertEqual(first["type"], "balances_changed")
        self.assertEqual(first["data"], {"balances": {"gold": 0, "diamond": 0}})

    def test_a_kind_registers_once(self):
        class Again(topics.Topic):
            kind = "user"

        with self.assertRaises(ValueError):
            topics.register(Again())


@override_settings(REALTIME_RATE_LIMITS={"game": (3, 1)}, REALTIME_ABUSE_FACTOR=2)
class LimitTests(SimpleTestCase):
    def setUp(self):
        cache.clear()

    def test_over_the_limit_is_refused_far_over_is_abuse(self):
        verdicts = [limits.hit("u1", "game", now=100.0) for _ in range(7)]
        ok, limited, abuse = limits.Verdict.OK, limits.Verdict.LIMITED, limits.Verdict.ABUSE
        self.assertEqual(verdicts, [ok, ok, ok, limited, limited, limited, abuse])

    def test_each_account_and_each_window_counts_alone(self):
        for _ in range(3):
            limits.hit("u1", "game", now=100.0)
        self.assertIs(limits.hit("u2", "game", now=100.0), limits.Verdict.OK)
        self.assertIs(limits.hit("u1", "game", now=101.0), limits.Verdict.OK)

    def test_a_reply_is_remembered_for_retries(self):
        self.assertIsNone(limits.claim("u1", "r1"))
        self.assertEqual(limits.claim("u1", "r1"), limits.PENDING)  # still working
        limits.remember("u1", "r1", {"type": "ack"})
        self.assertEqual(limits.claim("u1", "r1"), {"type": "ack"})
        self.assertIsNone(limits.claim("u2", "r1"))  # req_ids are per account
        limits.forget("u1", "r1")
        self.assertIsNone(limits.claim("u1", "r1"))


class PresenceTests(SimpleTestCase):
    def setUp(self):
        cache.clear()

    def test_online_while_a_socket_is_open(self):
        self.assertFalse(presence.is_online("u1"))
        presence.connected("u1")
        self.assertTrue(presence.is_online("u1"))
        presence.disconnected("u1")
        self.assertFalse(presence.is_online("u1"))

    def test_two_phones_the_last_one_to_close_marks_offline(self):
        presence.connected("u1")
        presence.connected("u1")
        presence.disconnected("u1")
        self.assertTrue(presence.is_online("u1"))
        presence.disconnected("u1")
        self.assertFalse(presence.is_online("u1"))

    def test_missed_heartbeats_mean_offline(self):
        presence.connected("u1")
        cache.delete("presence:u1")  # what the 60 s expiry does
        self.assertFalse(presence.is_online("u1"))
        presence.heartbeat("u1")
        self.assertTrue(presence.is_online("u1"))

    def test_many_at_once(self):
        presence.connected("a")
        presence.connected("c")
        self.assertEqual(presence.online(["a", "b", "c"]), {"a", "c"})

    def test_a_close_after_the_cache_forgot_is_harmless(self):
        presence.disconnected("ghost")
        self.assertFalse(presence.is_online("ghost"))
