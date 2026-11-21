"""Domain-event handlers: which events check which metrics. Idempotent (unlocks are unique)."""

from django.contrib.auth import get_user_model

from . import services


def _user(payload):
    return get_user_model().objects.filter(pk=payload.get("user_id")).first()


def on_stats_changed(payload, event=None) -> None:
    user = _user(payload)
    if user is not None:
        services.check(
            user, ["games_played", "wins", "best_win_streak"], context={"room_code": payload.get("room_code")}
        )


def on_xp_added(payload, event=None) -> None:
    if not payload.get("level_up"):
        return
    user = _user(payload)
    if user is not None:
        services.check(user, ["level"], context={"room_code": payload.get("room_code")})
