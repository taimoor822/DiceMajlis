"""
Account level from XP. Level 1 starts at 0 XP and each level needs 100 XP more
than the one before: level 2 at 100, level 3 at 300, level 4 at 600 ...

XP comes from activity (games, missions); earning it is built in Phase 2. The app
never computes levels: it shows what the server sends.
"""

from math import isqrt

XP_STEP = 100


def xp_for_level(level: int) -> int:
    """Total XP needed to reach ``level``."""
    return XP_STEP * level * (level - 1) // 2


def level_for_xp(xp: int) -> int:
    xp = max(0, xp)
    # Largest level with xp_for_level(level) <= xp.
    level = (1 + isqrt(1 + 8 * xp // XP_STEP)) // 2
    while xp_for_level(level + 1) <= xp:
        level += 1
    while level > 1 and xp_for_level(level) > xp:
        level -= 1
    return max(1, level)


def level_progress(xp: int) -> dict:
    """``{level, xp, level_xp, next_level_xp}`` for a progress bar."""
    level = level_for_xp(xp)
    return {
        "level": level,
        "xp": xp,
        "level_xp": xp_for_level(level),
        "next_level_xp": xp_for_level(level + 1),
    }
