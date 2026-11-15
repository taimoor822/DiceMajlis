"""
Immutable game state.

Every engine call takes a ``GameState`` and returns a NEW one; nothing is ever
mutated in place. ``version`` goes up by exactly one per accepted action, so a
client that knows its version can be sent only what it missed.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from enum import Enum
from typing import Any, Mapping

from .board import (
    BASE_PROGRESS,
    HOME_PROGRESS,
    SEAT_COLORS,
    absolute_square,
    is_valid_progress,
)
from .errors import InvalidSetup, UnknownPlayer
from .rules import Rules

SCHEMA_VERSION = 1


class GameStatus(str, Enum):
    PLAYING = "playing"
    FINISHED = "finished"


class TurnPhase(str, Enum):
    AWAITING_ROLL = "awaiting_roll"
    AWAITING_MOVE = "awaiting_move"


class PlayerStatus(str, Enum):
    ACTIVE = "active"
    FINISHED = "finished"  # every token is home
    FORFEITED = "forfeited"  # left, or timed out too many times


@dataclass(frozen=True)
class PlayerState:
    player_id: str
    seat: int
    tokens: tuple[int, ...]  # progress of each token, see board.py
    status: PlayerStatus = PlayerStatus.ACTIVE
    missed_turns: int = 0
    finish_place: int | None = None

    @property
    def color(self) -> str:
        return SEAT_COLORS[self.seat]

    @property
    def all_tokens_home(self) -> bool:
        return all(p == HOME_PROGRESS for p in self.tokens)

    def with_token(self, index: int, progress: int) -> "PlayerState":
        tokens = list(self.tokens)
        tokens[index] = progress
        return replace(self, tokens=tuple(tokens))

    def to_dict(self) -> dict[str, Any]:
        return {
            "player_id": self.player_id,
            "seat": self.seat,
            "color": self.color,  # derived, for clients
            "status": self.status.value,
            "missed_turns": self.missed_turns,
            "finish_place": self.finish_place,
            "tokens": [
                {
                    "index": i,
                    "progress": p,
                    "square": absolute_square(self.seat, p),  # derived, for clients
                }
                for i, p in enumerate(self.tokens)
            ],
        }

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> "PlayerState":
        return cls(
            player_id=str(data["player_id"]),
            seat=int(data["seat"]),
            tokens=tuple(int(t["progress"]) for t in data["tokens"]),
            status=PlayerStatus(data.get("status", PlayerStatus.ACTIVE.value)),
            missed_turns=int(data.get("missed_turns", 0)),
            finish_place=data.get("finish_place"),
        )


@dataclass(frozen=True)
class GameState:
    game_id: str
    players: tuple[PlayerState, ...]  # in turn order (clockwise by seat)
    rules: Rules = field(default_factory=Rules)
    status: GameStatus = GameStatus.PLAYING
    phase: TurnPhase = TurnPhase.AWAITING_ROLL
    current_index: int = 0
    turn_number: int = 1
    dice_value: int | None = None
    consecutive_sixes: int = 0
    winner_id: str | None = None
    version: int = 0

    def __post_init__(self) -> None:
        self.check_invariants()

    # ---- lookups -------------------------------------------------------

    @property
    def current_player(self) -> PlayerState:
        return self.players[self.current_index]

    @property
    def is_finished(self) -> bool:
        return self.status is GameStatus.FINISHED

    def index_of(self, player_id: str) -> int:
        for i, player in enumerate(self.players):
            if player.player_id == player_id:
                return i
        raise UnknownPlayer(f"player {player_id!r} is not in game {self.game_id!r}")

    def player(self, player_id: str) -> PlayerState:
        return self.players[self.index_of(player_id)]

    def with_player(self, index: int, player: PlayerState) -> "GameState":
        players = list(self.players)
        players[index] = player
        return replace(self, players=tuple(players))

    # ---- integrity -----------------------------------------------------

    def check_invariants(self) -> None:
        """Rejects states that can never happen, e.g. ones loaded from a tampered store."""
        if not 2 <= len(self.players) <= len(SEAT_COLORS):
            raise InvalidSetup("a game needs 2 to 4 players")
        ids = [p.player_id for p in self.players]
        seats = [p.seat for p in self.players]
        if len(set(ids)) != len(ids):
            raise InvalidSetup("player ids must be unique")
        if len(set(seats)) != len(seats) or seats != sorted(seats):
            raise InvalidSetup("seats must be unique and in turn order")
        if not 0 <= self.current_index < len(self.players):
            raise InvalidSetup("current_index out of range")
        for p in self.players:
            if len(p.tokens) != self.rules.tokens_per_player:
                raise InvalidSetup(f"player {p.player_id!r} has the wrong number of tokens")
            if not all(is_valid_progress(t) for t in p.tokens):
                raise InvalidSetup(f"player {p.player_id!r} has a token off the board")
        if self.phase is TurnPhase.AWAITING_MOVE and self.dice_value is None:
            raise InvalidSetup("awaiting_move needs a dice value")
        if self.phase is TurnPhase.AWAITING_ROLL and self.dice_value is not None:
            raise InvalidSetup("awaiting_roll must not carry a dice value")
        if self.version < 0:
            raise InvalidSetup("version must be >= 0")

    # ---- serialisation -------------------------------------------------

    def to_dict(self) -> dict[str, Any]:
        """JSON-safe snapshot: what goes to Redis/Postgres and to clients as ``state_snapshot``."""
        return {
            "schema_version": SCHEMA_VERSION,
            "game_id": self.game_id,
            "version": self.version,
            "status": self.status.value,
            "phase": self.phase.value,
            "turn_number": self.turn_number,
            "current_player_id": self.current_player.player_id,
            "dice_value": self.dice_value,
            "consecutive_sixes": self.consecutive_sixes,
            "winner_id": self.winner_id,
            "players": [p.to_dict() for p in self.players],
            "rules": self.rules.to_dict(),
        }

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> "GameState":
        if data.get("schema_version") != SCHEMA_VERSION:
            raise InvalidSetup(f"unsupported schema_version {data.get('schema_version')!r}")
        players = tuple(PlayerState.from_dict(p) for p in data["players"])
        current_id = str(data["current_player_id"])
        current_index = next(
            (i for i, p in enumerate(players) if p.player_id == current_id), None
        )
        if current_index is None:
            raise InvalidSetup("current_player_id is not one of the players")
        return cls(
            game_id=str(data["game_id"]),
            players=players,
            rules=Rules.from_dict(data.get("rules", {})),
            status=GameStatus(data["status"]),
            phase=TurnPhase(data["phase"]),
            current_index=current_index,
            turn_number=int(data["turn_number"]),
            dice_value=data.get("dice_value"),
            consecutive_sixes=int(data.get("consecutive_sixes", 0)),
            winner_id=data.get("winner_id"),
            version=int(data["version"]),
        )


def initial_tokens(rules: Rules) -> tuple[int, ...]:
    return tuple(BASE_PROGRESS for _ in range(rules.tokens_per_player))
