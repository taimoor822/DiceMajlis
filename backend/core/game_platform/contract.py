"""
What every game engine looks like to the platform.

Rooms, the game service (locking, versions, action log, turn timer, bots),
matchmaking and ratings talk to games only through this contract, so a new game
(Domino, Jackaroo) plugs in without changing them. Each game is a pure engine
package (like ``ludo_engine``) plus a small adapter that implements
:class:`GameEngine` and is registered in :mod:`game_platform.registry`.

Pure Python like the engines: no Django, no database, no clock. Anything random
(dice, shuffled tiles) comes in through a :class:`RandomSource`, so every game
can be replayed from its action log.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass, field
from typing import Any, Iterable, Mapping, Protocol, Sequence, runtime_checkable


class PlatformError(Exception):
    """A request the platform itself refuses. ``code`` is sent to the app as-is."""

    code = "platform_error"


class UnknownGame(PlatformError):
    code = "unknown_game"


class UnknownVariant(PlatformError):
    code = "unknown_variant"


@dataclass(frozen=True)
class Variant:
    """
    One way to play a game: a preset of the engine's rules, as data. Classic
    Ludo is the empty preset; Quick Ludo would be ``{"tokens_per_player": 2}``.
    """

    code: str
    rules: Mapping[str, Any] = field(default_factory=dict)  # changes to the engine's default rules
    min_players: int = 2
    max_players: int = 4
    default_players: int = 4
    # May be played in ranked queues (Phase 6). Never set by anything bought.
    ranked: bool = False

    def __post_init__(self) -> None:
        if not 1 <= self.min_players <= self.default_players <= self.max_players:
            raise ValueError(f"variant {self.code!r}: needs min <= default <= max players")

    def allows(self, player_count: int) -> bool:
        return self.min_players <= player_count <= self.max_players

    def to_dict(self) -> dict[str, Any]:
        return {
            "code": self.code,
            "min_players": self.min_players,
            "max_players": self.max_players,
            "default_players": self.default_players,
            "ranked": self.ranked,
        }


@dataclass(frozen=True)
class TurnInfo:
    """What the game service needs to know about any game's state."""

    version: int
    finished: bool
    current_player_id: str | None
    turn_number: int
    # Turn timer for this game, or None when it has none.
    turn_seconds: int | None
    warning_seconds: int | None
    winner_id: str | None
    # Players still in the game (not finished, not out).
    active_player_ids: tuple[str, ...] = ()


class RandomSource(Protocol):
    def randbelow(self, n: int) -> int:
        """A whole number from 0 to n - 1."""
        ...


class SecureRandom:
    """The server's randomness: the OS cryptographic source (can't be predicted)."""

    def randbelow(self, n: int) -> int:
        return secrets.randbelow(n)


class ScriptedRandom:
    """Fixed values, for tests: each call returns the next one."""

    def __init__(self, values: Iterable[int]) -> None:
        self._values = list(values)

    def randbelow(self, n: int) -> int:
        if not self._values:
            raise RuntimeError("ScriptedRandom ran out of values")
        value = self._values.pop(0)
        if not 0 <= value < n:
            raise ValueError(f"scripted value {value} is not below {n}")
        return value


@runtime_checkable
class Transition(Protocol):
    """One accepted action: the new state and its events (each with ``to_dict()``)."""

    state: Any
    events: Sequence[Any]


@runtime_checkable
class GameEngine(Protocol):
    """
    The shape of every game. States are the engine's own objects; the platform
    stores them with :meth:`dump` and gets them back with :meth:`load`.
    """

    game_type: str  # "ludo", later "domino", "jackaroo"
    default_variant: str
    variants: Mapping[str, Variant]
    # The engine's base error class: refused actions raise it with a ``code``.
    rule_error: type[Exception]

    def new_game(
        self,
        game_id: str,
        player_ids: Sequence[str],
        *,
        variant: str,
        seats: Sequence[int] | None = None,
        first_player_id: str | None = None,
    ) -> Any:
        """A game at version 0 for ``variant``."""

    def rules_for(self, variant: str) -> dict[str, Any]:
        """The full rules a variant plays with (defaults + its changes)."""

    def load(self, data: Mapping[str, Any]) -> Any:
        """A stored snapshot back into a state (refuses tampered ones)."""

    def dump(self, state: Any) -> dict[str, Any]:
        """JSON-safe snapshot of a state."""

    def info(self, state: Any) -> TurnInfo: ...

    def prepare_action(self, state: Any, action: Mapping[str, Any], random: RandomSource) -> dict[str, Any]:
        """
        Fill in what the server decides (dice, a bot's choice, an idle player's
        auto-move) so the logged action replays exactly. Checks first, so a
        refused request never uses the random source.
        """

    def apply_action(self, state: Any, action: Mapping[str, Any]) -> Transition: ...

    def legal_actions(self, state: Any, player_id: str) -> list[dict[str, Any]]:
        """What ``player_id`` may do now (empty when it isn't their turn)."""

    def bot_action(self, state: Any) -> dict[str, Any]:
        """What a bot does for the current player (randomness still to be prepared)."""

    def view_for(self, state: Any, player_id: str | None) -> dict[str, Any]:
        """The state as ``player_id`` may see it (hides others' hands in hidden-information games)."""

    def standings(self, state: Any) -> list[dict[str, Any]]:
        """Places for ratings and rewards: ``[{"player_id", "place", "status"}]``."""

    def replay(self, initial: Any, actions: Iterable[Mapping[str, Any]]) -> Any: ...
