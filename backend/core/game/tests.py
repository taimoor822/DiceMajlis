"""
End-to-end tests for the live game: REST endpoints → game.services → ludo_engine
→ database mirror → socket messages. Bots run inline (no threads) and dice are
scripted where a test needs a specific roll.
"""

from dataclasses import replace
from datetime import timedelta
from io import StringIO
from unittest import mock

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

import game_platform
import ludo_engine as le
from accounts import tokens as account_tokens
from accounts.models import User
from ludo_engine import GameState, TurnPhase

from . import services, timers
from .consumers import LobbyConsumer
from .models import Game, GameAction, Player, Token
from .tables.ludo import token_ids_by_player

IN_MEMORY_LAYER = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
LOCAL_CACHE = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}


@override_settings(
    GAME_BOTS_INLINE=True,
    GAME_BOT_DELAY_SECONDS=(0, 0),
    CHANNEL_LAYERS=IN_MEMORY_LAYER,
    CACHES=LOCAL_CACHE,
)
class GameApiTestCase(TestCase):
    capture_broadcasts = True

    def setUp(self):
        cache.clear()
        self.api = APIClient()
        self.sent = []  # game events, in order
        self.lobby = []  # players_updated messages
        self.access = {}  # seat (player) id -> that account's access token
        if self.capture_broadcasts:
            patcher = mock.patch("game.services.broadcast", side_effect=self._capture)
            patcher.start()
            self.addCleanup(patcher.stop)

    def _capture(self, code, messages):
        for message in messages:
            if message["type"] == "game_event":
                self.sent.append(message["payload"])
            else:
                self.lobby.append(message)

    # ---- helpers ---------------------------------------------------------

    def new_account(self):
        """A fresh guest account signed in on its own phone; returns its access token."""
        user = User.objects.create_guest()
        return account_tokens.start_session(user, device_id="test-device", platform="other").access

    def post(self, endpoint, *, player_id=None, as_account=None, signed_in=True, **data):
        """
        POST like the app. Signed in as the account sitting at ``player_id``, or
        ``as_account`` (an access token), or else a brand-new guest. The seat
        itself is never sent: the server finds it from the account.
        """
        headers = {}
        if signed_in:
            token = as_account or self.access.get(str(player_id)) or self.new_account()
            headers["HTTP_AUTHORIZATION"] = f"Bearer {token}"
        return self.api.post(f"/api/game/{endpoint}/", data, format="json", **headers)

    def create_room(self, color="red", max_players=4, account=None):
        account = account or self.new_account()
        r = self.post("create-room", as_account=account, color=color, max_players=max_players)
        self.assertEqual(r.status_code, 201, r.data)
        player_id = str(r.data["player"]["id"])
        self.access[player_id] = account
        return r.data["room"]["code"], player_id

    def join(self, code, color="blue", account=None):
        account = account or self.new_account()
        r = self.post("join-room", as_account=account, code=code, color=color)
        self.assertEqual(r.status_code, 200, r.data)
        player_id = str(r.data["player"]["id"])
        self.access[player_id] = account
        return player_id

    def start(self, code, host):
        r = self.post("start-game", code=code, player_id=host)
        self.assertEqual(r.status_code, 200, r.data)

    def two_humans(self):
        code, host = self.create_room()
        guest = self.join(code)
        self.start(code, host)
        return code, host, guest

    def game(self, code):
        return Game.objects.get(room__code=code)

    def state(self, code):
        return GameState.from_dict(self.game(code).state)

    def token_ids(self, code, player_id):
        return token_ids_by_player(self.game(code).room)[player_id]

    def dice(self, *values):
        """Script the server's dice: each roll takes the next value."""
        patcher = mock.patch.object(
            services, "SERVER_RANDOM", game_platform.ScriptedRandom(v - 1 for v in values)
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def set_positions(self, code, positions):
        """Put tokens anywhere (engine state + DB mirror), keeping it the same player's turn."""
        game = self.game(code)
        state = GameState.from_dict(game.state)
        players = tuple(
            replace(p, tokens=tuple(positions.get(p.player_id, p.tokens))) for p in state.players
        )
        game.state = replace(state, players=players).to_dict()
        game.save(update_fields=["state"])
        ids = token_ids_by_player(game.room)
        for player_id, tokens in positions.items():
            for index, progress in enumerate(tokens):
                Token.objects.filter(id=ids[player_id][index]).update(
                    position=progress, is_finished=progress == 56
                )

    def sent_types(self):
        return [m["type"] for m in self.sent]


class StartGameTests(GameApiTestCase):
    def test_players_keep_their_colour_seat_and_clashes_get_a_free_seat(self):
        code, host = self.create_room(color="red")
        a = self.join(code, color="blue")
        b = self.join(code, color="blue")  # two people asking for the same colour
        self.start(code, host)

        seats = {p.player_id: p.seat for p in self.state(code).players}
        self.assertEqual((seats[host], seats[a], seats[b]), (0, 1, 2))
        self.assertEqual(Player.objects.get(id=b).color, "green")
        self.assertEqual(Token.objects.filter(player__room__code=code).count(), 12)
        self.assertTrue(all(t.position == -1 for t in Token.objects.filter(player__room__code=code)))

    def test_solo_host_gets_a_bot_in_the_opposite_seat(self):
        code, host = self.create_room(color="red")
        self.start(code, host)
        bot = Player.objects.get(room__code=code, is_bot=True)
        self.assertEqual(bot.color, "green")
        self.assertEqual(self.state(code).player(str(bot.id)).seat, 2)
        self.assertEqual(self.state(code).current_player.player_id, host)

    def test_cannot_start_twice(self):
        code, host, _ = self.two_humans()
        r = self.post("start-game", code=code, player_id=host)
        self.assertEqual(r.status_code, 400)

    def test_only_the_host_can_start(self):
        code, host = self.create_room()
        guest = self.join(code)
        r = self.post("start-game", code=code, player_id=guest)
        self.assertEqual((r.status_code, r.data["code"]), (403, "not_host"))
        r = self.post("start-game")
        self.assertEqual((r.status_code, r.data["code"]), (400, "invalid_input"))


class RollAndMoveTests(GameApiTestCase):
    def test_roll_uses_server_dice_and_lists_movable_tokens(self):
        code, host, _ = self.two_humans()
        self.dice(6)
        r = self.post("roll-dice", code=code, player_id=host)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["dice"], 6)

        rolled = self.sent[0]
        self.assertEqual(rolled["type"], "dice_rolled")
        self.assertEqual(rolled["movable_token_ids"], self.token_ids(code, host))
        self.assertEqual(rolled["version"], 1)
        self.assertEqual(GameAction.objects.get().action["value"], 6)
        self.assertEqual(self.game(code).last_dice, 6)

    def test_client_cannot_choose_the_dice_value(self):
        code, host, _ = self.two_humans()
        self.dice(2)
        r = self.post("roll-dice", code=code, player_id=host, dice=6, value=6)
        self.assertEqual(r.data["dice"], 2)

    def test_not_your_turn(self):
        code, _, guest = self.two_humans()
        r = self.post("roll-dice", code=code, player_id=guest)
        self.assertEqual((r.status_code, r.data["code"]), (403, "not_your_turn"))

    def test_move_before_rolling_is_rejected(self):
        code, host, _ = self.two_humans()
        r = self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, host)[0])
        self.assertEqual((r.status_code, r.data["code"]), (400, "wrong_phase"))

    def test_cannot_move_someone_elses_token(self):
        code, host, guest = self.two_humans()
        self.dice(6)
        self.post("roll-dice", code=code, player_id=host)
        r = self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, guest)[0])
        self.assertEqual(r.status_code, 404)

    def test_no_legal_move_passes_the_turn(self):
        code, host, guest = self.two_humans()
        self.dice(3)
        self.post("roll-dice", code=code, player_id=host)
        self.assertEqual(self.sent_types(), ["dice_rolled", "turn_changed"])
        self.assertEqual(self.sent[1]["player_id"], guest)
        game = self.game(code)
        self.assertEqual((str(game.current_turn_id), game.last_dice), (guest, None))

    def test_six_enters_a_token_and_keeps_the_turn(self):
        code, host, _ = self.two_humans()
        self.dice(6)
        self.post("roll-dice", code=code, player_id=host)
        token = self.token_ids(code, host)[2]
        r = self.post("move-token", code=code, player_id=host, token_id=token)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(Token.objects.get(id=token).position, 0)
        moved = next(m for m in self.sent if m["type"] == "token_moved")
        self.assertEqual((moved["token_id"], moved["from"], moved["to"]), (token, -1, 0))
        turn = next(m for m in self.sent if m["type"] == "turn_changed")
        self.assertEqual((turn["player_id"], turn["extra_turn"]), (host, True))


