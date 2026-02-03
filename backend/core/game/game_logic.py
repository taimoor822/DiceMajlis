# Example path length (Ludo-style)
PATH_LENGTH = 52
HOME_POSITION = 100

def is_valid_move(token, dice):
    # Token already finished
    if token.is_finished:
        return False

    # Token in base: must roll 6 to enter
    if token.position == -1:
        return dice == 6

    # Token on path
    next_pos = token.position + dice

    # Cannot overshoot home
    if next_pos > PATH_LENGTH:
        return False

    return True


def calculate_new_position(token, dice):
    if token.position == -1:
        return 0  # enter board

    next_pos = token.position + dice

    if next_pos == PATH_LENGTH:
        return HOME_POSITION

    return next_pos

def get_next_player(room, current_player):
    players = list(room.players.order_by('created_at'))

    if len(players) == 0:
        return None

    current_index = players.index(current_player)

    for i in range(1, len(players) + 1):
        next_player = players[(current_index + i) % len(players)]

        # Skip players who finished all tokens
        unfinished_tokens = next_player.tokens.filter(is_finished=False)
        if unfinished_tokens.exists():
            return next_player

    return None
