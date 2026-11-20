"""
Daily login reward: claim once per reward-day. Days in a row climb a 7-day cycle;
missing a day starts again at day 1. Amounts are placeholders until the admin
reward bundles of Phase 2 (S6b).
"""

from __future__ import annotations

from datetime import timedelta

from django.utils import timezone

from . import days
from .engine import Granted, grant
from .models import RewardClaim

KIND = "daily_login"

DAILY_LOGIN_CYCLE = (
    {"gold": 100},
    {"gold": 150},
    {"gold": 200},
    {"gold": 250},
    {"gold": 300},
    {"gold": 400},
    {"gold": 500, "diamond": 5},
)


class AlreadyClaimed(Exception):
    code = "already_claimed"


def _last_claim(user) -> RewardClaim | None:
    return RewardClaim.objects.filter(user=user, kind=KIND).order_by("-reward_day").first()


def _day_in_cycle(last: RewardClaim | None, today) -> int:
    """Today's day in the cycle (1–7): the claimed one, or the one to claim."""
    if last is None:
        return 1
    if last.reward_day == today:
        return last.streak_day
    if last.reward_day == today - timedelta(days=1):
        return last.streak_day % len(DAILY_LOGIN_CYCLE) + 1
    return 1


def status(user, now=None) -> dict:
    now = now or timezone.now()
    today = days.reward_day(now)
    last = _last_claim(user)
    return {
        "reward_day": today.isoformat(),
        "day": _day_in_cycle(last, today),
        "claimed_today": last is not None and last.reward_day == today,
        "days": [
            {"day": number, "gold": bundle.get("gold", 0), "diamond": bundle.get("diamond", 0)}
            for number, bundle in enumerate(DAILY_LOGIN_CYCLE, start=1)
        ],
        # A countdown for the app that doesn't trust the phone's clock.
        "seconds_until_reset": max(0, int((days.next_reset(now) - now).total_seconds())),
    }


def claim(user, now=None) -> Granted:
    now = now or timezone.now()
    today = days.reward_day(now)
    last = _last_claim(user)
    if last is not None and last.reward_day == today:
        raise AlreadyClaimed()
    day = _day_in_cycle(last, today)
    result = grant(
        user,
        DAILY_LOGIN_CYCLE[day - 1],
        kind=KIND,
        idempotency_key=f"{KIND}:{user.pk}:{today.isoformat()}",
        reward_day=today,
        streak_day=day,
        source=f"{KIND}:day{day}",
    )
    if not result.created:  # a second tap that raced the first
        raise AlreadyClaimed()
    return result
