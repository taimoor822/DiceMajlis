"""The game registry and the Ludo adapter. Pure: runs with or without Django."""

import unittest

import game_platform as gp
import ludo_engine as le
from game_platform import ScriptedRandom, Variant
from ludo_engine import TurnPhase

from .toy_game import RACE, RaceGame


class RegistryTests(unittest.TestCase):
    def test_ludo_is_registered_with_classic_as_default(self):
        self.assertIn(gp.LUDO, gp.game_types())
        ludo = gp.get_game(gp.LUDO)
        self.assertEqual(ludo.default_variant, gp.CLASSIC)
        self.assertEqual(gp.get_variant(gp.LUDO).code, gp.CLASSIC)
        self.assertIsInstance(ludo, gp.GameEngine)

    def test_unknown_game_and_variant_have_codes(self):
        with self.assertRaises(gp.UnknownGame) as game:
            gp.get_game("chess")
        self.assertEqual(game.exception.code, "unknown_game")
        with self.assertRaises(gp.UnknownVariant) as variant:
            gp.get_variant(gp.LUDO, "turbo")
        self.assertEqual(variant.exception.code, "unknown_variant")

    def test_catalog_lists_games_variants_and_full_rules(self):
        ludo = next(g for g in gp.catalog() if g["game_type"] == gp.LUDO)
        self.assertEqual(ludo["default_variant"], "classic")
        classic = ludo["variants"][0]
        self.assertEqual(
            {k: classic[k] for k in ("code", "min_players", "max_players", "default_players", "ranked")},
            {"code": "classic", "min_players": 2, "max_players": 4, "default_players": 4, "ranked": True},
        )
        self.assertEqual(classic["rules"], le.Rules().to_dict())

    def test_a_second_game_plugs_in(self):
        gp.register(RaceGame())
        self.addCleanup(gp.unregister, RACE)
        self.assertEqual(gp.game_types(), [gp.LUDO, RACE])
        self.assertEqual(gp.get_variant(RACE).code, "short")
        self.assertEqual(
            [v["code"] for v in next(g for g in gp.catalog() if g["game_type"] == RACE)["variants"]],
            ["short", "long"],
        )
        self.assertEqual(set(gp.rule_errors()), {le.EngineError, RaceGame.rule_error})

    def test_registering_needs_the_contract_and_a_unique_type(self):
        with self.assertRaises(TypeError):
            gp.register(object())
        with self.assertRaises(ValueError):
            gp.register(gp.LudoGame())  # "ludo" is taken

    def test_variants_check_their_player_counts(self):
        with self.assertRaises(ValueError):
            Variant(code="odd", min_players=3, default_players=2, max_players=4)
        classic = gp.get_variant(gp.LUDO)
        self.assertTrue(classic.allows(2) and classic.allows(4))
        self.assertFalse(classic.allows(1) or classic.allows(5))


class LudoAdapterTests(unittest.TestCase):
    def setUp(self):
        self.ludo = gp.get_game(gp.LUDO)
        self.state = self.ludo.new_game("g", ["a", "b"], variant=gp.CLASSIC)

    def test_new_game_uses_the_variant_rules_and_player_counts(self):
        self.assertEqual(self.state.rules, le.Rules())
        self.assertEqual([p.seat for p in self.state.players], [0, 2])
        with self.assertRaises(le.InvalidSetup):
            self.ludo.new_game("g", ["a"], variant=gp.CLASSIC)

    def test_snapshots_round_trip(self):
        self.assertEqual(self.ludo.load(self.ludo.dump(self.state)), self.state)

    def test_info(self):
        info = self.ludo.info(self.state)
        self.assertEqual(
            (info.version, info.finished, info.current_player_id, info.turn_number),
            (0, False, "a", 1),
        )
        self.assertEqual((info.turn_seconds, info.warning_seconds), (30, 10))
        self.assertEqual(info.active_player_ids, ("a", "b"))
        self.assertIsNone(info.winner_id)

    def test_the_server_rolls_and_ignores_a_value_from_the_app(self):
        action = self.ludo.prepare_action(
            self.state, {"type": "roll", "player_id": "a", "value": 6}, ScriptedRandom([2])
        )
        self.assertEqual(action, {"type": "roll", "player_id": "a", "value": 3})

    def test_refused_requests_never_use_the_random_source(self):
        random = ScriptedRandom([])  # any use would raise RuntimeError
        with self.assertRaises(le.NotYourTurn):
            self.ludo.prepare_action(self.state, {"type": "roll", "player_id": "b"}, random)
        with self.assertRaises(le.InvalidAction):
            self.ludo.prepare_action(self.state, {"type": "timeout", "turn_number": 7}, random)
        with self.assertRaises(le.NotYourTurn):
            self.ludo.prepare_action(self.state, {"type": "bot", "player_id": "b"}, random)

    def test_bot_rolls_then_moves(self):
        rolled = self.ludo.apply_action(
            self.state, self.ludo.prepare_action(self.state, {"type": "bot", "player_id": "a"}, ScriptedRandom([5]))
        ).state
        self.assertEqual(rolled.phase, TurnPhase.AWAITING_MOVE)  # rolled a 6
        move = self.ludo.prepare_action(rolled, {"type": "bot", "player_id": "a"}, ScriptedRandom([]))
        self.assertEqual(move, {"type": "move", "player_id": "a", "token_index": 0})

    def test_timeout_rolls_only_when_a_roll_is_due(self):
        action = self.ludo.prepare_action(self.state, {"type": "timeout"}, ScriptedRandom([0]))
        self.assertEqual(action, {"type": "timeout", "turn_number": 1, "dice_value": 1})

    def test_legal_actions(self):
        self.assertEqual(self.ludo.legal_actions(self.state, "a"), [{"type": "roll", "player_id": "a"}])
        self.assertEqual(self.ludo.legal_actions(self.state, "b"), [])
        rolled = le.roll(self.state, "a", 6).state
        self.assertEqual(
            [a["token_index"] for a in self.ludo.legal_actions(rolled, "a")], [0, 1, 2, 3]
        )

    def test_everyone_sees_the_whole_board_and_standings_rank_everyone(self):
        self.assertEqual(self.ludo.view_for(self.state, "b"), self.state.to_dict())
        self.assertEqual([s["place"] for s in self.ludo.standings(self.state)], [1, 2])

    def test_replay(self):
        actions = [{"type": "roll", "player_id": "a", "value": 6}, {"type": "move", "player_id": "a", "token_index": 0}]
        final = self.ludo.replay(self.state, actions)
        self.assertEqual(final.players[0].tokens[0], 0)


class ToyGameTests(unittest.TestCase):
    """The toy game itself follows the contract (it is used by the game service tests)."""

    def test_race_to_the_target(self):
        race = RaceGame()
        state = race.new_game("r", ["x", "y"], variant="short")
        random = ScriptedRandom([2, 2, 2])  # draws of 3: x 3, y 3, x 6
        while not race.info(state).finished:
            player = race.info(state).current_player_id
            state = race.apply_action(state, race.prepare_action(state, {"type": "bot", "player_id": player}, random)).state
        self.assertEqual(race.info(state).winner_id, "x")
        self.assertEqual(state.version, 3)


if __name__ == "__main__":
    unittest.main()
