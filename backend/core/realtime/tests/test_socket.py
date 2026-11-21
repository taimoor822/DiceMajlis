"""
/ws/v1/ end to end, with a real socket test client (channels.testing).

TransactionTestCase: the socket reads the database from its own code path, and
``transaction.on_commit`` pushes (wallet balances) only run after a real commit.
"""

from datetime import timedelta

from asgiref.sync import async_to_sync
from channels.db import database_sync_to_async
from channels.routing import URLRouter
from django.core.cache import cache
from django.test import TransactionTestCase, override_settings
from django.utils import timezone

from accounts import tokens
from accounts.models import User
from realtime import handlers, presence, routing
from realtime.protocol import ProtocolError
from realtime.publish import publish
from wallet import services as wallet
from wallet.models import TransactionType

from .socket_client import SocketClient

APP = URLRouter(routing.websocket_urlpatterns)
WAIT = 2  # seconds


def sign_in(user=None):
    user = user or User.objects.create_guest()
    pair = tokens.start_session(user, device_id="socket-test", platform="other")
    return user, pair


def msg(type, req_id=None, **data):
    message = {"v": 1, "type": type, "data": data}
    if req_id is not None:
        message["req_id"] = req_id
    return message


class SocketTestCase(TransactionTestCase):
    def setUp(self):
        cache.clear()

    def run_async(self, scenario):
        async_to_sync(scenario)()

    async def open(self):
        socket = SocketClient(APP, "/ws/v1/")
        connected, _ = await socket.connect()
        self.assertTrue(connected)
        return socket

    async def open_signed_in(self, user=None):
        user, pair = await database_sync_to_async(sign_in)(user)
        socket = await self.open()
        await socket.send_json_to(msg("auth", "auth-1", access_token=pair.access))
        reply = await socket.receive_json_from(WAIT)
        self.assertEqual(reply["type"], "ack", reply)
        return socket, user, pair

    async def closed_with(self, socket, code):
        output = await socket.receive_output(WAIT)
        self.assertEqual(output, {"type": "websocket.close", "code": code})


class SignInTests(SocketTestCase):
    def test_auth_first_then_ack_with_the_player_id(self):
        async def scenario():
            user, pair = await database_sync_to_async(sign_in)()
            socket = await self.open()
            await socket.send_json_to(msg("auth", "a1", access_token=pair.access))
            reply = await socket.receive_json_from(WAIT)
            self.assertEqual(reply, {
                "v": 1, "type": "ack", "req_id": "a1",
                "data": {"player_id": user.player_id, "heartbeat_seconds": 20},
            })
            self.assertTrue(presence.is_online(user.id))
            await socket.disconnect()
            self.assertFalse(presence.is_online(user.id))

        self.run_async(scenario)

    @override_settings(REALTIME_AUTH_TIMEOUT_SECONDS=0.05)
    def test_no_auth_in_time_closes_4408(self):
        async def scenario():
            socket = await self.open()
            reply = await socket.receive_json_from(WAIT)
            self.assertEqual(reply["code"], "auth_timeout")
            await self.closed_with(socket, 4408)

        self.run_async(scenario)

    def test_anything_but_auth_first_closes_4401(self):
        async def scenario():
            socket = await self.open()
            await socket.send_json_to(msg("ping", "p1"))
            reply = await socket.receive_json_from(WAIT)
            self.assertEqual((reply["req_id"], reply["code"]), ("p1", "auth_required"))
            await self.closed_with(socket, 4401)

        self.run_async(scenario)

    def test_bad_expired_or_signed_out_tokens_close_4401(self):
        def tokens_to_try():
            _, pair = sign_in()
            expired = tokens.issue_access(pair.session, now=timezone.now() - timedelta(hours=1))
            _, revoked = sign_in()
            revoked.session.revoke("logout")
            return [("nonsense", "invalid_token"), (expired, "token_expired"),
                    (revoked.access, "session_revoked"), ("", "invalid_token")]

        async def scenario():
            for token, code in await database_sync_to_async(tokens_to_try)():
                socket = await self.open()
                await socket.send_json_to(msg("auth", "a", access_token=token))
                reply = await socket.receive_json_from(WAIT)
                self.assertEqual(reply["code"], code, token)
                await self.closed_with(socket, 4401)

        self.run_async(scenario)

    def test_garbage_before_sign_in_closes_4401(self):
        async def scenario():
            socket = await self.open()
            await socket.send_to(text_data="hello")
            reply = await socket.receive_json_from(WAIT)
            self.assertEqual(reply["code"], "invalid_message")
            await self.closed_with(socket, 4401)

        self.run_async(scenario)

    def test_auth_twice_is_refused_but_keeps_the_socket(self):
        async def scenario():
            socket, _, pair = await self.open_signed_in()
            await socket.send_json_to(msg("auth", "a2", access_token=pair.access))
            self.assertEqual((await socket.receive_json_from(WAIT))["code"], "already_authenticated")
            await socket.send_json_to(msg("ping", "p"))
            self.assertEqual((await socket.receive_json_from(WAIT))["type"], "pong")
            await socket.disconnect()

        self.run_async(scenario)


