"""
What achievements (and later missions) can count. Each metric reads its current
value from where the server already keeps it, so nothing is stored twice:

    games_played, wins, best_win_streak   statistics (stats), every game type added up
    level                                 account level (profiles, from XP)

Only real online games feed these (bot and offline games never count).
A new metric: add a reader here and say which domain event should check it
(progress.handlers).
"""

from __future__ import annotations

from typing import Callable


def _stat(name: str) -> Callable:
    def read(user) -> int:
        from stats.services import totals

        return totals(user)[name]

    return read


def _level(user) -> int:
    from profiles.levels import level_for_xp
    from profiles.services import profile_of

    return level_for_xp(profile_of(user).xp)


METRICS: dict[str, tuple[str, Callable]] = {
    "games_played": ("Online games played", _stat("games_played")),
    "wins": ("Online games won", _stat("wins")),
    "best_win_streak": ("Best win streak", _stat("best_win_streak")),
    "level": ("Account level", _level),
}


def read(user, metric: str) -> int:
    if metric not in METRICS:
        raise ValueError(f"unknown metric {metric!r}")
    return int(METRICS[metric][1](user))
