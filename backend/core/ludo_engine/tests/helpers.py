from __future__ import annotations

from ludo_engine import DEFAULT_RULES, GameState, PlayerState, Rules, TurnPhase


def make_state(
    *players: tuple[str, int, list[int]],
    current: int = 0,
    dice: int | None = None,
    rules: Rules = DEFAULT_RULES,
    sixes: int = 0,
    version: int = 0,
    turn_number: int = 1,
) -> GameState:
    """Build any position directly: make_state(("a", 0, [10, -1, -1, -1]), ("b", 2, [...]))."""
    return GameState(
        game_id="test",
        players=tuple(PlayerState(pid, seat, tuple(tokens)) for pid, seat, tokens in players),
        rules=rules,
        current_index=current,
        phase=TurnPhase.AWAITING_MOVE if dice is not None else TurnPhase.AWAITING_ROLL,
        dice_value=dice,
        consecutive_sixes=sixes,
        version=version,
        turn_number=turn_number,
    )


def progress_for_square(seat: int, square: int) -> int:
    """Progress a token of ``seat`` needs to stand on shared-track ``square``."""
    progress = (square - seat * 13) % 52
    assert progress <= 50, "that seat never stands on this square"
    return progress


BASE = [-1, -1, -1, -1]