class CaptureTests(GameApiTestCase):
    def test_capture_happens_on_the_same_board_square(self):
        code, host, guest = self.two_humans()  # host red seat 0, guest blue seat 1
        self.set_positions(code, {host: [2, -1, -1, -1], guest: [44, -1, -1, -1]})  # 44 = square 5
        self.dice(3)
        self.post("roll-dice", code=code, player_id=host)
        self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, host)[0])

        victim = self.token_ids(code, guest)[0]
        self.assertEqual(Token.objects.get(id=victim).position, -1)
        moved = next(m for m in self.sent if m["type"] == "token_moved")
        self.assertEqual(moved["killed"], [victim])
        self.assertEqual(str(self.game(code).current_turn_id), host)  # capture bonus

    def test_same_step_count_on_different_squares_is_not_a_capture(self):
        # The old server compared step counts across players and captured here.
        code, host, guest = self.two_humans()
        self.set_positions(code, {host: [2, -1, -1, -1], guest: [5, -1, -1, -1]})
        self.dice(3)
        self.post("roll-dice", code=code, player_id=host)
        self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, host)[0])
        self.assertEqual(Token.objects.get(id=self.token_ids(code, guest)[0]).position, 5)


class FinishTests(GameApiTestCase):
    def test_a_human_can_bring_every_token_home_and_win(self):
        code, host, guest = self.two_humans()
        self.set_positions(code, {host: [54, 56, 56, 56]})
        self.dice(2)
        self.post("roll-dice", code=code, player_id=host)
        r = self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, host)[0])

        self.assertEqual(r.data["winner"], True)
        game = self.game(code)
        self.assertTrue(game.is_finished)
        self.assertTrue(all(t.is_finished for t in Token.objects.filter(player_id=host)))
        finished = next(m for m in self.sent if m["type"] == "game_finished")
        self.assertEqual(finished["winner_id"], host)
        self.assertEqual([s["player_id"] for s in finished["standings"]], [host, guest])

        r = self.post("roll-dice", code=code, player_id=guest)
        self.assertEqual((r.status_code, r.data["code"]), (400, "game_not_active"))

    def test_home_needs_an_exact_roll(self):
        code, host, guest = self.two_humans()
        self.set_positions(code, {host: [54, 56, 56, 56]})
        self.dice(5)
        self.post("roll-dice", code=code, player_id=host)
        self.assertEqual(str(self.game(code).current_turn_id), guest)


