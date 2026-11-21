"""
Private rooms v2 (game/rooms.py, step 1.13): states, the ready system, host
controls, invites, custom rules, the start countdown and rematches. Most tests
call the room functions directly; the socket requests are checked at the end.
"""

from datetime import timedelta
from unittest import mock

from django.test import override_settings
from django.utils import timezone

import game_platform
from accounts.models import User
from realtime import handlers as realtime_handlers
from realtime.handlers import Context
from realtime.protocol import ProtocolError

from . import rooms, services
from .models import Game, Player, Room, RoomInvite
from .tests import GameApiTestCase

Status = Room.Status


class RoomTestCase(GameApiTestCase):
    def room(self, code):
        return Room.objects.get(code=code)

    def refused(self, fn, *args, **kwargs):
        with self.assertRaises(rooms.RoomError) as caught:
            fn(*args, **kwargs)
        return caught.exception.code

    def room_news(self):
        """The newest room_updated message."""
        return [m for m in self.lobby if m["type"] == "room_updated"][-1]

    def finish_game(self, code, winner):
        """``winner`` brings their last token home (it must be their turn)."""
        self.set_positions(code, {winner: [55, 56, 56, 56]})
        self.dice(1)
        self.post("roll-dice", code=code, player_id=winner)
        self.post("move-token", code=code, player_id=winner, token_id=self.token_ids(code, winner)[0])
        self.assertTrue(self.game(code).is_finished)


class ReadyAndStartTests(RoomTestCase):
    def test_a_host_alone_is_ready_and_the_ai_joins(self):
        code, host = self.create_room()
        self.assertEqual(self.room(code).status, Status.READY)
        r = self.post("start-game", code=code, player_id=host)
        self.assertEqual(r.data, {"status": "game_started"})
        room = self.room(code)
        self.assertEqual((room.status, room.is_started), (Status.PLAYING, True))
        self.assertTrue(room.players.filter(is_bot=True).exists())

    def test_everyone_must_be_ready_before_the_start(self):
        code, host = self.create_room()
        guest = self.join(code, ready=False)
        self.assertEqual(self.room(code).status, Status.WAITING)
        r = self.post("start-game", code=code, player_id=host)
        self.assertEqual((r.status_code, r.data["code"]), (400, "not_everyone_ready"))

        rooms.set_ready(self.user_of(guest), code, True)
        self.assertEqual(self.room(code).status, Status.READY)
        self.assertTrue(Player.objects.get(id=guest).is_ready)
        rooms.set_ready(self.user_of(guest), code, False)
        self.assertEqual(self.room(code).status, Status.WAITING)
        self.assertEqual(self.refused(rooms.set_ready, self.user_of(host), code, True), "host_always_ready")

    def test_the_ready_flags_reach_the_room(self):
        code, host = self.create_room()
        guest = self.join(code)
        players = [m for m in self.lobby if m["type"] == "players_updated"][-1]["players"]
        self.assertEqual([(p["id"], p["is_ready"]) for p in players], [(host, True), (guest, True)])
        news = self.room_news()
        self.assertEqual((news["status"], news["host_id"], news["is_locked"]), ("ready", host, False))
        self.assertEqual(news["options"], game_platform.get_variant("ludo").check_options(None))
        self.assertIn(
            {"key": "turn_timeout_seconds", "default": 30, "choices": [15, 30, 60]}, news["option_choices"]
        )

    @override_settings(GAME_START_COUNTDOWN_SECONDS=3)
    def test_the_countdown_then_the_game(self):
        code, host = self.create_room()
        self.join(code)
        now = timezone.now()
        self.assertEqual(rooms.request_start(self.user_of(host), code, now=now), "starting")
        room = self.room(code)
        self.assertEqual((room.status, room.starts_at), (Status.STARTING, now + timedelta(seconds=3)))
        self.assertFalse(Game.objects.filter(room=room).exists())
        # Asking again doesn't restart the countdown; joining waits for the next room.
        self.assertEqual(rooms.request_start(self.user_of(host), code, now=now), "starting")
        r = self.post("join-room", code=code)
        self.assertEqual(r.data["code"], "game_starting")

        self.assertEqual(rooms.start_due_rooms(now + timedelta(seconds=2)), 0)
        self.assertEqual(rooms.start_due_rooms(now + timedelta(seconds=3)), 1)
        self.assertEqual(self.room(code).status, Status.PLAYING)
        self.assertTrue(Game.objects.filter(room__code=code).exists())
        self.assertIn("game_started", [m["type"] for m in self.lobby])

    @override_settings(GAME_START_COUNTDOWN_SECONDS=3)
    def test_someone_not_ready_stops_the_countdown(self):
        code, host = self.create_room()
        guest = self.join(code)
        now = timezone.now()
        rooms.request_start(self.user_of(host), code, now=now)
        rooms.set_ready(self.user_of(guest), code, False)
        room = self.room(code)
        self.assertEqual((room.status, room.starts_at), (Status.WAITING, None))
        self.assertEqual(rooms.start_due_rooms(now + timedelta(seconds=5)), 0)

    @override_settings(GAME_START_COUNTDOWN_SECONDS=3)
    def test_a_guest_leaving_during_the_countdown(self):
        code, host = self.create_room()
        guest = self.join(code)
        rooms.request_start(self.user_of(host), code)
        self.post("leave-room", code=code, player_id=guest)
        self.assertEqual(self.room(code).status, Status.STARTING)  # everyone left is ready
        self.assertEqual(rooms.start_due_rooms(timezone.now() + timedelta(seconds=4)), 1)

    def test_the_timer_sweep_starts_due_rooms(self):
        with mock.patch.object(rooms, "start_due_rooms", return_value=0) as sweep:
            from . import timers

            stop = mock.Mock()
            stop.is_set.side_effect = [False, True]
            timers.run_forever(0, stop)
        sweep.assert_called_once()


