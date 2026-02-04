from __future__ import annotations

from .models import Token


BASE_POSITION = -1
ENTRY_POSITION = 0
FINISH_POSITION = 100
SAFE_ZONES: set[int] = {0, 10, 20, 30, 40, 50, 60, 70, 80, 90}


def _normalize_dice(dice) -> int | None:
    try:
        value = int(dice)
    except (TypeError, ValueError):
        return None
    if value < 1 or value > 6:
        return None
    return value


def is_valid_move(token, dice) -> bool:
    """
    Server-authoritative Ludo move validation.
    - Token at -1 can only move on a 6 (enters at 0).
    - Token cannot move beyond 100.
    - Finished tokens cannot move.
    """
    dice_value = _normalize_dice(dice)
    if dice_value is None:
        return False

    position = getattr(token, "position", None)
    if position is None:
        return False

    is_finished = getattr(token, "is_finished", False) or position == FINISH_POSITION
    if is_finished:
        return False

    if position == BASE_POSITION:
        return dice_value == 6

    return position + dice_value <= FINISH_POSITION


def calculate_new_position(token, dice) -> int:
    """
    Compute the new position for a valid move.
    """
    dice_value = _normalize_dice(dice)
    if dice_value is None:
        return getattr(token, "position", BASE_POSITION)

    position = getattr(token, "position", BASE_POSITION)

    if position == BASE_POSITION:
        return ENTRY_POSITION

    return position + dice_value


def get_next_player(room, current_player):
    """
    Returns the next player in join order who still has unfinished tokens.
    """
    players = list(room.players.order_by("joined_at"))
    if not players:
        return None

    try:
        current_index = players.index(current_player)
    except ValueError:
        current_index = 0

    for i in range(1, len(players) + 1):
        next_player = players[(current_index + i) % len(players)]
        if next_player.tokens.filter(is_finished=False).exists():
            return next_player

    return None


def kill_enemy_tokens(*, room, moving_player, position: int) -> list[str]:
    """
    Kill (send to base) any enemy tokens on the given position.
    Only applies to board positions (0..99). Never kills at base/home.
    Safe zones are immune to kills.
    Returns killed token ids as strings.
    """
    if position < ENTRY_POSITION or position >= FINISH_POSITION:
        return []

    if position in SAFE_ZONES:
        return []

    killed_tokens: list[str] = []

    enemies = (
        Token.objects.filter(player__room=room, position=position)
        .exclude(player=moving_player)
    )

    for enemy in enemies:
        enemy.position = BASE_POSITION
        enemy.is_finished = False
        enemy.save(update_fields=["position", "is_finished"])
        killed_tokens.append(str(enemy.id))

    return killed_tokens
