import json
import unittest

import ludo_engine as le
from ludo_engine import (
    GameNotActive,
    IllegalMove,
    InvalidAction,
    InvalidDiceValue,
    InvalidSetup,
    NotYourTurn,
    Rules,
    TurnPhase,
    UnknownPlayer,
    WrongPhase,
)

from .helpers import BASE, make_state, progress_for_square


class SetupTests(unittest.TestCase):
    def test_new_game_two_players_sit_opposite(self):
        state = le.new_game("g", ["a", "b"])
        self.assertEqual([(p.player_id, p.seat, p.color) for p in state.players],
                         [("a", 0, "red"), ("b", 2, "green")])
        self.assertEqual(state.version, 0)
        self.assertEqual(state.phase, TurnPhase.AWAITING_ROLL)
        self.assertTrue(all(p.tokens == (-1, -1, -1, -1) for p in state.players))

    def test_turn_order_follows_seats_not_join_order(self):
        state = le.new_game("g", ["x", "y", "z"], seats=[3, 0, 1])
        self.assertEqual([p.player_id for p in state.players], ["y", "z", "x"])

    def test_first_player_can_be_chosen(self):
        state = le.new_game("g", ["a", "b", "c"], first_player_id="c")
        self.assertEqual(state.current_player.player_id, "c")
        with self.assertRaises(UnknownPlayer):
            le.new_game("g", ["a", "b"], first_player_id="nobody")

    def test_invalid_setups(self):
        cases = [
            dict(player_ids=["a"]),
            dict(player_ids=["a", "b", "c", "d", "e"]),
            dict(player_ids=["a", "a"]),
            dict(player_ids=["a", "b"], seats=[0, 0]),
            dict(player_ids=["a", "b"], seats=[0, 4]),
            dict(player_ids=["a", "b"], seats=[0]),
        ]
        for kwargs in cases:
            with self.subTest(kwargs=kwargs), self.assertRaises(InvalidSetup):
                le.new_game("g", **kwargs)


class RollTests(unittest.TestCase):
    def setUp(self):
        self.state = le.new_game("g", ["a", "b"])

    def test_no_legal_move_passes_the_turn(self):
        t = le.roll(self.state, "a", 3)  # every token in base, 3 cannot enter
        self.assertEqual(t.event_types(), ["dice_result", "turn_ended", "turn_started"])
        self.assertEqual(t.events[1].data["reason"], "no_legal_moves")
        self.assertEqual(t.state.current_player.player_id, "b")
        self.assertEqual(t.state.phase, TurnPhase.AWAITING_ROLL)
        self.assertIsNone(t.state.dice_value)

    def test_six_lets_a_token_enter_on_the_start_square(self):
        t = le.roll(self.state, "a", 6)
        self.assertEqual(t.state.phase, TurnPhase.AWAITING_MOVE)
        self.assertEqual(t.events[0].data["movable_tokens"], [0, 1, 2, 3])
        t = le.move(t.state, "a", 2)
        self.assertEqual(t.state.player("a").tokens, (-1, -1, 0, -1))
        self.assertEqual(t.events[0].data["to_square"], 0)

    def test_six_gives_an_extra_turn(self):
        t = le.move(le.roll(self.state, "a", 6).state, "a", 0)
        self.assertEqual(t.state.current_player.player_id, "a")
        self.assertTrue(t.events[-1].data["extra_turn"])

    def test_normal_move_passes_the_turn(self):
        state = make_state(("a", 0, [10, -1, -1, -1]), ("b", 2, BASE))
        t = le.move(le.roll(state, "a", 4).state, "a", 0)
        self.assertEqual(t.state.player("a").tokens[0], 14)
        self.assertEqual(t.state.current_player.player_id, "b")

    def test_rules_entry_rolls_are_configurable(self):
        state = make_state(("a", 0, BASE), ("b", 2, BASE), rules=Rules(entry_rolls={1, 6}))
        t = le.roll(state, "a", 1)
        self.assertEqual(t.state.phase, TurnPhase.AWAITING_MOVE)

    def test_extra_turn_on_six_can_be_switched_off(self):
        state = make_state(("a", 0, [10, -1, -1, -1]), ("b", 2, BASE),
                           rules=Rules(extra_turn_on_six=False))
        t = le.move(le.roll(state, "a", 6).state, "a", 0)
        self.assertEqual(t.state.current_player.player_id, "b")