class HostControlTests(RoomTestCase):
    def test_only_the_host_controls_the_room(self):
        code, host = self.create_room()
        guest = self.join(code)
        user = self.user_of(guest)
        for fn, args in [
            (rooms.kick, (host,)),
            (rooms.set_locked, (True,)),
            (rooms.transfer_host, (guest,)),
        ]:
            self.assertEqual(self.refused(fn, user, code, *args), "not_host")
        self.assertEqual(self.refused(rooms.change_settings, user, code, options={}), "not_host")
        self.assertEqual(self.refused(rooms.request_start, user, code), "not_host")
        stranger = User.objects.create_guest()
        self.assertEqual(self.refused(rooms.set_ready, stranger, code, True), "not_in_room")

    def test_kicked_players_cannot_come_back_unless_invited(self):
        code, host = self.create_room()
        guest = self.join(code)
        kicked = self.user_of(guest)
        rooms.kick(self.user_of(host), code, guest)
        self.assertFalse(Player.objects.filter(id=guest).exists())
        self.assertIn({"type": "player_kicked", "player_id": guest}, self.lobby)
        self.assertEqual(self.refused(rooms.kick, self.user_of(host), code, host), "cannot_kick_yourself")
        self.assertEqual(self.refused(rooms.kick, self.user_of(host), code, "nobody"), "player_not_found")

        r = self.post("join-room", code=code, as_account=self.access[guest])
        self.assertEqual((r.status_code, r.data["code"]), (403, "player_kicked"))
        rooms.invite(self.user_of(host), code, kicked.player_id)  # the host changed their mind
        r = self.post("join-room", code=code, as_account=self.access[guest])
        self.assertEqual(r.status_code, 200)

    def test_a_locked_room_takes_invited_players_only(self):
        code, host = self.create_room()
        rooms.set_locked(self.user_of(host), code, True)
        self.assertTrue(self.room_news()["is_locked"])
        r = self.post("join-room", code=code)
        self.assertEqual((r.status_code, r.data["code"]), (403, "room_locked"))

        friend_account = self.new_account()
        r = self.api.get("/api/me/", HTTP_AUTHORIZATION=f"Bearer {friend_account}")
        friend = User.objects.get(player_id=r.data["player_id"])
        rooms.invite(self.user_of(host), code, friend.player_id)
        r = self.post("join-room", code=code, as_account=friend_account)
        self.assertEqual(r.status_code, 200)
        self.assertFalse(RoomInvite.objects.filter(to_user=friend).exists())  # used

    def test_passing_the_host_role(self):
        code, host = self.create_room()
        guest = self.join(code)
        rooms.transfer_host(self.user_of(host), code, guest)
        old, new = Player.objects.get(id=host), Player.objects.get(id=guest)
        self.assertEqual((old.is_host, old.is_ready, new.is_host, new.is_ready), (False, False, True, True))
        self.assertEqual(self.room(code).status, Status.WAITING)  # the old host gets ready now
        self.assertEqual(self.room_news()["host_id"], guest)


