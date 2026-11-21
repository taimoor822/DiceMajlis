import uuid

from django.conf import settings
from django.db import models


class RewardClaim(models.Model):
    """
    One reward given to a player, written by grant() together with its ledger
    entries. The idempotency key makes a second claim of the same reward impossible.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, related_name="reward_claims", on_delete=models.CASCADE
    )
    kind = models.CharField(max_length=32)  # "daily_login", later "achievement", "event" ...
    # For daily rewards: the server reward-day it counts for, and the day in the cycle.
    reward_day = models.DateField(null=True, blank=True)
    streak_day = models.PositiveSmallIntegerField(null=True, blank=True)
    bundle = models.JSONField(help_text='What was given, e.g. {"gold": 100, "xp": 20, "items": [...]}')
    # What exactly it was for, e.g. "daily_login:day3" or "achievement:wins:10".
    source = models.CharField(max_length=100, blank=True, default="")
    idempotency_key = models.CharField(max_length=120, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["user", "kind", "reward_day"])]

    def __str__(self) -> str:
        return f"{self.kind} for {self.user}: {self.bundle}"


class RewardBundle(models.Model):
    """
    A reward the team sets up in the admin (ROYAL_VIP_ECONOMY §5), given through
    grant(). ``contents`` is a bundle: currencies, XP and items, e.g.
    {"gold": 500, "diamond": 5, "xp": 50, "items": [{"code": "dice_pearl", "days": 7}]}.
    """

    code = models.SlugField(max_length=64, unique=True)
    name = models.CharField(max_length=80)
    contents = models.JSONField()
    active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"{self.name} ({self.code})"


class DailyRewardDay(models.Model):
    """One day of the daily login cycle and the bundle it gives (day 1, 2, 3 ...)."""

    day = models.PositiveSmallIntegerField(unique=True)
    bundle = models.ForeignKey(RewardBundle, related_name="+", on_delete=models.PROTECT)

    class Meta:
        ordering = ["day"]

    def __str__(self) -> str:
        return f"Day {self.day}: {self.bundle.code}"


class DailyRewardSettings(models.Model):
    """How the daily streak behaves (one row; edit it in the admin)."""

    class OnMiss(models.TextChoices):
        RESTART = "restart", "Start again at day 1"
        CONTINUE = "continue", "Carry on from the next day"

    class AfterLastDay(models.TextChoices):
        LOOP = "loop", "Start the cycle again"
        STAY = "stay", "Keep giving the last day"

    on_miss = models.CharField(max_length=12, choices=OnMiss.choices, default=OnMiss.RESTART)
    after_last_day = models.CharField(max_length=12, choices=AfterLastDay.choices, default=AfterLastDay.LOOP)

    class Meta:
        verbose_name_plural = "daily reward settings"

    @classmethod
    def load(cls) -> "DailyRewardSettings":
        settings, _ = cls.objects.get_or_create(pk=1)
        return settings

    def __str__(self) -> str:
        return f"Missed a day: {self.get_on_miss_display()}; after the last day: {self.get_after_last_day_display()}"
