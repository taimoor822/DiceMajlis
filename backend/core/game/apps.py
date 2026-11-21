from django.apps import AppConfig


class GameConfig(AppConfig):
    name = 'game'

    def ready(self):
        # room/ and game/ channels for the /ws/v1/ socket, and the game actions
        # it answers (roll_dice, move_token, game_action, leave_game, request_state).
        from . import handlers, topics  # noqa: F401  (handlers register on import)

        topics.register()