class BotGameTests(GameApiTestCase):
    def test_a_full_game_against_the_bot_finishes_and_replays_exactly(self):
        code, host = self.create_room()
        self.start(code, host)

        for _ in range(4000):
            state = self.state(code)
            if state.is_finished:
                break
            self.assertEqual(state.current_player.player_id, host, "bot left the turn hanging")
            if state.phase is TurnPhase.AWAITING_ROLL:
                r = self.post("roll-dice", code=code, player_id=host)
            else:
                index = le.legal_moves(state)[0].token_index
                r = self.post("move-token", code=code, player_id=host,
                              token_id=self.token_ids(code, host)[index])
            self.assertEqual(r.status_code, 200, r.data)

        game = self.game(code)
        state = GameState.from_dict(game.state)
        self.assertTrue(state.is_finished)
        self.assertIsNotNone(state.winner_id)

        actions = [a.action for a in game.actions.all()]
        self.assertEqual(len(actions), game.version)
        rebuilt = le.replay(GameState.from_dict(game.initial_state), actions)
        self.assertEqual(rebuilt, state)

        # DB mirror matches the engine for every token.
        ids = token_ids_by_player(game.room)
        for player in state.players:
            for index, progress in enumerate(player.tokens):
                self.assertEqual(Token.objects.get(id=ids[player.player_id][index]).position, progress)


class SafetyTests(GameApiTestCase):
    def test_stale_or_tampered_state_is_rejected(self):
        code, host, _ = self.two_humans()
        Game.objects.filter(room__code=code).update(version=7)
        r = self.post("roll-dice", code=code, player_id=host)
        self.assertEqual((r.status_code, r.data["code"]), (409, "stale_version"))

    def test_games_started_before_the_update_ask_for_a_new_game(self):
        code, host, _ = self.two_humans()
        Game.objects.filter(room__code=code).update(state=None)
        r = self.post("roll-dice", code=code, player_id=host)
        self.assertEqual((r.status_code, r.data["code"]), (409, "legacy_game"))

    def test_unknown_room(self):
        r = self.post("roll-dice", code="NOPE")
        self.assertEqual((r.status_code, r.data["code"]), (404, "room_not_found"))


class SocketDeliveryTests(GameApiTestCase):
    capture_broadcasts = False

    def test_events_reach_everyone_in_the_room_group(self):
        code, host, _ = self.two_humans()
        layer = get_channel_layer()
        channel = async_to_sync(layer.new_channel)()
        async_to_sync(layer.group_add)(services.group_name(code), channel)

        self.dice(3)
        self.post("roll-dice", code=code, player_id=host)
        first = async_to_sync(layer.receive)(channel)
        self.assertEqual(first["type"], "game_event")
        self.assertEqual(first["payload"]["type"], "dice_rolled")
        self.assertEqual(first["payload"]["dice"], 3)

    def test_consumer_forwards_engine_events_unchanged(self):
        consumer = LobbyConsumer()
        consumer.send = mock.AsyncMock()
        payload = {"type": "dice_rolled", "dice": 4, "version": 9}
        async_to_sync(consumer.game_event)({"type": "game_event", "payload": payload})
        consumer.send.assert_awaited_once()
        self.assertIn('"version": 9', consumer.send.await_args.kwargs["text_data"])