class MessageTests(SocketTestCase):
    def test_ping_pong(self):
        async def scenario():
            socket, user, _ = await self.open_signed_in()
            cache.delete(f"presence:{user.id}")  # as if the 60 s ran out
            await socket.send_json_to(msg("ping", "p1"))
            self.assertEqual(await socket.receive_json_from(WAIT), {"v": 1, "type": "pong", "req_id": "p1"})
            self.assertTrue(presence.is_online(user.id))
            await socket.disconnect()

        self.run_async(scenario)

    def test_bad_messages_get_an_error_and_the_socket_stays(self):
        async def scenario():
            socket, _, _ = await self.open_signed_in()
            await socket.send_to(text_data='{"v":7,"type":"ping","req_id":"x"}')
            reply = await socket.receive_json_from(WAIT)
            self.assertEqual((reply["req_id"], reply["code"]), ("x", "unsupported_version"))
            await socket.send_json_to(msg("fly_away", "f"))
            self.assertEqual((await socket.receive_json_from(WAIT))["code"], "unknown_type")
            await socket.send_json_to(msg("ping"))
            self.assertEqual((await socket.receive_json_from(WAIT))["type"], "pong")
            await socket.disconnect()

        self.run_async(scenario)

    @override_settings(REALTIME_MAX_MESSAGE_BYTES=1000)
    def test_huge_messages_close_the_socket(self):
        async def scenario():
            socket, _, _ = await self.open_signed_in()
            await socket.send_json_to(msg("ping", "p", padding="x" * 2000))
            await self.closed_with(socket, 1009)

        self.run_async(scenario)

    @override_settings(REALTIME_SESSION_CHECK_SECONDS=0)
    def test_a_signed_out_device_loses_its_socket(self):
        async def scenario():
            socket, _, pair = await self.open_signed_in()
            await database_sync_to_async(pair.session.revoke)("logout")
            await socket.send_json_to(msg("ping", "p"))
            self.assertEqual((await socket.receive_json_from(WAIT))["code"], "session_revoked")
            await self.closed_with(socket, 4401)

        self.run_async(scenario)


class SubscriptionTests(SocketTestCase):
    def test_your_user_channel_starts_with_balances_then_follows_them(self):
        async def scenario():
            socket, user, _ = await self.open_signed_in()
            channel = f"user/{user.player_id}"
            await socket.send_json_to(msg("subscribe", "s1", channel=channel))
            self.assertEqual(
                await socket.receive_json_from(WAIT),
                {"v": 1, "type": "ack", "req_id": "s1", "data": {"channel": channel}},
            )
            first = await socket.receive_json_from(WAIT)
            self.assertEqual(
                (first["type"], first["channel"], first["data"]),
                ("balances_changed", channel, {"balances": {"gold": 0, "diamond": 0}}),
            )

            # A reward lands (one committed transaction): every phone hears it.
            await database_sync_to_async(wallet.post)(
                user, "gold", 100, TransactionType.ADMIN_GRANT, "test-gift-1"
            )
            pushed = await socket.receive_json_from(WAIT)
            self.assertEqual(pushed["type"], "balances_changed")
            self.assertEqual(pushed["data"]["balances"]["gold"], 100)
            await socket.disconnect()

        self.run_async(scenario)

    def test_other_peoples_and_unknown_channels_are_refused(self):
        async def scenario():
            socket, _, _ = await self.open_signed_in()
            other = await database_sync_to_async(User.objects.create_guest)()
            for channel, code in [
                (f"user/{other.player_id}", "forbidden"),
                (f"notifications/{other.player_id}", "forbidden"),
                ("chat/1234", "unknown_channel"),
                ("room/00000000-0000-0000-0000-000000000000", "channel_not_found"),
                (None, "unknown_channel"),
            ]:
                await socket.send_json_to(msg("subscribe", "s", channel=channel))
                reply = await socket.receive_json_from(WAIT)
                self.assertEqual(reply["code"], code, channel)
            await socket.disconnect()

        self.run_async(scenario)

    def test_unsubscribe_stops_the_events(self):
        async def scenario():
            socket, user, _ = await self.open_signed_in()
            channel = f"notifications/{user.player_id}"
            await socket.send_json_to(msg("subscribe", "s", channel=channel))
            await socket.receive_json_from(WAIT)  # ack (no initial events here)
            await database_sync_to_async(publish)(channel, "notification", {"n": 1})
            self.assertEqual((await socket.receive_json_from(WAIT))["data"], {"n": 1})

            await socket.send_json_to(msg("unsubscribe", "u", channel=channel))
            self.assertEqual((await socket.receive_json_from(WAIT))["type"], "ack")
            await database_sync_to_async(publish)(channel, "notification", {"n": 2})
            self.assertTrue(await socket.receive_nothing(0.2))
            await socket.disconnect()

        self.run_async(scenario)

    @override_settings(REALTIME_MAX_SUBSCRIPTIONS=1)
    def test_subscriptions_per_socket_are_capped(self):
        async def scenario():
            socket, user, _ = await self.open_signed_in()
            await socket.send_json_to(msg("subscribe", "a", channel=f"notifications/{user.player_id}"))
            await socket.receive_json_from(WAIT)
            await socket.send_json_to(msg("subscribe", "b", channel=f"user/{user.player_id}"))
            self.assertEqual((await socket.receive_json_from(WAIT))["code"], "too_many_subscriptions")
            await socket.disconnect()

        self.run_async(scenario)