class ThreeSixesTests(unittest.TestCase):
    def test_third_six_in_a_row_ends_the_turn_without_moving(self):
        state = make_state(("a", 0, [10, -1, -1, -1]), ("b", 2, BASE))
        state = le.move(le.roll(state, "a", 6).state, "a", 0).state
        state = le.move(le.roll(state, "a", 6).state, "a", 0).state
        self.assertEqual(state.consecutive_sixes, 2)
        t = le.roll(state, "a", 6)
        self.assertEqual(t.events[1].data["reason"], "too_many_sixes")
        self.assertEqual(t.state.current_player.player_id, "b")
        self.assertEqual(t.state.player("a").tokens[0], 22)  # 10 + 6 + 6, third six not moved
        self.assertEqual(t.state.consecutive_sixes, 0)

    def test_count_resets_after_a_non_six(self):
        state = make_state(("a", 0, [10, -1, -1, -1]), ("b", 2, BASE), sixes=2)
        t = le.roll(state, "a", 2)
        self.assertEqual(t.state.consecutive_sixes, 0)

    def test_rule_can_be_disabled(self):
        state = make_state(("a", 0, [10, -1, -1, -1]), ("b", 2, BASE), sixes=5,
                           rules=Rules(max_consecutive_sixes=0))
        t = le.roll(state, "a", 6)
        self.assertEqual(t.state.phase, TurnPhase.AWAITING_MOVE)


class CaptureTests(unittest.TestCase):
    def test_landing_on_an_opponent_sends_it_to_base_and_gives_an_extra_turn(self):
        blue = progress_for_square(1, 5)
        state = make_state(("a", 0, [2, -1, -1, -1]), ("b", 1, [blue, -1, -1, -1]))
        t = le.move(le.roll(state, "a", 3).state, "a", 0)
        self.assertIn("token_captured", t.event_types())
        self.assertEqual(t.state.player("b").tokens[0], -1)
        self.assertEqual(t.state.current_player.player_id, "a")  # capture bonus turn

    def test_equal_progress_on_different_squares_does_not_capture(self):
        # Regression: game/utils.py compared raw progress across players.
        state = make_state(("a", 0, [2, -1, -1, -1]), ("b", 1, [5, -1, -1, -1]))
        t = le.move(le.roll(state, "a", 3).state, "a", 0)
        self.assertNotIn("token_captured", t.event_types())
        self.assertEqual(t.state.player("b").tokens[0], 5)

    def test_safe_star_square_protects(self):
        blue = progress_for_square(1, 8)
        state = make_state(("a", 0, [5, -1, -1, -1]), ("b", 1, [blue, -1, -1, -1]))
        t = le.move(le.roll(state, "a", 3).state, "a", 0)
        self.assertNotIn("token_captured", t.event_types())
        self.assertEqual(t.state.current_player.player_id, "b")

    def test_opponent_start_square_is_safe(self):
        state = make_state(("a", 0, [10, -1, -1, -1]), ("b", 1, [0, -1, -1, -1]))
        t = le.move(le.roll(state, "a", 3).state, "a", 0)  # square 13 = blue start
        self.assertNotIn("token_captured", t.event_types())

    def test_every_opponent_token_on_the_square_is_captured(self):
        blue = progress_for_square(1, 5)
        state = make_state(("a", 0, [2, -1, -1, -1]), ("b", 1, [blue, blue, -1, -1]))
        t = le.move(le.roll(state, "a", 3).state, "a", 0)
        self.assertEqual(t.event_types().count("token_captured"), 2)

    def test_own_tokens_stack_without_capture(self):
        state = make_state(("a", 0, [2, 5, -1, -1]), ("b", 2, BASE))
        t = le.move(le.roll(state, "a", 3).state, "a", 0)
        self.assertEqual(t.state.player("a").tokens[:2], (5, 5))
        self.assertNotIn("token_captured", t.event_types())

    def test_home_column_tokens_cannot_be_captured(self):
        # Red's progress 51 is its home column, not shared square 51.
        green = progress_for_square(2, 48)  # green lands on square 51 with a 3
        state = make_state(("a", 0, [51, -1, -1, -1]), ("g", 2, [green, -1, -1, -1]), current=1)
        t = le.move(le.roll(state, "g", 3).state, "g", 0)
        self.assertEqual(t.events[0].data["to_square"], 51)
        self.assertNotIn("token_captured", t.event_types())
        self.assertEqual(t.state.player("a").tokens[0], 51)

    def test_captures_can_be_disabled(self):
        blue = progress_for_square(1, 5)
        state = make_state(("a", 0, [2, -1, -1, -1]), ("b", 1, [blue, -1, -1, -1]),
                           rules=Rules(capture_enabled=False))
        t = le.move(le.roll(state, "a", 3).state, "a", 0)
        self.assertNotIn("token_captured", t.event_types())