class TurnTimerTests(GameApiTestCase):
    """game/timers.py: overdue turns are auto-played; idle players are removed."""

    def later(self, seconds=3600):
        return timezone.now() + timedelta(seconds=seconds)

    def test_a_new_game_starts_the_clock_for_the_first_turn(self):
        code, _, _ = self.two_humans()
        left = services.seconds_left(self.game(code).turn_deadline)
        self.assertTrue(28 <= left <= 30, left)

    def test_each_new_turn_tells_the_app_how_long_it_has(self):
        code, host, guest = self.two_humans()
        self.dice(3)
        self.post("roll-dice", code=code, player_id=host)
        turn = next(m for m in self.sent if m["type"] == "turn_changed")
        self.assertEqual(turn["player_id"], guest)
        self.assertTrue(28 <= turn["seconds_left"] <= 30)
        self.assertEqual(turn["warning_seconds"], 10)

    def test_rolling_does_not_reset_the_clock_moving_to_a_new_turn_does(self):
        code, host, _ = self.two_humans()
        game = self.game(code)
        game.turn_deadline = timezone.now() + timedelta(seconds=12)
        game.save(update_fields=["turn_deadline"])
        self.dice(6)
        self.post("roll-dice", code=code, player_id=host)  # same turn: still ~12s
        self.assertLessEqual(services.seconds_left(self.game(code).turn_deadline), 12)
        self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, host)[0])
        self.assertGreaterEqual(services.seconds_left(self.game(code).turn_deadline), 28)  # extra turn

    def test_nothing_happens_before_the_deadline(self):
        code, _, _ = self.two_humans()
        self.assertEqual(timers.process_due_turns(), 0)
        self.assertEqual(self.game(code).version, 0)

    def test_an_idle_player_is_played_for_and_the_turn_moves_on(self):
        code, host, guest = self.two_humans()
        self.dice(4)
        self.assertEqual(timers.process_due_turns(now=self.later()), 1)

        state = self.state(code)
        self.assertEqual(state.player(host).missed_turns, 1)
        self.assertEqual(state.current_player.player_id, guest)
        timeout = next(m for m in self.sent if m["type"] == "player_timeout")
        self.assertEqual((timeout["player_id"], timeout["missed_turns"], timeout["max_missed_turns"]), (host, 1, 3))
        self.assertEqual(GameAction.objects.last().action["type"], "timeout")

    def test_idle_player_with_a_rolled_dice_gets_moved(self):
        code, host, guest = self.two_humans()
        self.set_positions(code, {host: [10, -1, -1, -1]})
        self.dice(4)
        self.post("roll-dice", code=code, player_id=host)  # rolled, then walked away
        timers.process_due_turns(now=self.later())
        self.assertEqual(Token.objects.get(id=self.token_ids(code, host)[0]).position, 14)
        self.assertEqual(str(self.game(code).current_turn_id), guest)

    def test_three_missed_turns_in_a_row_remove_the_player(self):
        code, host, guest = self.two_humans()
        self.dice(*[3] * 10)  # nobody can ever move, so turns just time out
        for hour in range(1, 6):  # host, guest, host, guest, host — each sweep later than the last
            timers.process_due_turns(now=self.later(3600 * hour))

        state = self.state(code)
        self.assertEqual(state.player(host).status.value, "forfeited")
        self.assertEqual(state.winner_id, guest)
        self.assertTrue(self.game(code).is_finished)
        self.assertIsNone(self.game(code).turn_deadline)
        self.assertIn("player_forfeited", self.sent_types())
        self.assertEqual(timers.process_due_turns(now=self.later(3600 * 24)), 0)  # finished: ignored

    def test_playing_resets_the_missed_turn_count(self):
        code, host, guest = self.two_humans()
        self.dice(3, 3, 3)
        timers.process_due_turns(now=self.later())  # host misses once
        self.post("roll-dice", code=code, player_id=guest)
        self.post("roll-dice", code=code, player_id=host)  # host is back
        self.assertEqual(self.state(code).player(host).missed_turns, 0)

    def test_a_timer_for_a_turn_that_already_ended_does_nothing(self):
        code, host, _ = self.two_humans()
        stale_turn = self.state(code).turn_number
        Game.objects.filter(room__code=code).update(turn_deadline=timezone.now() - timedelta(seconds=1))
        self.dice(3)
        self.post("roll-dice", code=code, player_id=host)  # host acts at the last moment
        Game.objects.filter(room__code=code).update(turn_deadline=timezone.now() - timedelta(seconds=1))
        with self.assertRaises(le.InvalidAction):
            services.perform(code, {"type": "timeout", "turn_number": stale_turn})

    def test_timeouts_before_the_deadline_are_refused(self):
        code, _, _ = self.two_humans()
        with self.assertRaises(services.TimerNotDue):
            services.perform(code, {"type": "timeout"})

    def test_an_overdue_bot_just_plays_without_penalty(self):
        code, host = self.create_room()
        self.start(code, host)
        bot = str(Player.objects.get(room__code=code, is_bot=True).id)
        self.dice(*[3] * 10)
        self.post("roll-dice", code=code, player_id=host)  # passes to bot, bot plays inline
        # Simulate a dead bot thread: hand the turn back to the bot and let the clock run out.
        game = self.game(code)
        state = replace(self.state(code), current_index=self.state(code).index_of(bot))
        Game.objects.filter(pk=game.pk).update(
            state=state.to_dict(), current_turn_id=bot,
            turn_deadline=timezone.now() - timedelta(seconds=1),
        )
        self.assertEqual(timers.process_due_turns(), 1)
        self.assertEqual(self.state(code).player(bot).missed_turns, 0)
        self.assertEqual(self.state(code).current_player.player_id, host)

    def test_reconnecting_clients_get_the_time_left(self):
        code, _, _ = self.two_humans()
        consumer = LobbyConsumer()
        consumer.room_code = code
        _players, snapshot = async_to_sync(consumer.get_room_info)()
        self.assertTrue(28 <= snapshot["seconds_left"] <= 30)
        self.assertEqual(snapshot["warning_seconds"], 10)

    def test_management_command_runs_one_sweep(self):
        self.two_humans()
        Game.objects.update(turn_deadline=timezone.now() - timedelta(seconds=1))
        self.dice(3)
        out = StringIO()
        call_command("run_turn_timers", "--once", stdout=out)
        self.assertIn("Handled 1", out.getvalue())


