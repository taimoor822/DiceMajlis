import unittest

import ludo_engine as le
from ludo_engine import (
    GameNotActive,
    GameStatus,
    InvalidAction,
    InvalidDiceValue,
    PlayerStatus,
    Rules,
    TurnPhase,
)

from .helpers import BASE, make_state, progress_for_square


class VictoryTests(unittest.TestCase):
    def test_last_token_home_wins_and_ends_the_game(self):
        state = make_state(("a", 0, [54, 56, 56, 56]), ("b", 2, [30, -1, -1, -1]))
        t = le.move(le.roll(state, "a", 2).state, "a", 0)
        self.assertEqual(
            t.event_types(),
            ["token_moved", "token_finished", "player_finished", "game_finished"],
        )
        self.assertEqual(t.state.status, GameStatus.FINISHED)
        self.assertEqual(t.state.winner_id, "a")
        self.assertEqual([s["player_id"] for s in le.standings(t.state)], ["a", "b"])

    def test_no_actions_after_the_game_ends(self):
        state = make_state(("a", 0, [54, 56, 56, 56]), ("b", 2, BASE))
        done = le.move(le.roll(state, "a", 2).state, "a", 0).state
        for action in (lambda: le.roll(done, "b", 6),
                       lambda: le.timeout(done, dice_value=6),
                       lambda: le.forfeit(done, "b")):
            with self.assertRaises(GameNotActive):
                action()

    def test_unfinished_players_are_ranked_by_progress(self):
        state = make_state(
            ("a", 0, [54, 56, 56, 56]),
            ("b", 1, [5, -1, -1, -1]),
            ("c", 2, [40, 30, -1, -1]),
            ("d", 3, BASE),
        )
        done = le.move(le.roll(state, "a", 2).state, "a", 0).state
        self.assertEqual([s["player_id"] for s in le.standings(done)], ["a", "c", "b", "d"])

    def test_full_ranking_mode_plays_on_until_one_player_is_left(self):
        rules = Rules(end_when_first_player_finishes=False)
        state = make_state(
            ("a", 0, [54, 56, 56, 56]),
            ("b", 1, [54, 56, 56, 56]),
            ("c", 2, [10, -1, -1, -1]),
            rules=rules,
        )
        t = le.move(le.roll(state, "a", 2).state, "a", 0)
        self.assertEqual(t.state.status, GameStatus.PLAYING)
        self.assertEqual(t.state.player("a").finish_place, 1)
        self.assertEqual(t.state.current_player.player_id, "b")  # no bonus turn when finished

        t = le.move(le.roll(t.state, "b", 2).state, "b", 0)
        self.assertEqual(t.state.status, GameStatus.FINISHED)
        self.assertEqual(
            [(s["player_id"], s["place"]) for s in le.standings(t.state)],
            [("a", 1), ("b", 2), ("c", 3)],
        )
        self.assertEqual(t.state.winner_id, "a")


