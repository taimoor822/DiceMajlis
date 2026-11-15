"""
Plays hundreds of complete random games and checks rules that must ALWAYS hold,
then replays each game from its action log and expects the identical result.
"""

import random
import unittest

import ludo_engine as le
from ludo_engine import GameStatus, PlayerStatus, Rules, TurnPhase
from ludo_engine.board import absolute_square

GAMES = 300
MAX_ACTIONS = 5000


def play_random_game(seed: int):
    rng = random.Random(seed)
    player_count = rng.choice([2, 3, 4])
    rules = Rules(end_when_first_player_finishes=rng.random() < 0.5)
    initial = le.new_game(f"sim-{seed}", [f"p{i}" for i in range(player_count)], rules=rules)

    state, actions, transitions = initial, [], []
    while state.status is GameStatus.PLAYING:
        if len(actions) >= MAX_ACTIONS:
            raise AssertionError(f"game {seed} did not finish")
        current = state.current_player.player_id
        chance = rng.random()
        # Rare timeouts/forfeits so most games still end by a player getting home.
        if chance < 0.02:
            action = {"type": "timeout", "dice_value": rng.randint(1, 6),
                      "turn_number": state.turn_number}
        elif chance < 0.0205:
            active = [p.player_id for p in state.players if p.status is PlayerStatus.ACTIVE]
            action = {"type": "forfeit", "player_id": rng.choice(active)}
        elif state.phase is TurnPhase.AWAITING_ROLL:
            action = {"type": "roll", "player_id": current, "value": rng.randint(1, 6)}
        else:
            moves = le.legal_moves(state)
            token = le.choose_move(state).token_index if rng.random() < 0.5 \
                else rng.choice(moves).token_index
            action = {"type": "move", "player_id": current, "token_index": token}
        transition = le.apply_action(state, action)
        actions.append(action)
        transitions.append((state, transition))
        state = transition.state
    return initial, actions, transitions, state


class SimulationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.games = [play_random_game(seed) for seed in range(GAMES)]

    def test_every_game_ends_with_one_winner_and_a_full_ranking(self):
        for initial, _, _, final in self.games:
            places = sorted(s["place"] for s in le.standings(final))
            self.assertEqual(places, list(range(1, len(final.players) + 1)))
            self.assertEqual(final.player(final.winner_id).finish_place, 1)
            self.assertNotEqual(final.player(final.winner_id).status, PlayerStatus.FORFEITED)

    def test_versions_go_up_by_one_and_tag_every_event(self):
        for _, _, transitions, _ in self.games:
            for before, t in transitions:
                self.assertEqual(t.state.version, before.version + 1)
                self.assertTrue(t.events)
                self.assertTrue(all(e.version == t.state.version for e in t.events))

    def test_opponents_never_share_an_unsafe_square(self):
        for _, _, transitions, _ in self.games:
            for _, t in transitions:
                owner_by_square = {}
                for p in t.state.players:
                    if p.status is PlayerStatus.FORFEITED:
                        continue
                    for progress in p.tokens:
                        sq = absolute_square(p.seat, progress)
                        if sq is None or sq in t.state.rules.safe_squares:
                            continue
                        other = owner_by_square.setdefault(sq, p.player_id)
                        self.assertEqual(other, p.player_id, f"square {sq} shared")

    def test_replaying_the_action_log_rebuilds_the_exact_game(self):
        for initial, actions, _, final in self.games:
            self.assertEqual(le.replay(initial, actions), final)

    def test_snapshots_survive_every_step(self):
        for _, _, transitions, _ in self.games[:30]:
            for _, t in transitions:
                self.assertEqual(le.GameState.from_dict(t.state.to_dict()), t.state)


if __name__ == "__main__":
    unittest.main()