class RoomInputTests(GameApiTestCase):
    """The server checks what the app sends; bad input gets 400, never a crash."""

    def test_room_options_come_from_the_rules(self):
        r = self.api.get("/api/game/room-options/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(
            r.data,
            {"game_type": "ludo", "variant": "classic", "player_counts": [2, 3, 4], "default_player_count": 4},
        )

    def test_room_size_must_be_one_the_rules_allow(self):
        for size in (1, 0, 5, -2, "abc", True, None):
            r = self.post("create-room", max_players=size)
            self.assertEqual((r.status_code, r.data["code"]), (400, "invalid_input"), size)
            self.assertIn("max_players", r.data["fields"])
        r = self.post("create-room", max_players="3")
        self.assertEqual((r.status_code, r.data["room"]["max_players"]), (201, 3))

    def test_colours_are_checked(self):
        r = self.post("create-room", color="purple")
        self.assertEqual((r.status_code, r.data["code"]), (400, "invalid_input"))

    def test_names_come_from_the_account_and_seats_are_picked_by_the_server(self):
        host = self.new_account()
        r = self.post("create-room", as_account=host, max_players=4, name="Somebody else")
        code = r.data["room"]["code"]
        host_user = User.objects.get(seats__id=r.data["player"]["id"])
        self.assertEqual(
            (r.data["player"]["name"], r.data["player"]["color"]), (host_user.public_name, "red")
        )
        joined = [self.post("join-room", code=code).data["player"] for _ in range(3)]
        self.assertEqual([p["color"] for p in joined], ["green", "blue", "yellow"])
        for seat in joined:
            self.assertEqual(seat["name"], User.objects.get(seats__id=seat["id"]).public_name)

    def test_join_accepts_any_case_and_reports_why_it_failed(self):
        code, _ = self.create_room()
        self.assertEqual(self.post("join-room", code=f" {code.lower()} ").status_code, 200)
        r = self.post("join-room", code="ZZZZ")
        self.assertEqual((r.status_code, r.data["code"]), (404, "room_not_found"))
        r = self.post("join-room")
        self.assertEqual((r.status_code, r.data["code"]), (400, "invalid_input"))

    def test_a_full_room_turns_people_away(self):
        r = self.post("create-room", max_players=2)
        code = r.data["room"]["code"]
        self.assertEqual(self.post("join-room", code=code).status_code, 200)
        r = self.post("join-room", code=code)
        self.assertEqual((r.status_code, r.data["code"]), (400, "room_full"))

    def test_cannot_join_a_started_game(self):
        code, _, _ = self.two_humans()
        r = self.post("join-room", code=code)
        self.assertEqual((r.status_code, r.data["code"]), (400, "game_already_started"))

    def test_room_codes_use_the_secure_random_generator(self):
        account = self.new_account()  # signing up uses secrets.choice too
        with mock.patch("game.views.secrets.choice", return_value="Q") as choice:
            r = self.post("create-room", as_account=account)
        self.assertEqual(r.data["room"]["code"], "QQQQ")
        self.assertEqual(choice.call_count, 4)