class CustomRulesTests(RoomTestCase):
    def test_the_host_picks_the_rules_and_the_game_uses_them(self):
        code, host = self.create_room()
        guest = self.join(code)
        rooms.change_settings(self.user_of(host), code, options={"turn_timeout_seconds": 60})
        room = self.room(code)
        self.assertEqual(room.options["turn_timeout_seconds"], 60)
        self.assertEqual(room.options["capture_enabled"], True)  # the rest: defaults
        self.assertFalse(Player.objects.get(id=guest).is_ready)  # agree to the new rules
        self.assertEqual(room.status, Status.WAITING)
        self.assertEqual(self.room_news()["options"]["turn_timeout_seconds"], 60)

        rooms.set_ready(self.user_of(guest), code, True)
        self.start(code, host)
        rules = self.state(code).rules
        self.assertEqual(rules.turn_timeout_seconds, 60)
        self.assertEqual(services.seconds_left(self.game(code).turn_deadline), 60)

    def test_only_offered_values(self):
        code, host = self.create_room()
        user = self.user_of(host)
        self.assertEqual(
            self.refused(rooms.change_settings, user, code, options={"turn_timeout_seconds": 5}),
            "invalid_option",
        )
        self.assertEqual(
            self.refused(rooms.change_settings, user, code, options={"jump_over": True}),
            "invalid_option",
        )
        self.assertEqual(self.refused(rooms.change_settings, user, code, variant="turbo"), "unknown_variant")

    @override_settings(GAME_START_COUNTDOWN_SECONDS=3)
    def test_no_changes_during_the_countdown_or_the_game(self):
        code, host = self.create_room()
        user = self.user_of(host)
        rooms.request_start(user, code)
        self.assertEqual(self.refused(rooms.change_settings, user, code, options={}), "game_starting")
        rooms.start_due_rooms(timezone.now() + timedelta(seconds=4))
        self.assertEqual(self.refused(rooms.change_settings, user, code, options={}), "game_already_started")
        self.assertEqual(self.refused(rooms.set_locked, user, code, True), "game_already_started")


class InviteTests(RoomTestCase):
    def test_invite_by_player_id(self):
        code, host = self.create_room()
        friend = User.objects.create_guest()
        with mock.patch("game.rooms.publish") as publish:
            with self.captureOnCommitCallbacks(execute=True):
                rooms.invite(self.user_of(host), code, f"{friend.player_id}")
        channel, kind, payload = publish.call_args.args
        self.assertEqual((channel, kind), (f"user/{friend.player_id}", "room_invite"))
        self.assertEqual(payload["room_code"], code)
        self.assertEqual(payload["from"]["player_id"], self.user_of(host).player_id)

        self.assertEqual([i["room_code"] for i in rooms.pending_invites(friend)], [code])
        token = self.access_for(friend)
        r = self.api.get("/api/game/invites/", HTTP_AUTHORIZATION=f"Bearer {token}")
        self.assertEqual([i["room_code"] for i in r.data["invites"]], [code])
        rooms.decline_invite(friend, code.lower())
        self.assertEqual(rooms.pending_invites(friend), [])

    def test_refused_invites(self):
        code, host = self.create_room()
        guest = self.join(code)
        me = self.user_of(host)
        self.assertEqual(self.refused(rooms.invite, me, code, 1), "player_not_found")
        self.assertEqual(self.refused(rooms.invite, me, code, "abc"), "player_not_found")
        self.assertEqual(self.refused(rooms.invite, me, code, me.player_id), "cannot_invite_yourself")
        self.assertEqual(
            self.refused(rooms.invite, me, code, self.user_of(guest).player_id), "already_in_room"
        )
        rooms.set_locked(me, code, True)
        friend = User.objects.create_guest()
        self.assertEqual(self.refused(rooms.invite, self.user_of(guest), code, friend.player_id), "not_host")

    def test_invites_to_started_rooms_are_gone(self):
        code, host = self.create_room()
        friend = User.objects.create_guest()
        rooms.invite(self.user_of(host), code, friend.player_id)
        self.start(code, host)
        self.assertEqual(rooms.pending_invites(friend), [])

    def access_for(self, user):
        from accounts import tokens

        return tokens.start_session(user, device_id="invite-test", platform="other").access


