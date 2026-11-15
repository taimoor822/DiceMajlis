"""
Engine errors. Each has a stable ``code`` the API/WebSocket layer can send to
the client as-is (e.g. ``{"type": "error", "code": "not_your_turn"}``).
"""

from __future__ import annotations


class EngineError(Exception):
    code = "engine_error"


class InvalidSetup(EngineError):
    code = "invalid_setup"


class InvalidAction(EngineError):
    code = "invalid_action"


class GameNotActive(EngineError):
    code = "game_not_active"


class UnknownPlayer(EngineError):
    code = "unknown_player"


class NotYourTurn(EngineError):
    code = "not_your_turn"


class WrongPhase(EngineError):
    """Rolling when a move is due, or moving before rolling."""

    code = "wrong_phase"


class InvalidDiceValue(EngineError):
    code = "invalid_dice_value"


class IllegalMove(EngineError):
    code = "illegal_move"
