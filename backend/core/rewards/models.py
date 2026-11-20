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
    bundle = models.JSONField(help_text='What was given, e.g. {"gold": 100}')
    idempotency_key = models.CharField(max_length=120, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["user", "kind", "reward_day"])]

    def __str__(self) -> str:
        return f"{self.kind} for {self.user}: {self.bundle}"
