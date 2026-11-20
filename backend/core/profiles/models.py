"""
A player's public profile, one per account: name, avatar, country, spoken
languages and XP. Created automatically with every account (signals.py).
"""

from django.conf import settings
from django.db import models

from . import choices


class Profile(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        primary_key=True,
        related_name="profile",
        on_delete=models.CASCADE,
    )
    display_name = models.CharField(max_length=choices.NAME_MAX_LENGTH)
    avatar = models.CharField(max_length=32, default=choices.AVATARS[0])
    # ISO code (profiles.countries), or "" when the player doesn't show one.
    country = models.CharField(max_length=2, blank=True, default="")
    # Spoken-language codes from choices.LANGUAGES, in the player's order.
    languages = models.JSONField(default=list, blank=True)
    # Earned from activity (Phase 2); the level is worked out from it (levels.py).
    xp = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return self.display_name


def default_display_name(user) -> str:
    """Until the player picks one: "Player" and the last 4 digits of the Player ID."""
    return f"Player {user.player_id % 10000:04d}"


def default_avatar(user) -> str:
    """A different starting picture for different players."""
    return choices.AVATARS[user.player_id % len(choices.AVATARS)]
