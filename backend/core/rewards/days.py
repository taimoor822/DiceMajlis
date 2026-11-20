"""
The reward-day: daily rewards reset at the same moment for everyone, decided by
the server's clock (never the phone's). Default: 00:00 Bahrain time.
"""

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from django.conf import settings
from django.utils import timezone


def _zone() -> ZoneInfo:
    return ZoneInfo(settings.REWARD_DAY_TIMEZONE)


def reward_day(now: datetime | None = None) -> date:
    local = (now or timezone.now()).astimezone(_zone())
    return (local - timedelta(hours=settings.REWARD_DAY_START_HOUR)).date()


def next_reset(now: datetime | None = None) -> datetime:
    """When the next reward-day starts."""
    following = reward_day(now) + timedelta(days=1)
    return datetime.combine(following, time(hour=settings.REWARD_DAY_START_HOUR), tzinfo=_zone())
