"""
Wrong-password limit per account (on top of the per-IP rate limits): after
AUTH_LOGIN_MAX_FAILURES wrong passwords within AUTH_LOGIN_FAILURE_WINDOW, that
email can't sign in until the window has passed.
"""

import hashlib

from django.conf import settings
from django.core.cache import cache


def _key(email: str) -> str:
    return "login-failures:" + hashlib.sha256(email.encode()).hexdigest()


def _window() -> int:
    return int(settings.AUTH_LOGIN_FAILURE_WINDOW.total_seconds())


def blocked_for(email: str) -> int | None:
    """Seconds to wait if this email is locked, else None."""
    if cache.get(_key(email), 0) >= settings.AUTH_LOGIN_MAX_FAILURES:
        return _window()
    return None


def record_failure(email: str) -> None:
    key = _key(email)
    cache.add(key, 0, timeout=_window())
    try:
        cache.incr(key)
    except ValueError:  # expired between add and incr
        cache.set(key, 1, timeout=_window())


def clear_failures(email: str) -> None:
    cache.delete(_key(email))