class AccountSeatTests(GameApiTestCase):
    """Rooms belong to accounts: your seat is the one your account holds."""

    def test_rooms_need_a_signed_in_account(self):
        code, host = self.create_room()
        for endpoint in ("create-room", "join-room", "start-game", "roll-dice", "move-token", "leave-room"):
            r = self.post(endpoint, signed_in=False, code=code)
            self.assertEqual((r.status_code, r.data["code"]), (401, "not_authenticated"), endpoint)
        r = self.api.get("/api/game/room-options/")
        self.assertEqual(r.status_code, 200)  # reading the rules needs no account

    def test_seats_are_linked_to_accounts_and_bots_have_none(self):
        code, host = self.create_room()
        self.start(code, host)
        self.assertIsNotNone(Player.objects.get(id=host).user)
        self.assertIsNone(Player.objects.get(room__code=code, is_bot=True).user)

    def test_you_cannot_act_in_a_room_you_are_not_in(self):
        code, host, _ = self.two_humans()
        outsider = self.new_account()
        for endpoint in ("start-game", "roll-dice"):
            r = self.post(endpoint, as_account=outsider, code=code)
            self.assertEqual((r.status_code, r.data["code"]), (403, "not_in_room"), endpoint)
        r = self.post(
            "move-token", as_account=outsider, code=code, token_id=self.token_ids(code, host)[0]
        )
        self.assertEqual((r.status_code, r.data["code"]), (403, "not_in_room"))

    def test_you_only_ever_play_your_own_seat(self):
        code, host, guest = self.two_humans()
        # It's the host's turn; the guest asking to roll is the guest rolling.
        r = self.post("roll-dice", code=code, player_id=guest)
        self.assertEqual((r.status_code, r.data["code"]), (403, "not_your_turn"))
        self.dice(6)
        self.post("roll-dice", code=code, player_id=host)
        r = self.post("move-token", code=code, player_id=guest, token_id=self.token_ids(code, host)[0])
        self.assertEqual((r.status_code, r.data["code"]), (404, "not_your_token"))

    def test_joining_twice_gives_back_the_same_seat(self):
        code, host = self.create_room()
        account = self.new_account()
        first = self.join(code, account=account)
        second = self.join(code, account=account)
        self.assertEqual(first, second)
        self.assertEqual(Player.objects.filter(room__code=code).count(), 2)
        # The host joining their own room is fine too.
        r = self.post("join-room", player_id=host, code=code)
        self.assertEqual((r.status_code, str(r.data["player"]["id"])), (200, host))

    def test_you_can_rejoin_a_started_game_you_are_in(self):
        code, host, guest = self.two_humans()
        r = self.post("join-room", player_id=guest, code=code)
        self.assertEqual(r.status_code, 200)
        self.assertEqual((str(r.data["player"]["id"]), r.data["room"]["is_started"]), (guest, True))

    def test_one_game_at_a_time(self):
        code, host, _ = self.two_humans()
        account = self.access[host]
        r = self.post("create-room", as_account=account)
        self.assertEqual((r.status_code, r.data["code"]), (409, "already_in_game"))
        self.assertEqual(r.data["room_code"], code)
        other, _ = self.create_room()
        r = self.post("join-room", as_account=account, code=other)
        self.assertEqual((r.status_code, r.data["code"]), (409, "already_in_game"))

    def test_a_new_room_replaces_the_one_you_were_waiting_in(self):
        account = self.new_account()
        alone, _ = self.create_room(account=account)
        shared, host = self.create_room()
        guest = self.join(shared, account=account)
        self.assertFalse(Player.objects.filter(room__code=alone).exists())  # empty room closed
        self.create_room(account=account)
        self.assertFalse(Player.objects.filter(id=guest).exists())
        self.assertTrue(Player.objects.filter(id=host).exists())