class HomeStretchTests(unittest.TestCase):
    def test_track_leads_into_the_home_column(self):
        state = make_state(("a", 0, [48, -1, -1, -1]), ("b", 2, BASE))
        t = le.move(le.roll(state, "a", 5).state, "a", 0)
        self.assertEqual(t.state.player("a").tokens[0], 53)
        self.assertIsNone(t.events[0].data["to_square"])

    def test_must_land_on_home_exactly(self):
        state = make_state(("a", 0, [54, 56, 56, 56]), ("b", 2, BASE))
        t = le.roll(state, "a", 3)
        self.assertEqual(t.events[1].data["reason"], "no_legal_moves")

    def test_finishing_a_token_gives_an_extra_turn(self):
        state = make_state(("a", 0, [54, -1, -1, -1]), ("b", 2, BASE))
        t = le.move(le.roll(state, "a", 2).state, "a", 0)
        self.assertIn("token_finished", t.event_types())
        self.assertEqual(t.state.current_player.player_id, "a")


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.state = make_state(("a", 0, [10, -1, -1, -1]), ("b", 2, BASE))

    def test_not_your_turn(self):
        with self.assertRaises(NotYourTurn):
            le.roll(self.state, "b", 4)

    def test_unknown_player(self):
        with self.assertRaises(UnknownPlayer):
            le.roll(self.state, "ghost", 4)

    def test_move_before_roll_and_roll_twice(self):
        with self.assertRaises(WrongPhase):
            le.move(self.state, "a", 0)
        rolled = le.roll(self.state, "a", 4).state
        with self.assertRaises(WrongPhase):
            le.roll(rolled, "a", 4)

    def test_client_cannot_send_impossible_dice(self):
        for value in (0, 7, -1, True, 3.0, "6", None):
            with self.subTest(value=value), self.assertRaises(InvalidDiceValue):
                le.roll(self.state, "a", value)

    def test_illegal_tokens(self):
        rolled = le.roll(self.state, "a", 3).state
        for token in (1, 4, -1, True, "0"):  # 1 is in base and 3 cannot enter
            with self.subTest(token=token), self.assertRaises(IllegalMove):
                le.move(rolled, "a", token)

    def test_failed_action_changes_nothing(self):
        before = self.state.to_dict()
        with self.assertRaises(NotYourTurn):
            le.roll(self.state, "b", 4)
        self.assertEqual(self.state.to_dict(), before)

    def test_apply_action_rejects_bad_input(self):
        with self.assertRaises(InvalidAction):
            le.apply_action(self.state, {"type": "teleport"})
        with self.assertRaises(InvalidAction):
            le.apply_action(self.state, {"type": "roll", "player_id": "a"})


class VersionAndSnapshotTests(unittest.TestCase):
    def test_each_action_bumps_version_once_and_tags_every_event(self):
        state = le.new_game("g", ["a", "b"])
        t1 = le.roll(state, "a", 6)
        t2 = le.move(t1.state, "a", 0)
        self.assertEqual((t1.state.version, t2.state.version), (1, 2))
        self.assertTrue(all(e.version == 2 for e in t2.events))

    def test_snapshot_round_trip_and_json(self):
        state = le.move(le.roll(le.new_game("g", ["a", "b", "c"]), "a", 6).state, "a", 1).state
        data = json.loads(json.dumps(state.to_dict()))
        self.assertEqual(le.GameState.from_dict(data), state)

    def test_tampered_snapshots_are_rejected(self):
        good = le.new_game("g", ["a", "b"]).to_dict()
        tampered = [
            {**good, "schema_version": 99},
            {**good, "current_player_id": "ghost"},
            {**good, "players": [dict(good["players"][0], tokens=[{"progress": 99}] * 4),
                                 good["players"][1]]},
            {**good, "players": [dict(good["players"][0], tokens=[{"progress": 0}]),
                                 good["players"][1]]},
            {**good, "phase": "awaiting_move", "dice_value": None},
        ]
        for data in tampered:
            with self.subTest(data=data), self.assertRaises(InvalidSetup):
                le.GameState.from_dict(data)


if __name__ == "__main__":
    unittest.main()
