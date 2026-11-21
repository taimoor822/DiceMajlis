"""
Game actions over the /ws/v1/ socket (game/handlers.py, step 1.12).

The handlers are called directly here (the socket's own plumbing is tested in
realtime/tests); one end-to-end test at the bottom plays through a real socket.
"""

from asgiref.sync import async_to_sync
from channels.db import database_sync_to_async
from django.core.cache import cache
from django.test import TransactionTestCase, override_settings

import game_platform
from accounts.models import User
from realtime import handlers as realtime_handlers
from realtime.handlers import Context
from realtime.protocol import ProtocolError
from realtime.tests.test_socket import APP, WAIT, msg, sign_in
from realtime.tests.socket_client import SocketClient

from . import services
from .models import Game, Player, Room, Token
from .tests import IN_MEMORY_LAYER, LOCAL_CACHE, GameApiTestCase


class SocketActionTestCase(GameApiTestCase):
    def user(self, player_id):
        return Player.objects.get(id=player_id).user

    def call(self, type, player_id=None, *, user=None, **data):
        entry = realtime_handlers.get(type)
        self.assertIsNotNone(entry, f"no handler for {type}")
        return entry.fn(Context(user or self.user(player_id), "test-session"), data)

    def refused(self, type, player_id=None, *, user=None, **data):
        with self.assertRaises(ProtocolError) as caught:
            self.call(type, player_id, user=user, **data)
        return caught.exception.code


class RollAndMoveTests(SocketActionTestCase):
    def test_roll_then_move_by_game_id(self):
        code, host, _guest = self.two_humans()
        game = self.game(code)
        self.dice(6)

        ack = self.call("roll_dice", host, game_id=game.id, expected_version=game.version)
        self.assertEqual(ack["dice"], 6)
        self.assertEqual(sorted(ack["movable_token_ids"]), sorted(self.token_ids(code, host)))
        self.assertEqual(ack["version"], self.game(code).version)

        token = self.token_ids(code, host)[2]
        ack = self.call("move_token", host, game_id=str(game.id), token_id=token, expected_version=ack["version"])
        self.assertEqual(ack, {"version": self.game(code).version, "finished": False, "winner": False})
        self.assertEqual(Token.objects.get(id=token).position, 0)
        self.assertEqual([m["type"] for m in self.sent][:2], ["dice_rolled", "token_moved"])
        self.assertEqual(self.sent[1]["token_id"], token)

    def test_room_code_and_token_index_work_too(self):
        code, host, _guest = self.two_humans()
        self.dice(6)
        self.call("roll_dice", host, code=code.lower())
        self.call("move_token", host, code=code, token_index=1)
        self.assertEqual(Token.objects.get(id=self.token_ids(code, host)[1]).position, 0)

    def test_acting_on_an_old_version_is_refused_and_changes_nothing(self):
        code, host, _guest = self.two_humans()
        version = self.game(code).version
        self.dice(6)
        self.assertEqual(self.refused("roll_dice", host, code=code, expected_version=version - 1), "stale_version")
        self.assertEqual(self.game(code).version, version)
        self.assertEqual(self.sent, [])

    def test_engine_refusals_keep_their_code(self):
        code, host, guest = self.two_humans()
        self.assertEqual(self.refused("roll_dice", guest, code=code), "not_your_turn")
        self.assertEqual(self.refused("move_token", host, code=code, token_index=0), "wrong_phase")
        self.dice(3)  # no six: nothing can leave base, the turn passes
        self.call("roll_dice", host, code=code)
        self.assertEqual(self.refused("roll_dice", host, code=code), "not_your_turn")

    def test_only_your_own_tokens(self):
        code, host, guest = self.two_humans()
        self.dice(6)
        self.call("roll_dice", host, code=code)
        other = self.token_ids(code, guest)[0]
        self.assertEqual(self.refused("move_token", host, code=code, token_id=other), "token_not_found")
        self.assertEqual(self.refused("move_token", host, code=code), "invalid_request")
        self.assertEqual(self.refused("move_token", host, code=code, token_index="two"), "invalid_request")

    def test_the_ai_plays_after_you(self):
        account = self.new_account()
        code, host = self.create_room(account=account)
        self.start(code, host)  # alone: an AI takes the other seat
        self.dice(3, 6, 2)  # you: 3 (turn passes); AI: 6 then 2
        self.call("roll_dice", host, code=code)
        game = self.game(code)
        self.assertEqual(str(game.current_turn_id), host)  # the AI played inline and passed back
        self.assertGreater(len([m for m in self.sent if m["type"] == "dice_rolled"]), 1)


