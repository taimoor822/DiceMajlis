"""
Deterministic move choice, used for bots and for auto-moves on timeout.

Same state in, same move out (ties go to the lowest token index), so bot games
replay exactly. Scores are simple and readable on purpose; tune them here.
"""

from __future__ import annotations

from .board import LAST_TRACK_PROGRESS, TRACK_LENGTH, absolute_square
from .engine import Move, legal_moves
from .errors import IllegalMove
from .state import GameState, PlayerStatus

FINISH_SCORE = 1000
CAPTURE_SCORE = 500
ENTER_SCORE = 300
ESCAPE_DANGER_SCORE = 120
SAFE_LANDING_SCORE = 60
DANGER_PENALTY = 150


def choose_move(state: GameState) -> Move:
    moves = legal_moves(state)
    if not moves:
        raise IllegalMove("no legal moves to choose from")
    return max(moves, key=lambda m: (score_move(state, m), -m.token_index))


def score_move(state: GameState, move: Move) -> int:
    seat = state.current_player.seat
    score = max(move.to_progress, 0) - max(move.from_progress, 0)  # progress made

    if move.finishes_token:
        score += FINISH_SCORE
    score += CAPTURE_SCORE * len(move.captures)
    if move.enters_board:
        score += ENTER_SCORE

    from_square = absolute_square(seat, move.from_progress)
    if from_square is not None and _is_threatened(state, from_square):
        score += ESCAPE_DANGER_SCORE

    if move.to_square is None:
        if not move.finishes_token and not move.enters_board:
            score += SAFE_LANDING_SCORE  # home column: nobody can reach it
    elif move.to_square in state.rules.safe_squares:
        score += SAFE_LANDING_SCORE
    elif _is_threatened(state, move.to_square, ignore_captured=move):
        score -= DANGER_PENALTY

    return score


def _is_threatened(state: GameState, square: int, ignore_captured: Move | None = None) -> bool:
    """Could an opponent land on ``square`` with one roll (1..6) next turn?"""
    if square in state.rules.safe_squares or not state.rules.capture_enabled:
        return False
    captured = {(c.player_id, c.token_index) for c in ignore_captured.captures} if ignore_captured else set()
    me = state.current_player.player_id
    for other in state.players:
        if other.player_id == me or other.status is not PlayerStatus.ACTIVE:
            continue
        for token_index, progress in enumerate(other.tokens):
            if (other.player_id, token_index) in captured:
                continue
            their_square = absolute_square(other.seat, progress)
            if their_square is None:
                continue
            distance = (square - their_square) % TRACK_LENGTH
            if 1 <= distance <= 6 and progress + distance <= LAST_TRACK_PROGRESS:
                return True
    return False
