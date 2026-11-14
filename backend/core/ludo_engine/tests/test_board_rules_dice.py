import unittest

from ludo_engine import Rules, ScriptedDice, SecureDice
from ludo_engine.board import (
    absolute_square,
    default_safe_squares,
    default_seats_for,
    is_in_home_column,
    start_square,
)


class BoardTests(unittest.TestCase):
    def test_seat_starts_are_13_apart_like_the_flutter_board(self):
        self.assertEqual([start_square(s) for s in range(4)], [0, 13, 26, 39])

    def test_progress_maps_to_absolute_square_and_wraps(self):
        self.assertEqual(absolute_square(0, 0), 0)
        self.assertEqual(absolute_square(1, 0), 13)
        self.assertEqual(absolute_square(3, 20), 7)  # 39 + 20 wraps past 51
        self.assertEqual(absolute_square(2, 50), 24)

    def test_base_home_column_and_home_have_no_square(self):
        for progress in (-1, 51, 55, 56):
            self.assertIsNone(absolute_square(0, progress))
        self.assertTrue(is_in_home_column(51))
        self.assertFalse(is_in_home_column(56))

    def test_same_progress_is_a_different_square_for_each_seat(self):
        squares = {absolute_square(seat, 5) for seat in range(4)}
        self.assertEqual(len(squares), 4)

    def test_safe_squares_are_starts_and_stars(self):
        self.assertEqual(sorted(default_safe_squares()), [0, 8, 13, 21, 26, 34, 39, 47])

    def test_default_seats(self):
        self.assertEqual(default_seats_for(2), (0, 2))
        self.assertEqual(default_seats_for(4), (0, 1, 2, 3))
        with self.assertRaises(ValueError):
            default_seats_for(5)

    def test_bad_seat_rejected(self):
        for seat in (-1, 4, True, "1"):
            with self.assertRaises(ValueError):
                absolute_square(seat, 0)


class RulesTests(unittest.TestCase):
    def test_round_trip(self):
        rules = Rules(entry_rolls={1, 6}, max_missed_turns=5)
        self.assertEqual(Rules.from_dict(rules.to_dict()), rules)

    def test_lists_from_json_are_normalised(self):
        rules = Rules.from_dict({"entry_rolls": [6, 1], "unknown_future_key": 1})
        self.assertEqual(rules.entry_rolls, frozenset({1, 6}))

    def test_invalid_rules_rejected(self):
        bad = [
            {"tokens_per_player": 0},
            {"entry_rolls": set()},
            {"entry_rolls": {7}},
            {"safe_squares": {52}},
            {"max_consecutive_sixes": -1},
            {"max_missed_turns": -1},
            {"turn_timeout_seconds": 0},
            {"timeout_warning_seconds": 30},
        ]
        for kwargs in bad:
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                Rules(**kwargs)


class DiceTests(unittest.TestCase):
    def test_secure_dice_only_rolls_1_to_6_and_hits_every_face(self):
        dice = SecureDice()
        rolls = [dice.roll() for _ in range(2000)]
        self.assertEqual(set(rolls), {1, 2, 3, 4, 5, 6})

    def test_scripted_dice_plays_back_in_order_then_stops(self):
        dice = ScriptedDice([6, 1])
        self.assertEqual([dice.roll(), dice.roll()], [6, 1])
        self.assertEqual(dice.remaining, 0)
        with self.assertRaises(RuntimeError):
            dice.roll()

    def test_scripted_dice_rejects_impossible_values(self):
        for values in ([0], [7], [True], ["6"]):
            with self.assertRaises(ValueError):
                ScriptedDice(values)


if __name__ == "__main__":
    unittest.main()
