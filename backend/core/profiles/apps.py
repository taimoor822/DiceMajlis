from django.apps import AppConfig


class ProfilesConfig(AppConfig):
    name = "profiles"
    verbose_name = "Profiles"

    def ready(self):
        from events.outbox import on

        from . import signals  # noqa: F401  (connects the receivers)
        from .xp import on_game_finished

        on("game_finished", on_game_finished)  # XP for real games (game.results)
