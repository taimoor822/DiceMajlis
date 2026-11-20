"""
Dice Majlis Ludo engine: pure Python, no Django imports.

Server-authoritative: the server rolls dice (``SecureDice``), feeds actions in,
stores the returned state and broadcasts the returned events. The same rules
and test cases are the spec for the Dart engine used by offline mode.

Not implemented yet (TODO): blocks (two tokens of one colour blocking a square),
team mode victory, configurable "enter and move" variants.
"""

from .board import (
    BASE_PROGRESS,
    HOME_PROGRESS,
    MAX_PLAYERS,
    MIN_PLAYERS,
    SEAT_COLORS,
    TRACK_LENGTH,
    absolute_square,
    default_safe_squares,
    start_square,
)
from .bot import choose_move
from .dice import DiceRoller, ScriptedDice, SecureDice
from .engine import (
    Capture,
    Move,
    apply_action,
    check_roll,
    check_timeout,
    forfeit,
    legal_moves,
    move,
    new_game,
    replay,
    roll,
    standings,
    timeout,
)
from .errors import (
    EngineError,
    GameNotActive,
    IllegalMove,
    InvalidAction,
    InvalidDiceValue,
    InvalidSetup,
    NotYourTurn,
    UnknownPlayer,
    WrongPhase,
)
from .events import Event, EventType, Transition, TurnEndReason
from .rules import DEFAULT_RULES, Rules
from .state import GameState, GameStatus, PlayerState, PlayerStatus, TurnPhase

__all__ = [
    "BASE_PROGRESS",
    "HOME_PROGRESS",
    "MAX_PLAYERS",
    "MIN_PLAYERS",
    "SEAT_COLORS",
    "TRACK_LENGTH",
    "absolute_square",
    "default_safe_squares",
    "start_square",
    "choose_move",
    "DiceRoller",
    "ScriptedDice",
    "SecureDice",
    "Capture",
    "Move",
    "apply_action",
    "check_roll",
    "check_timeout",
    "forfeit",
    "legal_moves",
    "move",
    "new_game",
    "replay",
    "roll",
    "standings",
    "timeout",
    "EngineError",
    "GameNotActive",
    "IllegalMove",
    "InvalidAction",
    "InvalidDiceValue",
    "InvalidSetup",
    "NotYourTurn",
    "UnknownPlayer",
    "WrongPhase",
    "Event",
    "EventType",
    "Transition",
    "TurnEndReason",
    "DEFAULT_RULES",
    "Rules",
    "GameState",
    "GameStatus",
    "PlayerState",
    "PlayerStatus",
    "TurnPhase",
]
