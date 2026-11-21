"""
A player's public profile, one per account: name, avatar, country, spoken
languages and XP. Created automatically with every account (signals.py).
"""

import uuid

from django.conf import settings
from django.db import models
from django.db.models import F, Q

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
    # Earned from activity; changed only through profiles.xp.add_xp() (one XpEntry
    # per change). The level is worked out from it (levels.py).
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


class XpIsAppendOnly(Exception):
    pass


class XpEntry(models.Model):
    """
    One change of an account's XP (append-only, like the wallet ledger). The sum
    of a profile's entries is its ``xp``; ``idempotency_key`` makes sure the same
    game or reward never adds XP twice.
    """

    class Reason(models.TextChoices):
        GAME = "game", "Game played"
        REWARD = "reward", "Reward"
        ADMIN = "admin", "Admin adjustment"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    profile = models.ForeignKey(Profile, related_name="xp_entries", on_delete=models.CASCADE)
    amount = models.PositiveIntegerField()
    xp_before = models.PositiveIntegerField()
    xp_after = models.PositiveIntegerField()
    reason = models.CharField(max_length=16, choices=Reason.choices)
    # What it was for, e.g. ("game", "12").
    reference_type = models.CharField(max_length=40, blank=True, default="")
    reference_id = models.CharField(max_length=64, blank=True, default="")
    # Reward-day it counts towards (daily caps), 00:00 Bahrain time.
    reward_day = models.DateField(db_index=True)
    idempotency_key = models.CharField(max_length=120)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["profile", "idempotency_key"], name="one_xp_entry_per_key"),
            models.CheckConstraint(condition=Q(amount__gt=0), name="xp_amount_positive"),
            models.CheckConstraint(
                condition=Q(xp_after=F("xp_before") + F("amount")), name="xp_after_adds_up"
            ),
        ]
        indexes = [models.Index(fields=["profile", "reason", "reward_day"], name="xp_daily_idx")]

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise XpIsAppendOnly("XP entries can't be changed.")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise XpIsAppendOnly("XP entries can't be deleted.")

    def __str__(self) -> str:
        return f"+{self.amount} XP ({self.reason})"
