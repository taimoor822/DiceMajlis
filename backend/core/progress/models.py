"""
The progress engine (SOCIAL_MAJLIS §11, step S3): achievements first; missions
reuse it later (Phase 8). An achievement watches one metric (progress.metrics)
and unlocks a tier each time the metric reaches that tier's threshold; each tier
may give a reward through rewards.grant().
"""

from django.conf import settings
from django.db import models

RARITIES = [("common", "Common"), ("rare", "Rare"), ("epic", "Epic"), ("legendary", "Legendary")]


class Achievement(models.Model):
    """The catalog, managed in the admin."""

    code = models.SlugField(max_length=64, unique=True)
    name = models.CharField(max_length=60)
    description = models.CharField(max_length=200)
    # A picture the app draws (a key it knows; unknown keys get a trophy).
    icon = models.CharField(max_length=32, default="trophy")
    rarity = models.CharField(max_length=12, choices=RARITIES, default="common")
    # What it counts (progress.metrics.METRICS).
    metric = models.CharField(max_length=40)
    # Not shown until unlocked.
    hidden = models.BooleanField(default=False)
    active = models.BooleanField(default=True)
    sort_order = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["sort_order", "code"]

    def __str__(self) -> str:
        return self.name


class AchievementTier(models.Model):
    """One step of an achievement: reach ``threshold`` to unlock it (and get ``reward``)."""

    achievement = models.ForeignKey(Achievement, related_name="tiers", on_delete=models.CASCADE)
    threshold = models.PositiveBigIntegerField()
    # A reward bundle for rewards.grant(), e.g. {"gold": 100}; {} = no reward.
    reward = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["achievement", "threshold"]
        constraints = [
            models.UniqueConstraint(fields=["achievement", "threshold"], name="one_tier_per_threshold"),
        ]

    def __str__(self) -> str:
        return f"{self.achievement.code} ≥ {self.threshold}"


class AchievementUnlock(models.Model):
    """An account reached a tier (once: unique). The reward claim is kept with it."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="achievement_unlocks", on_delete=models.CASCADE)
    tier = models.ForeignKey(AchievementTier, related_name="unlocks", on_delete=models.PROTECT)
    # The metric's value when it unlocked.
    value = models.BigIntegerField()
    reward_claim = models.ForeignKey(
        "rewards.RewardClaim", null=True, blank=True, related_name="+", on_delete=models.SET_NULL
    )
    unlocked_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-unlocked_at"]
        constraints = [models.UniqueConstraint(fields=["user", "tier"], name="one_unlock_per_tier")]

    def __str__(self) -> str:
        return f"{self.user} unlocked {self.tier}"
