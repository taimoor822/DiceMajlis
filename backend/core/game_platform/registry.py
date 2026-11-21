"""
The game registry: ``game_type`` → engine. Everything that runs a game looks it
up here instead of importing an engine directly.
"""

from __future__ import annotations

from .contract import GameEngine, UnknownGame, UnknownVariant, Variant

_GAMES: dict[str, GameEngine] = {}


def register(game: GameEngine) -> GameEngine:
    """Add a game. Registering the same ``game_type`` twice is a mistake."""
    if not isinstance(game, GameEngine):
        raise TypeError(f"{game!r} does not follow the GameEngine contract")
    if game.game_type in _GAMES and _GAMES[game.game_type] is not game:
        raise ValueError(f"game type {game.game_type!r} is already registered")
    if game.default_variant not in game.variants:
        raise ValueError(f"{game.game_type}: default variant {game.default_variant!r} is missing")
    _GAMES[game.game_type] = game
    return game


def unregister(game_type: str) -> None:
    """Remove a game (tests that register a toy game clean up with this)."""
    _GAMES.pop(game_type, None)


def get_game(game_type: str) -> GameEngine:
    try:
        return _GAMES[game_type]
    except KeyError:
        raise UnknownGame(f"no game {game_type!r}") from None


def get_variant(game_type: str, code: str | None = None) -> Variant:
    """A game's variant; its default one when ``code`` is empty."""
    game = get_game(game_type)
    code = code or game.default_variant
    try:
        return game.variants[code]
    except KeyError:
        raise UnknownVariant(f"{game_type} has no variant {code!r}") from None


def game_types() -> list[str]:
    return sorted(_GAMES)


def rule_errors() -> tuple[type[Exception], ...]:
    """Every registered engine's rule error, for ``except`` clauses."""
    return tuple({game.rule_error for game in _GAMES.values()})


def catalog() -> list[dict]:
    """What can be played, for the app: games, their variants and rules."""
    return [
        {
            "game_type": game.game_type,
            "default_variant": game.default_variant,
            "variants": [
                {**variant.to_dict(), "rules": game.rules_for(variant.code)}
                for variant in game.variants.values()
            ],
        }
        for game in (_GAMES[t] for t in game_types())
    ]