class LeaveRoomTests(GameApiTestCase):
    def test_leaving_before_the_start_frees_the_seat(self):
        code, host = self.create_room()
        guest = self.join(code)
        self.lobby.clear()
        r = self.post("leave-room", player_id=guest, code=code)
        self.assertEqual((r.status_code, r.data), (200, {"status": "left"}))
        self.assertFalse(Player.objects.filter(id=guest).exists())
        self.assertEqual(self.lobby[-1]["type"], "players_updated")
        self.assertEqual([p["id"] for p in self.lobby[-1]["players"]], [host])

    def test_the_host_role_passes_on_and_an_empty_room_closes(self):
        code, host = self.create_room()
        guest = self.join(code)
        self.post("leave-room", player_id=host, code=code)
        self.assertTrue(Player.objects.get(id=guest).is_host)
        self.post("leave-room", player_id=guest, code=code)
        self.assertFalse(Player.objects.filter(room__code=code).exists())
        self.assertEqual(self.post("join-room", code=code).data["code"], "room_not_found")

    def test_leaving_a_game_forfeits_it(self):
        code, host, guest = self.two_humans()
        r = self.post("leave-room", player_id=guest, code=code)
        self.assertEqual(r.status_code, 200)
        state = self.state(code)
        self.assertEqual(state.player(guest).status, le.PlayerStatus.FORFEITED)
        self.assertEqual(state.winner_id, host)  # only one player was left
        self.assertIn("player_forfeited", self.sent_types())
        self.assertEqual(GameAction.objects.last().action["type"], "forfeit")

    def test_leaving_twice_or_an_unknown_room_is_fine(self):
        code, host, guest = self.two_humans()
        self.post("leave-room", player_id=guest, code=code)
        r = self.post("leave-room", player_id=guest, code=code)
        self.assertEqual(r.status_code, 200)
        r = self.post("leave-room", code="ZZZZ")
        self.assertEqual(r.status_code, 200)

    def test_leaving_a_bot_game_on_the_bots_turn_lets_the_game_end(self):
        code, host = self.create_room()
        self.start(code, host)
        self.post("leave-room", player_id=host, code=code)
        self.assertTrue(self.game(code).is_finished)


class SessionRestoreTests(GameApiTestCase):
    """GET /api/me tells the app which room to go back to."""

    def me(self, account):
        return self.api.get("/api/me/", HTTP_AUTHORIZATION=f"Bearer {account}").data

    def test_active_room_follows_the_account(self):
        account = self.new_account()
        self.assertIsNone(self.me(account)["active_room"])
        code, host = self.create_room(account=account)
        room = self.me(account)["active_room"]
        self.assertEqual(
            room,
            {
                "code": code, "seat_id": host, "is_host": True, "max_players": 4, "started": False,
                "game_type": "ludo", "variant": "classic",
            },
        )
        guest = self.join(code)
        self.start(code, host)
        self.assertTrue(self.me(account)["active_room"]["started"])
        self.assertEqual(self.me(self.access[guest])["active_room"]["code"], code)

    def test_no_active_room_after_leaving_or_when_the_game_ends(self):
        code, host, guest = self.two_humans()
        self.post("leave-room", player_id=guest, code=code)
        self.assertIsNone(self.me(self.access[guest])["active_room"])
        self.assertIsNone(self.me(self.access[host])["active_room"])  # the game is over

    def test_a_player_removed_for_idling_has_no_active_room(self):
        code, host, guest = self.two_humans()
        game = self.game(code)
        state = self.state(code)
        players = tuple(
            replace(p, status=le.PlayerStatus.FORFEITED) if p.player_id == host else p
            for p in state.players
        )
        game.state = replace(state, players=players).to_dict()
        game.save(update_fields=["state"])
        self.assertIsNone(self.me(self.access[host])["active_room"])
        self.assertEqual(self.me(self.access[guest])["active_room"]["code"], code)


class MovableTokenTests(GameApiTestCase):
    """The app never guesses the rules: the server lists the tokens that may move."""

    def test_roll_response_lists_the_movable_tokens(self):
        code, host, _ = self.two_humans()
        self.dice(6)
        r = self.post("roll-dice", code=code, player_id=host)
        self.assertEqual(sorted(r.data["movable_token_ids"]), sorted(self.token_ids(code, host)))

    def test_roll_response_is_empty_when_nothing_can_move(self):
        code, host, _ = self.two_humans()
        self.dice(3)  # every token is still at base
        r = self.post("roll-dice", code=code, player_id=host)
        self.assertEqual(r.data["movable_token_ids"], [])

    def test_reconnect_snapshot_lists_the_movable_tokens(self):
        code, host, _ = self.two_humans()
        self.dice(6)
        self.post("roll-dice", code=code, player_id=host)
        snapshot = services.game_snapshot(self.game(code).room)
        self.assertEqual(snapshot["type"], "game_started")
        self.assertEqual(sorted(snapshot["movable_token_ids"]), sorted(self.token_ids(code, host)))
        self.assertIsNone(snapshot["winner_id"])

    def test_reconnect_snapshot_after_the_game_shows_the_winner(self):
        code, host, _ = self.two_humans()
        self.set_positions(code, {host: [55, 56, 56, 56]})
        self.dice(1)
        self.post("roll-dice", code=code, player_id=host)
        self.post("move-token", code=code, player_id=host, token_id=self.token_ids(code, host)[0])
        snapshot = services.game_snapshot(self.game(code).room)
        self.assertEqual((snapshot["winner_id"], snapshot["movable_token_ids"]), (host, []))


