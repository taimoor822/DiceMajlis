from __future__ import annotations

BASE_POSITION = -1
ENTRY_POSITION = 0
PATH_LENGTH = 52
HOME_POSITION = 100


def is_valid_move(token, dice: int) -> bool:
    if dice is None:
        return False

    try:
        dice_value = int(dice)
    except (TypeError, ValueError):
        return False

    if dice_value < 1 or dice_value > 6:
        return False

    position = getattr(token, 'position', None)
    is_finished = getattr(token, 'is_finished', False) or position == HOME_POSITION

    if is_finished:
        return False

    if position == BASE_POSITION:
        return dice_value == 6

    if position is None:
        return False

    next_pos = position + dice_value
    return next_pos <= PATH_LENGTH


def calculate_new_position(token, dice: int) -> int:
    position = getattr(token, 'position', BASE_POSITION)

    dice_value = int(dice)

    if position == BASE_POSITION:
        return ENTRY_POSITION

    next_pos = position + dice_value
    if next_pos == PATH_LENGTH:
        return HOME_POSITION

    return next_pos


def get_next_player(room, current_player):
    players = list(room.players.order_by('joined_at'))
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
