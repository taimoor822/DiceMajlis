"""
The shared test vectors (``shared/ludo/engine_vectors.json``) must always match
this engine, because the Flutter app's Dart engine is tested against them.
After a rules change, regenerate them from backend/core:

    python -m ludo_engine.vectors
"""

import json
import unittest

import ludo_engine as le
from ludo_engine.errors import EngineError
from ludo_engine.events import EventType, TurnEndReason
from ludo_engine.vectors import VECTORS_PATH, build_vectors, dumps

REGENERATE = "run `python -m ludo_engine.vectors` in backend/core and commit the file"


class VectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vectors = json.loads(dumps(build_vectors()))

    def test_committed_file_matches_the_engine(self):
        self.assertTrue(VECTORS_PATH.exists(), f"{VECTORS_PATH} is missing: {REGENERATE}")
        committed = json.loads(VECTORS_PATH.read_text(encoding="utf-8"))
        # assertTrue, not assertEqual: a full diff of the file is unreadable.
        self.assertTrue(committed == self.vectors, f"engine_vectors.json is out of date: {REGENERATE}")

    def test_vectors_cover_every_event_turn_end_and_error(self):
        events, reasons, errors = set(), set(), set()
        for game in self.vectors["games"]:
            for step in game["steps"]:
                if "error" in step:
                    errors.add(step["error"])
                for kind, data in step.get("events", []):
                    events.add(kind)
                    if kind == EventType.TURN_ENDED.value:
                        reasons.add(data["reason"])
        for case in self.vectors["setups"] + self.vectors["snapshots"]:
            if "error" in case:
                errors.add(case["error"])

        self.assertEqual(events, {e.value for e in EventType})
        self.assertEqual(reasons, {r.value for r in TurnEndReason})
        codes = {cls.code for cls in EngineError.__subclasses__()}
        self.assertEqual(errors, codes)

    def test_every_game_replays_step_by_step(self):
        for game in self.vectors["games"]:
            state = le.GameState.from_dict(game["initial"])
            for number, step in enumerate(game["steps"]):
                where = f"{game['name']} step {number}"
                if "error" in step:
                    with self.assertRaises(EngineError, msg=where) as caught:
                        le.apply_action(state, step["action"])
                    self.assertEqual(caught.exception.code, step["error"], where)
                    continue
                if "bot" in step:
                    self.assertEqual(le.choose_move(state).token_index, step["bot"], where)
                transition = le.apply_action(state, step["action"])
                self.assertEqual(
                    [[e.type.value, e.data] for e in transition.events], step["events"], where
                )
                self.assertTrue(all(e.version == state.version + 1 for e in transition.events))
                state = transition.state
                if "state" in step:
                    self.assertEqual(state.to_dict(), step["state"], where)
            self.assertEqual(state.to_dict(), game["final"], game["name"])
            self.assertTrue(state.is_finished, game["name"])


if __name__ == "__main__":
    unittest.main()