class TimeoutTests(unittest.TestCase):
    def test_timeout_needs_a_server_dice_value_when_a_roll_is_due(self):
        with self.assertRaises(InvalidDiceValue):
            le.timeout(le.new_game("g", ["a", "b"]))

    def test_timeout_auto_rolls_and_auto_moves(self):
        t = le.timeout(le.new_game("g", ["a", "b"]), dice_value=6)
        self.assertEqual(
            t.event_types(),
            ["player_timeout", "dice_result", "token_moved", "turn_ended", "turn_started"],
        )
        self.assertEqual(t.state.player("a").missed_turns, 1)
        self.assertEqual(t.state.player("a").tokens.count(0), 1)

    def test_timeout_while_a_move_is_due_moves_for_the_player(self):
        state = make_state(("a", 0, [10, -1, -1, -1]), ("b", 2, BASE), dice=4)
        t = le.timeout(state)
        self.assertEqual(t.state.player("a").tokens[0], 14)
        self.assertEqual(t.state.current_player.player_id, "b")

    def test_stale_timer_is_rejected(self):
        state = le.new_game("g", ["a", "b"])
        after_turn = le.roll(state, "a", 3).state  # turn already passed to b
        with self.assertRaises(InvalidAction):
            le.timeout(after_turn, dice_value=4, expected_turn=state.turn_number)

    def test_missed_turns_reset_when_the_player_acts(self):
        state = make_state(("a", 0, BASE), ("b", 2, BASE))
        state = le.roll(le.timeout(state, dice_value=2).state, "b", 2).state
        self.assertEqual(state.player("a").missed_turns, 1)
        state = le.roll(state, "a", 3).state
        self.assertEqual(state.player("a").missed_turns, 0)

    def test_too_many_timeouts_forfeit_and_the_other_player_wins(self):
        state = le.new_game("g", ["a", "b"])
        for _ in range(2):
            state = le.timeout(state, dice_value=3).state  # a misses
            state = le.timeout(state, dice_value=3).state  # b misses
        t = le.timeout(state, dice_value=3)  # a's third miss in a row
        self.assertIn("player_forfeited", t.event_types())
        self.assertEqual(t.state.player("a").status, PlayerStatus.FORFEITED)
        self.assertEqual(t.state.winner_id, "b")

    def test_forfeit_by_timeout_keeps_a_bigger_game_going(self):
        rules = Rules(max_missed_turns=1)
        state = make_state(("a", 0, BASE), ("b", 1, BASE), ("c", 2, BASE), rules=rules)
        t = le.timeout(state, dice_value=3)
        self.assertEqual(t.state.status, GameStatus.PLAYING)
        self.assertEqual(t.state.current_player.player_id, "b")
        self.assertEqual(t.state.player("a").finish_place, 3)


class ForfeitTests(unittest.TestCase):
    def test_leaving_on_your_turn_passes_it(self):
        state = make_state(("a", 0, BASE), ("b", 1, BASE), ("c", 2, BASE))
        t = le.forfeit(state, "a")
        self.assertEqual(t.state.current_player.player_id, "b")

    def test_leaving_out_of_turn_keeps_the_turn(self):
        state = make_state(("a", 0, BASE), ("b", 1, BASE), ("c", 2, BASE))
        t = le.forfeit(state, "c")
        self.assertEqual(t.state.current_player.player_id, "a")
        later = le.roll(le.roll(t.state, "a", 3).state, "b", 3).state
        self.assertEqual(later.current_player.player_id, "a")  # c is skipped

    def test_forfeited_tokens_are_off_the_board(self):
        blue = progress_for_square(1, 5)
        state = make_state(("a", 0, [2, -1, -1, -1]), ("b", 1, [blue, -1, -1, -1]),
                           ("c", 2, BASE))
        state = le.forfeit(state, "b").state
        t = le.move(le.roll(state, "a", 3).state, "a", 0)
        self.assertNotIn("token_captured", t.event_types())

    def test_cannot_forfeit_twice(self):
        state = make_state(("a", 0, BASE), ("b", 1, BASE), ("c", 2, BASE))
        state = le.forfeit(state, "c").state
        with self.assertRaises(InvalidAction):
            le.forfeit(state, "c")


class BotTests(unittest.TestCase):
    def test_prefers_finishing_then_capturing(self):
        blue = progress_for_square(1, 13 + 9)  # square 22, not safe
        state = make_state(("a", 0, [53, 19, -1, -1]), ("b", 1, [9, -1, -1, -1]), dice=3)
        self.assertEqual(le.choose_move(state).token_index, 0)  # 53 + 3 = home
        state = make_state(("a", 0, [40, 19, -1, -1]), ("b", 1, [blue, -1, -1, -1]), dice=3)
        self.assertEqual(le.choose_move(state).token_index, 1)  # 19 + 3 captures on 22

    def test_is_deterministic(self):
        state = make_state(("a", 0, [-1, -1, -1, -1]), ("b", 2, BASE), dice=6)
        picks = {le.choose_move(state).token_index for _ in range(20)}
        self.assertEqual(picks, {0})

    def test_needs_a_legal_move(self):
        with self.assertRaises(le.IllegalMove):
            le.choose_move(le.new_game("g", ["a", "b"]))


if __name__ == "__main__":
    unittest.main()