class WhoMayActTests(SocketActionTestCase):
    def test_people_without_a_seat_are_refused(self):
        code, _host, _guest = self.two_humans()
        stranger = User.objects.create_guest()
        self.assertEqual(self.refused("roll_dice", user=stranger, code=code), "not_in_game")
        self.assertEqual(self.refused("request_state", user=stranger, code=code), "not_in_game")

    def test_unknown_games_rooms_and_missing_ids(self):
        code, host, _guest = self.two_humans()
        self.assertEqual(self.refused("roll_dice", host, game_id=999999), "game_not_found")
        self.assertEqual(self.refused("roll_dice", host, code="ZZZZZZ"), "room_not_found")
        self.assertEqual(self.refused("roll_dice", host), "invalid_request")
        self.assertEqual(self.refused("roll_dice", host, game_id="abc"), "invalid_request")
        self.assertEqual(self.refused("roll_dice", host, code=code, expected_version="x"), "invalid_request")

    def test_a_room_that_has_not_started(self):
        code, host = self.create_room()
        self.assertEqual(self.refused("roll_dice", host, code=code), "game_not_started")

    def test_old_games_say_so(self):
        code, host, _guest = self.two_humans()
        Game.objects.filter(room__code=code).update(state=None)
        self.assertEqual(self.refused("roll_dice", host, code=code), "legacy_game")


class GenericActionTests(SocketActionTestCase):
    def setUp(self):
        super().setUp()
        from game_platform.tests.toy_game import RaceGame

        game_platform.register(RaceGame())
        self.addCleanup(game_platform.unregister, "race")

    def test_any_game_takes_its_own_player_actions(self):
        account = self.new_account()
        r = self.post("create-room", as_account=account, game_type="race")
        code, host = r.data["room"]["code"], str(r.data["player"]["id"])
        self.access[host] = account
        self.start(code, host)
        services.SERVER_RANDOM = game_platform.ScriptedRandom([2, 2])
        self.addCleanup(setattr, services, "SERVER_RANDOM", game_platform.SecureRandom())

        # Ludo's own requests refuse; game_action works for every game.
        self.assertEqual(self.refused("roll_dice", host, code=code), "wrong_game")
        self.assertEqual(self.refused("move_token", host, code=code, token_index=0), "wrong_game")
        ack = self.call("game_action", host, code=code, action={"type": "draw"}, expected_version=0)
        self.assertEqual(ack["version"], 1)  # your own draw
        game = self.game(code)
        self.assertEqual((game.version, game.state["scores"]), (2, [3, 3]))  # then the AI drew

    def test_only_the_players_own_action_types(self):
        code, host, _guest = self.two_humans()
        for action in ({"type": "timeout"}, {"type": "bot"}, {"type": "forfeit"}, {}):
            self.assertEqual(self.refused("game_action", host, code=code, action=action), "invalid_action")
        self.assertEqual(self.refused("game_action", host, code=code, action="roll"), "invalid_request")

    def test_the_seat_comes_from_the_account_not_the_request(self):
        code, host, guest = self.two_humans()
        self.dice(6)
        # The guest names the host's seat: the server uses the guest's own seat.
        action = {"type": "roll", "player_id": host}
        self.assertEqual(self.refused("game_action", guest, code=code, action=action), "not_your_turn")
        ack = self.call("game_action", host, code=code, action={"type": "roll", "player_id": guest})
        self.assertEqual(ack["dice"], 6)


