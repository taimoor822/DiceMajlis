"""
Daily login reward: claim once per reward-day. Days in a row climb the cycle the
team sets up in the admin (``DailyRewardDay`` → a ``RewardBundle`` each).
``DailyRewardSettings`` decide what a missed day does (start again, or carry on)
and what comes after the last day (start the cycle again, or keep the last day).
"""

from __future__ import annotations

from datetime import timedelta

from django.utils import timezone

from . import days
from .engine import Granted, bundle_payload, grant
from .models import DailyRewardDay, DailyRewardSettings, RewardClaim

KIND = "daily_login"


class AlreadyClaimed(Exception):
    code = "already_claimed"


class NotAvailable(Exception):
    """No days are set up (the team turned the daily reward off)."""

    code = "daily_reward_unavailable"


def cycle() -> list[DailyRewardDay]:
    return list(DailyRewardDay.objects.select_related("bundle").order_by("day"))


def _last_claim(user) -> RewardClaim | None:
    return RewardClaim.objects.filter(user=user, kind=KIND).order_by("-reward_day").first()


def _after(day: int, length: int, settings: DailyRewardSettings) -> int:
    """The day that follows ``day`` in a cycle of ``length`` days."""
    if day < length:
        return day + 1
    return 1 if settings.after_last_day == DailyRewardSettings.AfterLastDay.LOOP else length


def _day_in_cycle(last: RewardClaim | None, today, length: int, settings: DailyRewardSettings) -> int:
    """Today's day in the cycle: the claimed one, or the one to claim."""
    if last is None or length == 0:
        return 1
    previous = min(last.streak_day or 1, length)  # the cycle may have been shortened
    if last.reward_day == today:
        return previous
    if last.reward_day == today - timedelta(days=1):
        return _after(previous, length, settings)
    if settings.on_miss == DailyRewardSettings.OnMiss.CONTINUE:
        return _after(previous, length, settings)
    return 1


def status(user, now=None) -> dict:
    now = now or timezone.now()
    today = days.reward_day(now)
    last = _last_claim(user)
    days_ = cycle()
    settings = DailyRewardSettings.load()
    day = _day_in_cycle(last, today, len(days_), settings)
    claimed = last is not None and last.reward_day == today
    return {
        "reward_day": today.isoformat(),
        "day": day,
        "claimed_today": claimed,
        # Tomorrow's day if today's is claimed and the streak goes on.
        "next_day": _after(day, len(days_), settings) if days_ else 1,
        "available": bool(days_),
        # What a missed day does: "restart" (day 1 again) or "continue".
        "on_miss": settings.on_miss,
        "days": [{"day": d.day, **bundle_payload(d.bundle.contents)} for d in days_],
        # A countdown for the app that doesn't trust the phone's clock.
        "seconds_until_reset": max(0, int((days.next_reset(now) - now).total_seconds())),
    }


def claim(user, now=None) -> Granted:
    now = now or timezone.now()
    today = days.reward_day(now)
    last = _last_claim(user)
    if last is not None and last.reward_day == today:
        raise AlreadyClaimed()
    days_ = cycle()
    if not days_:
        raise NotAvailable()
    day = _day_in_cycle(last, today, len(days_), DailyRewardSettings.load())
    result = grant(
        user,
        days_[day - 1].bundle.contents,
        kind=KIND,
        idempotency_key=f"{KIND}:{user.pk}:{today.isoformat()}",
        reward_day=today,
        streak_day=day,
        source=f"{KIND}:day{day}",
    )
    if not result.created:  # a second tap that raced the first
        raise AlreadyClaimed()
    return result
