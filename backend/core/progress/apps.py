from django.apps import AppConfig


class ProgressConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "progress"
    verbose_name = "Progress (achievements)"

    def ready(self):
        from events.outbox import on

        from . import handlers

        on("player_stats_changed", handlers.on_stats_changed)
        on("xp_added", handlers.on_xp_added)