class RematchTests(RoomTestCase):
    def test_everyone_agrees_then_the_same_people_play_again(self):
        code, host, guest = self.two_humans()
        self.finish_game(code, host)
        self.assertEqual(self.room(code).status, Status.FINISHED)
        self.assertEqual(self.room_news()["status"], "finished")

        self.assertEqual(rooms.vote_rematch(self.user_of(host), code, True), {"next_room": None})
        self.assertTrue([p for p in services.players_payload(self.room(code)) if p["id"] == host][0]["wants_rematch"])
        answer = rooms.vote_rematch(self.user_of(guest), code, True)

        old = self.room(code)
        new = Room.objects.get(code=answer["next_room"]["code"])
        self.assertEqual((old.status, old.next_room_id), (Status.CLOSED, new.id))
        self.assertEqual(new.status, Status.PLAYING)  # no countdown in these tests
        moved = [m for m in self.lobby if m["type"] == "rematch_started"][-1]
        self.assertEqual((moved["room_code"], moved["room_id"]), (new.code, str(new.id)))
        self.assertEqual(set(moved["seats"]), {host, guest})
        self.assertEqual(answer["seat_id"], moved["seats"][guest])
        new_host = Player.objects.get(id=moved["seats"][host])
        self.assertEqual((new_host.is_host, new_host.color), (True, Player.objects.get(id=host).color))
        self.assertEqual(services.active_seat_for(self.user_of(guest))["code"], new.code)
        # Asking again in the old room tells you where the rematch is.
        self.assertEqual(rooms.vote_rematch(self.user_of(host), code, True)["next_room"]["code"], new.code)

    def test_people_who_left_are_not_waited_for(self):
        code, host, guest = self.two_humans()
        self.finish_game(code, host)
        rooms.vote_rematch(self.user_of(host), code, True)
        self.post("leave-room", code=code, player_id=guest)
        self.assertTrue(Player.objects.get(id=guest).has_left)
        room = self.room(code)
        self.assertEqual(room.status, Status.CLOSED)
        new = room.next_room
        self.assertEqual(list(new.players.filter(is_bot=False).values_list("user", flat=True)), [self.user_of(host).pk])
        self.assertTrue(new.players.filter(is_bot=True).exists())  # alone again: the AI plays

    def test_no_rematch_before_the_end_and_an_empty_room_closes(self):
        code, host, guest = self.two_humans()
        self.assertEqual(self.refused(rooms.vote_rematch, self.user_of(host), code, True), "game_not_finished")
        self.post("leave-room", code=code, player_id=guest)  # forfeit: the host wins
        self.assertEqual(self.room(code).status, Status.FINISHED)
        self.post("leave-room", code=code, player_id=host)
        self.assertEqual(self.room(code).status, Status.CLOSED)
        self.assertIsNone(self.room(code).next_room)


class RoomRequestTests(RoomTestCase):
    """The room requests on /ws/v1/ (game/handlers.py)."""

    def call(self, type, user, **data):
        return realtime_handlers.get(type).fn(Context(user, "test-session"), data)

    def code_of(self, type, user, **data):
        with self.assertRaises(ProtocolError) as caught:
            self.call(type, user, **data)
        return caught.exception.code

    def test_room_requests(self):
        code, host = self.create_room()
        guest = self.join(code, ready=False)
        host_user, guest_user = self.user_of(host), self.user_of(guest)

        self.assertEqual(self.call("set_ready", guest_user, code=code, ready=True), {"ready": True})
        self.assertEqual(self.call("lock_room", host_user, code=code, locked=True), {"locked": True})
        answer = self.call("room_settings", host_user, code=code, options={"capture_enabled": False})
        self.assertEqual(answer["options"]["capture_enabled"], False)
        friend = User.objects.create_guest()
        self.assertEqual(self.call("invite_player", host_user, code=code, player_id=friend.player_id), {"invited": True})
        self.assertEqual(self.call("decline_invite", friend, code=code), {"declined": True})
        self.assertEqual(self.call("transfer_host", host_user, code=code, player_id=guest), {"host_id": guest})
        self.assertEqual(self.call("kick_player", guest_user, code=code, player_id=host), {"kicked": True})
        self.assertEqual(self.call("start_game", guest_user, code=code), {"status": "started"})

    def test_refusals_and_bad_requests(self):
        code, host = self.create_room()
        guest = self.join(code)
        guest_user = self.user_of(guest)
        self.assertEqual(self.code_of("set_ready", guest_user, code=code, ready="yes"), "invalid_request")
        self.assertEqual(self.code_of("set_ready", guest_user, ready=True), "invalid_request")
        self.assertEqual(self.code_of("kick_player", guest_user, code=code, player_id=host), "not_host")
        self.assertEqual(self.code_of("kick_player", guest_user, code=code), "invalid_request")
        self.assertEqual(self.code_of("room_settings", guest_user, code=code, options=[]), "invalid_request")
        self.assertEqual(self.code_of("rematch", guest_user, code=code, want=True), "game_not_finished")
        self.assertEqual(self.code_of("start_game", guest_user, code="ZZZZ"), "room_not_found")
