"""
Per-account rate limits and remembered replies, in the shared cache so every
server process (and every phone of the account) counts together.

Rate limits: ``REALTIME_RATE_LIMITS = {bucket: (messages, seconds)}``. Over the
limit, the message is refused with ``rate_limited``; far over it
(``REALTIME_ABUSE_FACTOR`` times), the socket is closed with 4429.

Remembered replies (idempotency): a request that changes something carries a
``req_id``. Its reply is kept for ``REALTIME_REPLY_MEMORY_SECONDS``; the same
``req_id`` again (a retry after a lost answer) gets that reply back and is not
applied twice.
"""

from __future__ import annotations

import time
from enum import Enum

from django.conf import settings
from django.core.cache import cache


class Verdict(Enum):
    OK = "ok"
    LIMITED = "limited"  # refuse this message
    ABUSE = "abuse"  # close the socket


def hit(user_id, bucket: str, *, now: float | None = None) -> Verdict:
    """Count one message of ``bucket`` for ``user_id``."""
    count, seconds = settings.REALTIME_RATE_LIMITS[bucket]
    window = int((time.time() if now is None else now) // seconds)
    key = f"rate:{user_id}:{bucket}:{window}"
    cache.add(key, 0, timeout=seconds + 1)
    try:
        used = cache.incr(key)
    except ValueError:  # expired between add and incr
        cache.set(key, 1, timeout=seconds + 1)
        used = 1
    if used <= count:
        return Verdict.OK
    if used > count * settings.REALTIME_ABUSE_FACTOR:
        return Verdict.ABUSE
    return Verdict.LIMITED


# ---- remembered replies --------------------------------------------------------

PENDING = "pending"


def _reply_key(user_id, req_id: str) -> str:
    return f"ws:req:{user_id}:{req_id}"


def claim(user_id, req_id: str) -> dict | str | None:
    """
    Start handling ``req_id``. Returns None when it is new (go ahead), the
    remembered reply when it was answered before, or PENDING while another
    socket is still working on it.
    """
    key = _reply_key(user_id, req_id)
    if cache.add(key, PENDING, timeout=settings.REALTIME_REPLY_MEMORY_SECONDS):
        return None
    return cache.get(key) or PENDING


def remember(user_id, req_id: str, reply: dict) -> None:
    cache.set(_reply_key(user_id, req_id), reply, timeout=settings.REALTIME_REPLY_MEMORY_SECONDS)


def forget(user_id, req_id: str) -> None:
    """Let a retry run again (the first try failed on the server's side)."""
    cache.delete(_reply_key(user_id, req_id))
