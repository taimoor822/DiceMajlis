"""
Dice sources.

The engine never rolls dice itself: the server rolls with ``SecureDice`` and
passes the value in. That keeps the engine deterministic (same actions in, same
state out), which is what makes replays and dispute checks possible.
"""

from __future__ import annotations

import secrets
from typing import Iterable, Protocol


class DiceRoller(Protocol):
    def roll(self) -> int: ...


class SecureDice:
    """Server dice. Uses the OS cryptographic RNG, so results cannot be predicted."""

    def roll(self) -> int:
        return secrets.randbelow(6) + 1


class ScriptedDice:
    """Fixed sequence of values, for tests and for replaying a recorded game."""

    def __init__(self, values: Iterable[int]) -> None:
        self._values = list(values)
        self._next = 0
        for value in self._values:
            if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= 6:
                raise ValueError(f"dice values must be 1..6, got {value!r}")

    def roll(self) -> int:
        if self._next >= len(self._values):
            raise RuntimeError("ScriptedDice ran out of values")
        value = self._values[self._next]
        self._next += 1
        return value

    @property
    def remaining(self) -> int:
        return len(self._values) - self._next
