from django.apps import AppConfig


class GameConfig(AppConfig):
    name = 'game'

    def ready(self):
        # room/ and game/ channels for the /ws/v1/ socket.
        from . import topics

        topics.register()
