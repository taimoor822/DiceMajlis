"""
A tiny second game, only for tests: proof that a game other than Ludo plugs
into the platform (registry, game service, bots, timer) without changes there.

"Race": players take turns drawing 1–3 (server random) and add it to their
score; the first to reach the target wins.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Any, Iterable, Mapping, Sequence

from game_platform import RandomSource, TurnInfo, Variant

RACE = "race"


class RaceError(Exception):
    code = "race_error"


class NotYourTurn(RaceError):
    code = "not_your_turn"


class Finished(RaceError):
    code = "game_not_active"


@dataclass(frozen=True)
class RaceEvent:
    type: str
    version: int
    data: dict

    def to_dict(self) -> dict:
        return {"type": self.type, "version": self.version, "data": self.data}


@dataclass(frozen=True)
class RaceState:
    game_id: str
    players: tuple[str, ...]
    scores: tuple[int, ...]
    target: int
    current: int = 0
    turn_number: int = 1
    version: int = 0
    winner_id: str | None = None


@dataclass(frozen=True)
class RaceTransition:
    state: RaceState
    events: tuple[RaceEvent, ...]


class RaceGame:
    game_type = RACE
    default_variant = "short"
    variants = {
        "short": Variant(code="short", rules={"target": 5}, min_players=2, max_players=3, default_players=2),
        "long": Variant(code="long", rules={"target": 20}, min_players=2, max_players=3, default_players=3),
    }
    rule_error = RaceError
    player_action_types = frozenset({"draw"})

    def rules_for(self, variant: str) -> dict[str, Any]:
        return dict(self.variants[variant].rules)

    def new_game(self, game_id, player_ids: Sequence[str], *, variant, seats=None, first_player_id=None):
        players = tuple(str(p) for p in player_ids)
        first = players.index(first_player_id) if first_player_id else 0
        return RaceState(game_id, players, tuple(0 for _ in players), self.rules_for(variant)["target"], current=first)

    def load(self, data: Mapping[str, Any]) -> RaceState:
        return RaceState(
            data["game_id"], tuple(data["players"]), tuple(data["scores"]), data["target"],
            data["current"], data["turn_number"], data["version"], data["winner_id"],
        )

    def dump(self, state: RaceState) -> dict[str, Any]:
        return {
            "game_id": state.game_id, "players": list(state.players), "scores": list(state.scores),
            "target": state.target, "current": state.current, "turn_number": state.turn_number,
            "version": state.version, "winner_id": state.winner_id,
        }

    def info(self, state: RaceState) -> TurnInfo:
        return TurnInfo(
            version=state.version,
            finished=state.winner_id is not None,
            current_player_id=state.players[state.current],
            turn_number=state.turn_number,
            turn_seconds=20,
            warning_seconds=5,
            winner_id=state.winner_id,
            active_player_ids=() if state.winner_id else state.players,
        )

    def prepare_action(self, state, action, random: RandomSource):
        kind = action.get("type")
        if kind in ("draw", "bot", "timeout"):
            self._check(state, action.get("player_id", state.players[state.current]))
            return {"type": "draw", "player_id": state.players[state.current], "value": random.randbelow(3) + 1}
        return dict(action)

    def apply_action(self, state: RaceState, action) -> RaceTransition:
        if action.get("type") != "draw":
            raise RaceError(f"unknown action {action.get('type')!r}")
        self._check(state, action["player_id"])
        version = state.version + 1
        scores = list(state.scores)
        scores[state.current] += action["value"]
        events = [RaceEvent("drew", version, {"player_id": action["player_id"], "value": action["value"]})]
        winner = action["player_id"] if scores[state.current] >= state.target else None
        if winner:
            events.append(RaceEvent("game_finished", version, {"winner_id": winner}))
            nxt = state.current
        else:
            nxt = (state.current + 1) % len(state.players)
        new = replace(state, scores=tuple(scores), current=nxt, turn_number=state.turn_number + (0 if winner else 1),
                      version=version, winner_id=winner)
        return RaceTransition(new, tuple(events))

    def legal_actions(self, state, player_id):
        if state.winner_id or state.players[state.current] != player_id:
            return []
        return [{"type": "draw", "player_id": player_id}]

    def bot_action(self, state):
        return {"type": "draw", "player_id": state.players[state.current]}

    def view_for(self, state, player_id):
        return self.dump(state)

    def standings(self, state):
        order = sorted(range(len(state.players)), key=lambda i: -state.scores[i])
        return [{"player_id": state.players[i], "place": n + 1, "status": "active"} for n, i in enumerate(order)]

    def replay(self, initial, actions: Iterable[Mapping[str, Any]]):
        state = initial
        for action in actions:
            state = self.apply_action(state, action).state
        return state

    def _check(self, state: RaceState, player_id) -> None:
        if state.winner_id is not None:
            raise Finished("the race is over")
        if player_id not in state.players or state.players[state.current] != player_id:
            raise NotYourTurn("not your turn")
