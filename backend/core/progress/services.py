"""
Achievements: check an account's metrics against every tier, unlock what was
reached (once), give the reward through rewards.grant(), and tell the account.

    check(user, ["wins", "games_played"], context={"room_code": "AB12CD"})
"""

from __future__ import annotations

from typing import Any, Iterable

from django.db import IntegrityError, transaction

from events.outbox import emit
from rewards.engine import bundle_payload, grant

from . import metrics
from .models import Achievement, AchievementTier, AchievementUnlock

ACHIEVEMENT_UNLOCKED = "achievement_unlocked"


def check(user, metric_names: Iterable[str] | None = None, *, context: dict | None = None) -> list[AchievementUnlock]:
    """Unlock every reached tier of active achievements on these metrics (all when None)."""
    names = set(metric_names) if metric_names is not None else set(metrics.METRICS)
    names &= set(metrics.METRICS)
    if not names:
        return []
    values = {name: metrics.read(user, name) for name in names}
    reached = (
        AchievementTier.objects.filter(achievement__active=True, achievement__metric__in=names)
        .exclude(unlocks__user=user)
        .select_related("achievement")
        .order_by("achievement__sort_order", "threshold")
    )
    unlocked = []
    for tier in reached:
        value = values[tier.achievement.metric]
        if value >= tier.threshold:
            unlock = _unlock(user, tier, value, context or {})
            if unlock is not None:
                unlocked.append(unlock)
    return unlocked


def _unlock(user, tier: AchievementTier, value: int, context: dict) -> AchievementUnlock | None:
    achievement = tier.achievement
    with transaction.atomic():
        try:
            with transaction.atomic():
                unlock = AchievementUnlock.objects.create(user=user, tier=tier, value=value)
        except IntegrityError:
            return None  # unlocked already (another connection was first)
        if tier.reward:
            granted = grant(
                user,
                tier.reward,
                kind="achievement",
                idempotency_key=f"achievement:{tier.pk}:{user.pk}",
                source=f"achievement:{achievement.code}:{tier.threshold}",
            )
            unlock.reward_claim = granted.claim
            unlock.save(update_fields=["reward_claim"])
        data = {
            "code": achievement.code,
            "name": achievement.name,
            "icon": achievement.icon,
            "rarity": achievement.rarity,
            "tier": tier_number(tier),
            "threshold": tier.threshold,
            "reward": bundle_payload(tier.reward),
            "room_code": context.get("room_code"),
        }
        # For moments and notifications (Phase 5); the account hears now.
        emit(ACHIEVEMENT_UNLOCKED, {"user_id": str(user.pk), **data})
        transaction.on_commit(lambda: _push(user, data))
    return unlock


def tier_number(tier: AchievementTier) -> int:
    """1 for the first tier of its achievement, 2 for the next ..."""
    return AchievementTier.objects.filter(achievement_id=tier.achievement_id, threshold__lte=tier.threshold).count()


def _push(user, data: dict) -> None:
    from realtime.publish import publish

    publish(f"user/{user.player_id}", "achievement_unlocked", data)


def achievements_payload(user) -> dict[str, Any]:
    """Every achievement the player may see, with progress (hidden ones once unlocked)."""
    unlocked = {
        u.tier_id: u.unlocked_at for u in AchievementUnlock.objects.filter(user=user).only("tier_id", "unlocked_at")
    }
    values: dict[str, int] = {}
    shown, hidden_left, total_tiers = [], 0, 0
    for achievement in Achievement.objects.filter(active=True).prefetch_related("tiers"):
        tiers = list(achievement.tiers.all())
        if not tiers or achievement.metric not in metrics.METRICS:
            continue
        done = [t for t in tiers if t.pk in unlocked]
        if achievement.hidden and not done:
            hidden_left += 1
            continue
        if achievement.metric not in values:
            values[achievement.metric] = metrics.read(user, achievement.metric)
        value = values[achievement.metric]
        upcoming = next((t for t in tiers if t.pk not in unlocked), None)
        total_tiers += len(tiers)
        shown.append(
            {
                "code": achievement.code,
                "name": achievement.name,
                "description": achievement.description,
                "icon": achievement.icon,
                "rarity": achievement.rarity,
                "metric": achievement.metric,
                "value": value,
                "tiers": [
                    {
                        "threshold": t.threshold,
                        "reward": bundle_payload(t.reward),
                        "unlocked_at": unlocked[t.pk].isoformat() if t.pk in unlocked else None,
                    }
                    for t in tiers
                ],
                "unlocked_tiers": len(done),
                "next_threshold": upcoming.threshold if upcoming else None,
                "completed": upcoming is None,
            }
        )
    return {
        "achievements": shown,
        "unlocked_tiers": sum(a["unlocked_tiers"] for a in shown),
        "total_tiers": total_tiers,
        "hidden_left": hidden_left,
    }