class GamePlatformTests(GameApiTestCase):
    """Rooms carry a game type and variant; the service runs any registered game."""

    def setUp(self):
        super().setUp()
        from game_platform.tests.toy_game import RaceGame

        game_platform.register(RaceGame())
        self.addCleanup(game_platform.unregister, "race")

    def test_rooms_are_ludo_classic_unless_asked_otherwise(self):
        code, host = self.create_room()
        r = self.post("join-room", code=code)
        self.assertEqual((r.data["room"]["game_type"], r.data["room"]["variant"]), ("ludo", "classic"))
        self.start(code, host)
        game = self.game(code)
        self.assertEqual((game.game_type, game.variant), ("ludo", "classic"))
        snapshot = services.game_snapshot(game.room)
        self.assertEqual((snapshot["game_type"], snapshot["variant"]), ("ludo", "classic"))
        self.assertEqual(len(snapshot["tokens"]), 8)  # Ludo's table adds its tokens

    def test_the_catalog_lists_every_game_and_variant(self):
        r = self.api.get("/api/game/catalog/")
        self.assertEqual(r.status_code, 200)
        games = {g["game_type"]: g for g in r.data["games"]}
        self.assertEqual(set(games), {"ludo", "race"})
        classic = games["ludo"]["variants"][0]
        self.assertEqual((classic["code"], classic["ranked"]), ("classic", True))
        self.assertEqual(classic["rules"]["tokens_per_player"], 4)

    def test_unknown_games_and_variants_are_refused_by_code(self):
        r = self.post("create-room", game_type="chess")
        self.assertEqual((r.status_code, r.data["fields"]), (400, {"game_type": ["unknown_game"]}))
        r = self.post("create-room", game_type="ludo", variant="turbo")
        self.assertEqual((r.status_code, r.data["fields"]), (400, {"variant": ["unknown_variant"]}))
        r = self.api.get("/api/game/room-options/", {"game_type": "chess"})
        self.assertEqual(r.data["fields"], {"game_type": ["unknown_game"]})

    def test_each_variant_sets_its_own_room_sizes(self):
        r = self.api.get("/api/game/room-options/", {"game_type": "race", "variant": "long"})
        self.assertEqual((r.data["player_counts"], r.data["default_player_count"]), ([2, 3], 3))
        r = self.post("create-room", game_type="race", variant="long")
        self.assertEqual((r.data["room"]["variant"], r.data["room"]["max_players"]), ("long", 3))
        r = self.post("create-room", game_type="race", max_players=4)
        self.assertEqual((r.status_code, r.data["fields"]), (400, {"max_players": ["max_value"]}))

    def test_another_game_runs_through_the_same_service(self):
        account = self.new_account()
        r = self.post("create-room", as_account=account, game_type="race")
        code, host = r.data["room"]["code"], str(r.data["player"]["id"])
        self.access[host] = account
        self.start(code, host)  # alone: the AI joins

        game = self.game(code)
        self.assertEqual((game.game_type, game.variant, game.state["target"]), ("race", "short", 5))
        self.assertFalse(Token.objects.filter(player__room__code=code).exists())  # no Ludo rows

        # Ludo's endpoints refuse; the game's own actions go through perform().
        r = self.post("roll-dice", code=code, player_id=host)
        self.assertEqual((r.status_code, r.data["code"]), (400, "wrong_game"))
        services.SERVER_RANDOM = game_platform.ScriptedRandom([2, 2, 2])
        self.addCleanup(setattr, services, "SERVER_RANDOM", game_platform.SecureRandom())
        result = services.perform(code, {"type": "draw", "player_id": host})
        self.assertTrue(result.next_is_bot)
        services.schedule_bots(code)  # the AI draws inline

        game = self.game(code)
        self.assertEqual(game.state["scores"], [3, 3])
        self.assertEqual(GameAction.objects.filter(game=game).count(), 2)
        self.assertEqual(str(game.current_turn_id), host)
        # Messages are the engine's own events when a game has no table of its own.
        self.assertEqual([m["type"] for m in self.sent], ["drew", "drew"])
        self.assertEqual(self.sent[0]["version"], 1)

        # The turn timer plays for an idle player through the same contract.
        self.assertEqual(timers.process_due_turns(now=timezone.now() + timedelta(seconds=60)), 1)
        game = self.game(code)
        self.assertTrue(game.is_finished)
        self.assertEqual(game.state["winner_id"], host)
        self.assertEqual(self.sent[-1]["type"], "game_finished")
        self.assertIsNone(services.active_seat_for(Player.objects.get(id=host).user))

    def test_refused_actions_keep_their_engine_code(self):
        code, host, guest = self.two_humans()
        r = self.post("roll-dice", code=code, player_id=guest)
        self.assertEqual((r.status_code, r.data["code"]), (403, "not_your_turn"))
