"""
Board geometry for a standard 4-seat Ludo board with a 52-square shared track.

Every token position is stored as *progress*: how far that token has travelled
from its own seat's start square. Progress is relative to the seat, so two
tokens of different colours with the same progress are on DIFFERENT squares.
Use :func:`absolute_square` whenever two players' tokens are compared.

Progress values
    -1          in base (not on the board yet)
    0 .. 50     on the shared track (51 squares; 0 is the seat's start square)
    51 .. 55    in the seat's private home column (cannot be captured)
    56          home (finished)

Seat layout matches ``LudoPath`` in the Flutter client: seat 0 = red, and each
following seat is the red path rotated by one more quarter turn, which puts
seat starts 13 squares apart on the shared track (0, 13, 26, 39).
"""

from __future__ import annotations

TRACK_LENGTH = 52
SEAT_COUNT = 4
SEAT_SPACING = TRACK_LENGTH // SEAT_COUNT  # 13

BASE_PROGRESS = -1
START_PROGRESS = 0
LAST_TRACK_PROGRESS = 50
FIRST_HOME_COLUMN_PROGRESS = 51
HOME_COLUMN_LENGTH = 5
HOME_PROGRESS = FIRST_HOME_COLUMN_PROGRESS + HOME_COLUMN_LENGTH  # 56

SEAT_COLORS: tuple[str, ...] = ("red", "blue", "green", "yellow")

# The star (safe) square sits 8 squares after each seat's start square.
STAR_OFFSET_FROM_START = 8


def _check_seat(seat: int) -> None:
    if not isinstance(seat, int) or isinstance(seat, bool) or not 0 <= seat < SEAT_COUNT:
        raise ValueError(f"seat must be an int in 0..{SEAT_COUNT - 1}, got {seat!r}")


def start_square(seat: int) -> int:
    """Absolute track square where a seat's tokens enter the board."""
    _check_seat(seat)
    return seat * SEAT_SPACING


def is_in_base(progress: int) -> bool:
    return progress == BASE_PROGRESS


def is_on_track(progress: int) -> bool:
    return START_PROGRESS <= progress <= LAST_TRACK_PROGRESS


def is_in_home_column(progress: int) -> bool:
    return FIRST_HOME_COLUMN_PROGRESS <= progress < HOME_PROGRESS


def is_home(progress: int) -> bool:
    return progress == HOME_PROGRESS


def is_valid_progress(progress: int) -> bool:
    return progress == BASE_PROGRESS or START_PROGRESS <= progress <= HOME_PROGRESS


def absolute_square(seat: int, progress: int) -> int | None:
    """
    Shared-track square (0..51) for a token, or ``None`` when the token is in
    base, in its private home column, or home. Only tokens with a square can
    meet (and capture) tokens of other seats.
    """
    _check_seat(seat)
    if not is_on_track(progress):
        return None
    return (progress + seat * SEAT_SPACING) % TRACK_LENGTH


def default_safe_squares() -> frozenset[int]:
    """Every seat's start square plus every star square (8 apart from the starts)."""
    starts = {seat * SEAT_SPACING for seat in range(SEAT_COUNT)}
    stars = {(start + STAR_OFFSET_FROM_START) % TRACK_LENGTH for start in starts}
    return frozenset(starts | stars)


def default_seats_for(player_count: int) -> tuple[int, ...]:
    """Seats used when the caller does not choose them: 2 players sit opposite each other."""
    if player_count == 2:
        return (0, 2)
    if player_count in (3, 4):
        return tuple(range(player_count))
    raise ValueError(f"Ludo needs 2 to {SEAT_COUNT} players, got {player_count}")
