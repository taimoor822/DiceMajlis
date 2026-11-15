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
from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

import ludo_engine as le
from ludo_engine import GameState, TurnPhase

from . import services, timers
from .consumers import LobbyConsumer
from .models import Game, GameAction, Player, Token

IN_MEMORY_LAYER = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}


@override_settings(
    GAME_BOTS_INLINE=True,
    GAME_BOT_DELAY_SECONDS=(0, 0),
    CHANNEL_LAYERS=IN_MEMORY_LAYER,
)
class GameApiTestCase(TestCase):
    capture_broadcasts = True

    def setUp(self):
        self.api = APIClient()
        self.sent = []
        if self.capture_broadcasts:
            patcher = mock.patch(
                "game.services.broadcast",
                side_effect=lambda code, msgs: self.sent.extend(m["payload"] for m in msgs),
            )
            patcher.start()
            self.addCleanup(patcher.stop)

    # ---- helpers ---------------------------------------------------------

    def post(self, endpoint, **data):
        return self.api.post(f"/api/game/{endpoint}/", data, format="json")

    def create_room(self, name="Host", color="red"):
        r = self.post("create-room", name=name, color=color, max_players=4)
        self.assertEqual(r.status_code, 201, r.data)
        return r.data["room"]["code"], str(r.data["player"]["id"])

    def join(self, code, name, color="blue"):
        r = self.post("join-room", code=code, name=name, color=color)
        self.assertEqual(r.status_code, 200, r.data)
        return str(r.data["player"]["id"])

    def start(self, code, host):
        r = self.post("start-game", code=code, player_id=host)
        self.assertEqual(r.status_code, 200, r.data)

    def two_humans(self):
        code, host = self.create_room()
        guest = self.join(code, "Guest")
        self.start(code, host)
        return code, host, guest

    def game(self, code):
        return Game.objects.get(room__code=code)

    def state(self, code):
        return GameState.from_dict(self.game(code).state)

    def token_ids(self, code, player_id):
        return services.token_ids_by_player(self.game(code).room)[player_id]

    def dice(self, *values):
        patcher = mock.patch.object(services.SecureDice, "roll", side_effect=list(values))
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
        ids = services.token_ids_by_player(game.room)
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
        a = self.join(code, "A", color="blue")
        b = self.join(code, "B", color="blue")  # the app sends blue for every joiner
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
        guest = self.join(code, "Guest")
        r = self.post("start-game", code=code, player_id=guest)
        self.assertEqual(r.status_code, 403)
        r = self.post("start-game", code=code, player_id="not-a-uuid")
        self.assertEqual(r.status_code, 403)


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
        ids = services.token_ids_by_player(game.room)
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
        r = self.post("roll-dice", code="NOPE", player_id="x")
        self.assertEqual(r.status_code, 404)


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
        snapshot = async_to_sync(consumer.get_game_state)()
        self.assertTrue(28 <= snapshot["seconds_left"] <= 30)

    def test_management_command_runs_one_sweep(self):
        self.two_humans()
        Game.objects.update(turn_deadline=timezone.now() - timedelta(seconds=1))
        self.dice(3)
        out = StringIO()
        call_command("run_turn_timers", "--once", stdout=out)
        self.assertIn("Handled 1", out.getvalue())