@override_settings(REALTIME_RATE_LIMITS={"control": (2, 60), "subscribe": (5, 1)}, REALTIME_ABUSE_FACTOR=2)
class RateLimitTests(SocketTestCase):
    def test_too_fast_is_refused_then_closed_4429(self):
        async def scenario():
            socket, _, _ = await self.open_signed_in()
            replies = []
            for n in range(5):
                await socket.send_json_to(msg("ping", f"p{n}"))
                reply = await socket.receive_json_from(WAIT)
                replies.append(reply.get("code", reply["type"]))
            self.assertEqual(replies, ["pong", "pong", "rate_limited", "rate_limited", "rate_limited"])
            await self.closed_with(socket, 4429)

        self.run_async(scenario)


class HandlerTests(SocketTestCase):
    """Requests features register (game actions in 1.12): replies are remembered."""

    def setUp(self):
        super().setUp()
        self.calls = []

        def add_point(ctx, data):
            if data.get("refuse"):
                raise ProtocolError("not_allowed", "No")
            if data.get("crash"):
                self.calls.append("crash")
                raise RuntimeError("boom")
            self.calls.append(ctx.user.player_id)
            return {"points": len(self.calls)}

        handlers.register("add_point", add_point, bucket="game")
        self.addCleanup(handlers.unregister, "add_point")

    def test_a_retried_request_gets_the_first_answer_and_runs_once(self):
        async def scenario():
            socket, user, _ = await self.open_signed_in()
            for _ in range(2):
                await socket.send_json_to(msg("add_point", "same-id"))
                reply = await socket.receive_json_from(WAIT)
                self.assertEqual(reply, {"v": 1, "type": "ack", "req_id": "same-id", "data": {"points": 1}})
            self.assertEqual(self.calls, [user.player_id])
            await socket.send_json_to(msg("add_point", "new-id"))
            self.assertEqual((await socket.receive_json_from(WAIT))["data"], {"points": 2})
            await socket.disconnect()

        self.run_async(scenario)

    def test_the_retry_works_from_another_socket_too(self):
        async def scenario():
            first, user, _ = await self.open_signed_in()
            await first.send_json_to(msg("add_point", "r1"))
            await first.receive_json_from(WAIT)
            await first.disconnect()  # the connection dropped before the app saw the answer
            second, _, _ = await self.open_signed_in(user)
            await second.send_json_to(msg("add_point", "r1"))
            self.assertEqual((await second.receive_json_from(WAIT))["data"], {"points": 1})
            self.assertEqual(len(self.calls), 1)
            await second.disconnect()

        self.run_async(scenario)

    def test_refusals_are_remembered_server_errors_are_not(self):
        async def scenario():
            socket, _, _ = await self.open_signed_in()
            await socket.send_json_to(msg("add_point", "no", refuse=True))
            self.assertEqual((await socket.receive_json_from(WAIT))["code"], "not_allowed")
            await socket.send_json_to(msg("add_point", "no"))  # same id, no "refuse": same answer
            self.assertEqual((await socket.receive_json_from(WAIT))["code"], "not_allowed")

            await socket.send_json_to(msg("add_point", "boom", crash=True))
            self.assertEqual((await socket.receive_json_from(WAIT))["code"], "server_error")
            await socket.send_json_to(msg("add_point", "boom"))  # a retry runs again
            self.assertEqual((await socket.receive_json_from(WAIT))["type"], "ack")
            self.assertEqual(len(self.calls), 2)
            await socket.disconnect()

        self.run_async(scenario)

    def test_state_changing_requests_need_a_req_id(self):
        async def scenario():
            socket, _, _ = await self.open_signed_in()
            await socket.send_json_to(msg("add_point"))
            self.assertEqual((await socket.receive_json_from(WAIT))["code"], "req_id_required")
            self.assertEqual(self.calls, [])
            await socket.disconnect()

        self.run_async(scenario)

    def test_built_in_types_cannot_be_taken(self):
        with self.assertRaises(ValueError):
            handlers.register("ping", lambda ctx, data: {}, bucket="control")
