"""
Configurable game rules.

Gameplay numbers live here, not scattered through views, consumers or widgets.
A ``Rules`` object is stored inside every ``GameState`` so a game in progress
keeps the rules it started with, even if the defaults change later.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field, fields
from typing import Any, Mapping

from .board import TRACK_LENGTH, default_safe_squares


@dataclass(frozen=True)
class Rules:
    tokens_per_player: int = 4

    # Dice values that let a token leave base and enter on its start square.
    entry_rolls: frozenset[int] = frozenset({6})

    extra_turn_on_six: bool = True
    extra_turn_on_capture: bool = True
    extra_turn_on_finish: bool = True

    # Rolling this many sixes in a row ends the turn. 0 disables the rule.
    max_consecutive_sixes: int = 3

    capture_enabled: bool = True
    safe_squares: frozenset[int] = field(default_factory=default_safe_squares)

    # Enforced by the server's turn timer, not by the engine (the engine has no clock).
    turn_timeout_seconds: int = 30
    timeout_warning_seconds: int = 10

    # After this many timed-out turns in a row a player forfeits. 0 disables the rule.
    max_missed_turns: int = 3

    # True: the first player to bring every token home wins and the game ends.
    # False: play continues and every player gets a finishing place.
    end_when_first_player_finishes: bool = True

    def __post_init__(self) -> None:
        # Accept lists/sets from JSON and normalise them, so equality and hashing work.
        object.__setattr__(self, "entry_rolls", frozenset(self.entry_rolls))
        object.__setattr__(self, "safe_squares", frozenset(self.safe_squares))
        self.validate()

    def validate(self) -> None:
        if not 1 <= self.tokens_per_player <= 4:
            raise ValueError("tokens_per_player must be 1..4")
        if not self.entry_rolls or not all(_is_die_face(v) for v in self.entry_rolls):
            raise ValueError("entry_rolls must be a non-empty set of values 1..6")
        if not all(isinstance(s, int) and 0 <= s < TRACK_LENGTH for s in self.safe_squares):
            raise ValueError(f"safe_squares must be track squares 0..{TRACK_LENGTH - 1}")
        if self.max_consecutive_sixes < 0:
            raise ValueError("max_consecutive_sixes must be >= 0")
        if self.max_missed_turns < 0:
            raise ValueError("max_missed_turns must be >= 0")
        if self.turn_timeout_seconds <= 0:
            raise ValueError("turn_timeout_seconds must be > 0")
        if not 0 <= self.timeout_warning_seconds < self.turn_timeout_seconds:
            raise ValueError("timeout_warning_seconds must be 0..turn_timeout_seconds-1")

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["entry_rolls"] = sorted(self.entry_rolls)
        data["safe_squares"] = sorted(self.safe_squares)
        return data

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> "Rules":
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in data.items() if k in known})


def _is_die_face(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 6


DEFAULT_RULES = Rules()
