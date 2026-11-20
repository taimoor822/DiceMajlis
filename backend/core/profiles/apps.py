from django.apps import AppConfig


class ProfilesConfig(AppConfig):
    name = "profiles"
    verbose_name = "Profiles"

    def ready(self):
        from . import signals  # noqa: F401  (connects the receivers)
