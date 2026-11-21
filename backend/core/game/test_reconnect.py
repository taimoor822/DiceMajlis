"""
Reconnection (step 1.14, game/connections.py): the seat is kept, the room hears
who dropped and who is back, a returning player gets what they missed
(state_delta) or the whole state, and a server restart loses nothing.
"""

import time
from datetime import timedelta
from unittest import mock

from asgiref.sync import async_to_sync
from channels.db import database_sync_to_async
from django.core.cache import cache
from django.test import TransactionTestCase, override_settings
from django.utils import timezone

import game_platform
from realtime import handlers as realtime_handlers
from realtime import presence
from realtime.handlers import Context
from realtime.tests.socket_client import SocketClient
from realtime.tests.test_socket import APP, WAIT, msg, sign_in

from . import connections, services, topics
from .models import Game, GameAction, Player, Room
from .tests import IN_MEMORY_LAYER, LOCAL_CACHE, GameApiTestCase

U1 = "5a0f9e9c-1f43-4c1e-9c55-0d6c2f0a0001"
U2 = "5a0f9e9c-1f43-4c1e-9c55-0d6c2f0a0002"


class PresenceTests(GameApiTestCase):
    """realtime/presence.py with the game listening (ids are account UUIDs)."""

    def setUp(self):
        super().setUp()
        cache.clear()

    def test_two_phones_then_offline_with_the_last_one(self):
        self.assertTrue(presence.connected(U1, "phone-a"))
        self.assertFalse(presence.connected(U1, "phone-b"))  # already online
        self.assertFalse(presence.disconnected(U1, "phone-a"))
        self.assertTrue(presence.is_online(U1))
        self.assertTrue(presence.disconnected(U1, "phone-b"))
        self.assertFalse(presence.is_online(U1))

    def test_sockets_of_a_dead_server_do_not_count(self):
        # A socket from before a restart, never closed, last heard 2 minutes ago.
        cache.set(f"presence:{U1}:sockets", {"old-socket": time.time() - 120})
        self.assertTrue(presence.connected(U1, "new-socket"))  # came online
        self.assertTrue(presence.disconnected(U1, "new-socket"))  # and offline again

    def test_listeners_hear_online_and_offline(self):
        heard = []
        listener = lambda user_id, online: heard.append((user_id, online))  # noqa: E731
        presence.listen(listener)
        self.addCleanup(presence.unlisten, listener)
        presence.connected(U2, "a")
        presence.connected(U2, "b")
        presence.disconnected(U2, "a")
        presence.disconnected(U2, "b")
        self.assertEqual(heard, [(U2, True), (U2, False)])


class SeatKeptTests(GameApiTestCase):
    def test_dropping_keeps_the_seat_and_the_room_hears_it(self):
        code, host, guest = self.two_humans()
        user = self.user_of(guest)
        connections.on_presence(user.id, False)
        seat = Player.objects.get(id=guest)
        self.assertIsNotNone(seat.disconnected_at)
        self.assertIn({"type": "player_disconnected", "player_id": guest}, self.lobby)
        players = [m for m in self.lobby if m["type"] == "players_updated"][-1]["players"]
        self.assertEqual({p["id"]: p["connected"] for p in players}, {host: True, guest: False})
        # Still seated: the game goes on and the turn timer runs for them.
        self.assertTrue(Player.objects.filter(id=guest, has_left=False).exists())

        before = len(self.lobby)
        connections.on_presence(user.id, False)  # already away: nothing new
        self.assertEqual(len(self.lobby), before)
        connections.on_presence(user.id, True)
        self.assertIsNone(Player.objects.get(id=guest).disconnected_at)
        self.assertIn({"type": "player_reconnected", "player_id": guest}, self.lobby)

    def test_finished_rooms_and_bots_are_left_alone(self):
        code, host = self.create_room()
        self.start(code, host)  # the AI joins
        Room.objects.filter(code=code).update(status=Room.Status.FINISHED)
        connections.on_presence(self.user_of(host).id, False)
        self.assertIsNone(Player.objects.get(id=host).disconnected_at)

    def test_the_sweep_marks_seats_whose_sockets_died_with_the_server(self):
        cache.clear()
        code, host, guest = self.two_humans()
        presence.connected(self.user_of(host).id, "host-socket")
        self.assertEqual(connections.mark_stale(), 1)  # the guest has no socket
        self.assertIsNotNone(Player.objects.get(id=guest).disconnected_at)
        self.assertIsNone(Player.objects.get(id=host).disconnected_at)
        self.assertEqual(connections.mark_stale(), 0)

    def test_bot_turns_start_again_after_a_restart(self):
        code, host = self.create_room()
        self.start(code, host)
        bot = Player.objects.get(room__code=code, is_bot=True)
        Game.objects.filter(room__code=code).update(current_turn=bot)
        with mock.patch.object(services, "schedule_bots") as schedule:
            self.assertEqual(connections.resume_after_restart(), 1)
        schedule.assert_called_once_with(code)


