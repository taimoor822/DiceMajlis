"""
Who is online, kept in the shared cache (Redis in production).

An account is online while ``presence:<user id>`` exists. Each socket refreshes
it on connect and on every ``ping`` (every 20 s), and it expires after
``REALTIME_PRESENCE_SECONDS`` (60 s): two missed pings = offline. A counter of
open sockets lets the last socket to close mark the account offline at once
(an account can be signed in on two phones).

Friends' online status (Phase 5) and ``player_disconnected`` (1.14) read this.
"""

from __future__ import annotations

from django.conf import settings
from django.core.cache import cache
from django.utils import timezone

_COUNTER_SECONDS = 24 * 60 * 60


def _key(user_id) -> str:
    return f"presence:{user_id}"


def _sockets_key(user_id) -> str:
    return f"presence:{user_id}:sockets"


def _seconds() -> int:
    return settings.REALTIME_PRESENCE_SECONDS


def connected(user_id) -> None:
    """A socket of ``user_id`` signed in."""
    key = _sockets_key(user_id)
    cache.add(key, 0, timeout=_COUNTER_SECONDS)
    try:
        cache.incr(key)
    except ValueError:  # expired between add and incr
        cache.set(key, 1, timeout=_COUNTER_SECONDS)
    heartbeat(user_id)


def heartbeat(user_id) -> None:
    """A socket of ``user_id`` is still there (ping)."""
    cache.set(_key(user_id), int(timezone.now().timestamp()), timeout=_seconds())
    cache.touch(_sockets_key(user_id), _COUNTER_SECONDS)


def disconnected(user_id) -> None:
    """A socket of ``user_id`` closed. The last one marks the account offline."""
    try:
        remaining = cache.decr(_sockets_key(user_id))
    except ValueError:  # counter gone (expired, or the cache restarted)
        remaining = 0
    if remaining <= 0:
        cache.delete_many([_key(user_id), _sockets_key(user_id)])


def is_online(user_id) -> bool:
    return cache.get(_key(user_id)) is not None


def online(user_ids) -> set[str]:
    """Which of ``user_ids`` are online (one cache round trip)."""
    keys = {_key(user_id): str(user_id) for user_id in user_ids}
    return {keys[key] for key in cache.get_many(list(keys))}
