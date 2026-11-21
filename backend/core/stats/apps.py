from django.apps import AppConfig


class StatsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "stats"
    verbose_name = "Statistics"

    def ready(self):
        from events.outbox import on

        from .services import on_game_finished

        on("game_finished", on_game_finished)  # real games only (game.results)