class CatchUpTests(GameApiTestCase):
    def play_a_little(self, code, host):
        """Host rolls a 6, brings a token out, rolls a 3 and moves it."""
        self.dice(6, 3)
        self.post("roll-dice", code=code, player_id=host)
        self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, host)[0])
        self.post("roll-dice", code=code, player_id=host)
        self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, host)[0])

    def test_the_delta_is_what_was_broadcast(self):
        code, host, _guest = self.two_humans()
        game = self.game(code)
        start = game.version
        self.sent.clear()
        self.play_a_little(code, host)
        game = self.game(code)

        delta = services.game_delta(game, start)
        self.assertEqual((delta["from_version"], delta["version"]), (start, game.version))
        self.assertEqual(
            [{"type": e["type"], **e["data"], "version": e["version"]} for e in delta["events"]],
            self.sent,
        )
        self.assertEqual(delta["seconds_left"], services.seconds_left(game.turn_deadline))
        self.assertEqual(services.game_delta(game, game.version)["events"], [])

    def test_when_only_the_whole_state_will_do(self):
        code, host, _guest = self.two_humans()
        self.play_a_little(code, host)
        game = self.game(code)
        self.assertIsNone(services.game_delta(game, game.version + 1))  # ahead of the server
        self.assertIsNone(services.game_delta(game, -1))
        with mock.patch.object(services, "MAX_DELTA_ACTIONS", 1):
            self.assertIsNone(services.game_delta(game, 0))
        GameAction.objects.filter(game=game, version=1).update(messages=[])  # from before 1.14
        self.assertIsNone(services.game_delta(game, 0))

    def test_the_game_channel_catches_up(self):
        code, host, _guest = self.two_humans()
        start = self.game(code).version
        self.play_a_little(code, host)
        game = self.game(code)
        topic = topics.GameTopic()
        user = self.user_of(host)
        (delta,) = topic.catch_up(user, str(game.id), start)
        self.assertEqual((delta["type"], delta["version"]), ("state_delta", game.version))
        self.assertGreater(len(delta["data"]["events"]), 3)
        self.assertIsNone(topic.catch_up(user, str(game.id), game.version + 5))
        # The room channel leaves the game to the game channel then.
        room_events = topics.RoomTopic().catch_up(user, str(game.room_id), start)
        self.assertEqual([e["type"] for e in room_events], ["players_updated", "room_updated"])

    def test_sync_request(self):
        code, host, _guest = self.two_humans()
        start = self.game(code).version
        self.play_a_little(code, host)
        user = self.user_of(host)
        sync = realtime_handlers.get("sync")
        self.assertFalse(sync.changes_state)
        answer = sync.fn(Context(user, "s"), {"code": code, "version": start})
        self.assertEqual(answer["kind"], "delta")
        self.assertEqual(answer["version"], self.game(code).version)
        answer = sync.fn(Context(user, "s"), {"code": code, "version": 10_000})
        self.assertEqual((answer["kind"], answer["version"]), ("snapshot", self.game(code).version))
        answer = sync.fn(Context(user, "s"), {"code": code})
        self.assertEqual(answer["kind"], "snapshot")


@override_settings(
    GAME_BOTS_INLINE=True,
    GAME_BOT_DELAY_SECONDS=(0, 0),
    GAME_START_COUNTDOWN_SECONDS=0,
    CHANNEL_LAYERS=IN_MEMORY_LAYER,
    CACHES=LOCAL_CACHE,
)
class SocketReconnectTests(TransactionTestCase):
    """Real sockets: a drop is heard by the room; coming back gets only what was missed."""

    def setUp(self):
        cache.clear()
        self.addCleanup(setattr, services, "SERVER_RANDOM", services.SERVER_RANDOM)

    def test_drop_and_come_back(self):
        def set_up():
            host_user, host_pair = sign_in()
            guest_user, guest_pair = sign_in()
            room = Room.objects.create(code="BACK", is_started=True, status=Room.Status.PLAYING)
            host = Player.objects.create(room=room, user=host_user, name="Host", color="red", is_host=True)
            Player.objects.create(room=room, user=guest_user, name="Guest", color="blue")
            game, _ = services.start_game(room, host)
            return room, game, host, host_pair, guest_pair

        async def open_as(pair):
            socket = SocketClient(APP, "/ws/v1/")
            await socket.connect()
            await socket.send_json_to(msg("auth", "a", access_token=pair.access))
            self.assertEqual((await socket.receive_json_from(WAIT))["type"], "ack")
            return socket

        async def until(socket, kind):
            while True:
                message = await socket.receive_json_from(WAIT)
                if message["type"] == kind:
                    return message

        async def scenario():
            room, game, host, host_pair, guest_pair = await database_sync_to_async(set_up)()
            watcher = await open_as(host_pair)
            await watcher.send_json_to(msg("subscribe", "s", channel=f"room/{room.id}"))
            guest = await open_as(guest_pair)
            await guest.send_json_to(msg("subscribe", "g", channel=f"game/{game.id}"))
            snapshot = await until(guest, "state_snapshot")
            seen = snapshot["version"]

            await guest.disconnect()
            gone = await until(watcher, "player_disconnected")
            self.assertEqual(gone["channel"], f"room/{room.id}")

            # The game goes on while the guest is away.
            services.SERVER_RANDOM = game_platform.ScriptedRandom([2])  # a 3
            await database_sync_to_async(services.perform)(
                "BACK", {"type": "roll", "player_id": str(host.id)}
            )

            guest = await open_as(guest_pair)
            back = await until(watcher, "player_reconnected")
            self.assertEqual(back["data"]["player_id"], gone["data"]["player_id"])
            await guest.send_json_to(msg("subscribe", "g2", channel=f"game/{game.id}", since=seen))
            delta = await until(guest, "state_delta")
            self.assertEqual(delta["data"]["from_version"], seen)
            self.assertEqual(
                [e["type"] for e in delta["data"]["events"]][:1], ["dice_rolled"]
            )
            await watcher.disconnect()
            await guest.disconnect()

        async_to_sync(scenario)()
