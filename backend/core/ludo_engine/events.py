"""
Events the engine emits for each accepted action.

Event ``type`` values are the WebSocket event names in docs/ARCHITECTURE.md, so
the server can broadcast them without translating. Every event from one action
carries the state ``version`` that action produced.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from .state import GameState


class EventType(str, Enum):
    DICE_RESULT = "dice_result"
    TOKEN_MOVED = "token_moved"
    TOKEN_CAPTURED = "token_captured"
    TOKEN_FINISHED = "token_finished"
    TURN_ENDED = "turn_ended"
    TURN_STARTED = "turn_started"
    PLAYER_TIMEOUT = "player_timeout"
    PLAYER_FINISHED = "player_finished"
    PLAYER_FORFEITED = "player_forfeited"
    GAME_FINISHED = "game_finished"


class TurnEndReason(str, Enum):
    MOVED = "moved"
    NO_LEGAL_MOVES = "no_legal_moves"
    TOO_MANY_SIXES = "too_many_sixes"
    PLAYER_FINISHED = "player_finished"
    FORFEITED = "forfeited"


@dataclass(frozen=True)
class Event:
    type: EventType
    version: int
    data: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {"type": self.type.value, "version": self.version, "data": dict(self.data)}


@dataclass(frozen=True)
class Transition:
    """Result of one accepted action: the new state and what happened, in order."""

    state: GameState
    events: tuple[Event, ...]

    def event_types(self) -> list[str]:
        return [e.type.value for e in self.events]
