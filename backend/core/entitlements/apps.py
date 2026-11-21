from django.apps import AppConfig


class EntitlementsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "entitlements"
    verbose_name = "Entitlements (privileges)"

    def ready(self):
        from . import signals  # noqa: F401  (forget cached answers when the rules change)
