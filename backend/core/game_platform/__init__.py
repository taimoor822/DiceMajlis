"""
Dice Majlis game platform: one contract for every game, and the registry that
maps ``game_type`` → engine (PLATFORM.md §3). Pure Python, no Django.

Adding a game = a pure engine package + an adapter following
:class:`GameEngine` + ``register(...)`` below + its app module. Rooms, the game
service, bots and the turn timer don't change.
"""

from .contract import (
    GameEngine,
    InvalidOption,
    PlatformError,
    RandomSource,
    RoomOption,
    ScriptedRandom,
    SecureRandom,
    TurnInfo,
    UnknownGame,
    UnknownVariant,
    Variant,
)
from .ludo import CLASSIC, LUDO, LudoGame
from .registry import (
    catalog,
    game_types,
    get_game,
    get_variant,
    register,
    rule_errors,
    unregister,
)

# The games Dice Majlis offers today.
register(LudoGame())

__all__ = [
    "CLASSIC",
    "LUDO",
    "GameEngine",
    "InvalidOption",
    "LudoGame",
    "PlatformError",
    "RandomSource",
    "RoomOption",
    "ScriptedRandom",
    "SecureRandom",
    "TurnInfo",
    "UnknownGame",
    "UnknownVariant",
    "Variant",
    "catalog",
    "game_types",
    "get_game",
    "get_variant",
    "register",
    "rule_errors",
    "unregister",
]