class LeaveAndStateTests(SocketActionTestCase):
    def test_request_state_is_the_snapshot(self):
        code, host, _guest = self.two_humans()
        state = self.call("request_state", host, code=code)
        expected = services.game_snapshot(Room.objects.get(code=code))
        expected.pop("type")
        self.assertEqual(state, expected)
        self.assertEqual(state["version"], self.game(code).version)
        self.assertEqual(state["room_id"], str(Room.objects.get(code=code).id))
        self.assertFalse(realtime_handlers.get("request_state").changes_state)

    def test_request_state_before_the_start(self):
        code, host = self.create_room()
        state = self.call("request_state", host, code=code)
        self.assertEqual((state["game_id"], state["version"]), (None, None))
        self.assertEqual([p["id"] for p in state["players"]], [host])
        self.assertEqual(state["room_id"], str(Room.objects.get(code=code).id))

    def test_leaving_a_started_game_forfeits(self):
        code, host, guest = self.two_humans()
        self.assertEqual(self.call("leave_game", guest, code=code), {"left": True})
        game = self.game(code)
        self.assertTrue(game.is_finished)
        self.assertEqual(game.state["winner_id"], host)
        self.assertIn("player_forfeited", [m["type"] for m in self.sent])


@override_settings(
    GAME_BOTS_INLINE=True,
    GAME_BOT_DELAY_SECONDS=(0, 0),
    CHANNEL_LAYERS=IN_MEMORY_LAYER,
    CACHES=LOCAL_CACHE,
)
class SocketEndToEndTests(TransactionTestCase):
    """Two players on real sockets: one acts, both see it on game/<id>."""

    def setUp(self):
        cache.clear()
        self.addCleanup(setattr, services, "SERVER_RANDOM", services.SERVER_RANDOM)

    def test_play_over_the_socket(self):
        def set_up():
            host_user, host_pair = sign_in()
            guest_user, guest_pair = sign_in()
            room = Room.objects.create(code="SOCKET", is_started=True)
            host = Player.objects.create(room=room, user=host_user, name="Host", color="red", is_host=True)
            Player.objects.create(room=room, user=guest_user, name="Guest", color="blue")
            game, _ = services.start_game(room, host)
            return game, host_pair, guest_pair

        async def open_as(pair):
            socket = SocketClient(APP, "/ws/v1/")
            await socket.connect()
            await socket.send_json_to(msg("auth", "a", access_token=pair.access))
            self.assertEqual((await socket.receive_json_from(WAIT))["type"], "ack")
            return socket

        async def until_reply(socket, req_id):
            """Messages up to the request's own reply (events may come first)."""
            seen = []
            while True:
                message = await socket.receive_json_from(WAIT)
                seen.append(message)
                if message.get("req_id") == req_id:
                    return message, seen

        async def scenario():
            game, host_pair, guest_pair = await database_sync_to_async(set_up)()
            host, guest = await open_as(host_pair), await open_as(guest_pair)
            channel = f"game/{game.id}"
            for socket in (host, guest):
                await socket.send_json_to(msg("subscribe", "s", channel=channel))
                self.assertEqual((await socket.receive_json_from(WAIT))["type"], "ack")
                snapshot = await socket.receive_json_from(WAIT)
                self.assertEqual(snapshot["type"], "state_snapshot")
            version = snapshot["data"]["version"]

            services.SERVER_RANDOM = game_platform.ScriptedRandom([5])  # a six
            await host.send_json_to(msg("roll_dice", "r1", game_id=game.id, expected_version=version))
            reply, _ = await until_reply(host, "r1")
            self.assertEqual((reply["type"], reply["data"]["dice"]), ("ack", 6))
            event = await guest.receive_json_from(WAIT)
            self.assertEqual((event["type"], event["channel"]), ("dice_rolled", channel))
            self.assertEqual(event["version"], reply["data"]["version"])

            # The guest may not act for the host, and an old version is refused.
            await guest.send_json_to(msg("roll_dice", "g1", code="SOCKET"))
            refusal, _ = await until_reply(guest, "g1")
            self.assertEqual((refusal["type"], refusal["code"]), ("error", "not_your_turn"))
            await host.send_json_to(msg("move_token", "m1", code="SOCKET", token_index=0, expected_version=version))
            refusal, _ = await until_reply(host, "m1")
            self.assertEqual((refusal["type"], refusal["code"]), ("error", "stale_version"))

            await host.disconnect()
            await guest.disconnect()

        async_to_sync(scenario)()
