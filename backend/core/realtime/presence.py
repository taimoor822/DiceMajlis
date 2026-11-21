"""
Who is online, kept in the shared cache (Redis in production).

An account is online while ``presence:<user id>`` exists. Each socket refreshes
it on connect and on every ``ping`` (every 20 s), and it expires after
``REALTIME_PRESENCE_SECONDS`` (60 s): two missed pings = offline.

``presence:<user id>:sockets`` maps each open socket to when it was last heard
from, so the last socket to close marks the account offline at once (an
account can be signed in on two phones). Sockets not heard from for
``REALTIME_PRESENCE_SECONDS`` don't count: after a server restart (when old
sockets never said goodbye) they fall away on their own.

Features learn when an account comes online or goes offline with
:func:`listen` (``game`` uses it for ``player_disconnected`` /
``player_reconnected``, 1.14). Listeners run in the socket's sync thread.
"""

from __future__ import annotations

import logging
import time
import uuid
from typing import Callable

from django.conf import settings
from django.core.cache import cache
from django.utils import timezone

logger = logging.getLogger(__name__)

_COUNTER_SECONDS = 24 * 60 * 60

Listener = Callable[[object, bool], None]
_LISTENERS: list[Listener] = []


def _key(user_id) -> str:
    return f"presence:{user_id}"


def _sockets_key(user_id) -> str:
    return f"presence:{user_id}:sockets"


def _seconds() -> int:
    return settings.REALTIME_PRESENCE_SECONDS


def listen(listener: Listener) -> None:
    """Call ``listener(user_id, online)`` when an account comes online or goes offline."""
    if listener not in _LISTENERS:
        _LISTENERS.append(listener)


def unlisten(listener: Listener) -> None:
    if listener in _LISTENERS:
        _LISTENERS.remove(listener)


def _notify(user_id, online: bool) -> None:
    for listener in list(_LISTENERS):
        try:
            listener(user_id, online)
        except Exception:  # one feature's bug must not break sign-in or goodbye
            logger.exception("presence listener failed")


def _live_sockets(user_id) -> dict[str, float]:
    """Open sockets heard from recently (older ones belonged to a dead server)."""
    sockets = cache.get(_sockets_key(user_id))
    if not isinstance(sockets, dict):
        return {}
    cutoff = time.time() - _seconds()
    return {socket: seen for socket, seen in sockets.items() if seen >= cutoff}


def connected(user_id, socket_id: str | None = None) -> bool:
    """A socket of ``user_id`` signed in. True when the account just came online."""
    sockets = _live_sockets(user_id)
    was_online = bool(sockets)
    sockets[socket_id or uuid.uuid4().hex] = time.time()
    cache.set(_sockets_key(user_id), sockets, timeout=_COUNTER_SECONDS)
    cache.set(_key(user_id), int(timezone.now().timestamp()), timeout=_seconds())
    if not was_online:
        _notify(user_id, True)
    return not was_online


def heartbeat(user_id, socket_id: str | None = None) -> None:
    """A socket of ``user_id`` is still there (ping)."""
    cache.set(_key(user_id), int(timezone.now().timestamp()), timeout=_seconds())
    sockets = _live_sockets(user_id)
    now = time.time()
    if socket_id is None:
        sockets = {socket: now for socket in sockets}
    else:
        sockets[socket_id] = now
    cache.set(_sockets_key(user_id), sockets, timeout=_COUNTER_SECONDS)


def disconnected(user_id, socket_id: str | None = None) -> bool:
    """A socket of ``user_id`` closed. True when that was the last one (now offline)."""
    sockets = _live_sockets(user_id)
    if socket_id in sockets:
        del sockets[socket_id]
    elif socket_id is None and sockets:
        sockets.pop(next(iter(sockets)))
    if sockets:
        cache.set(_sockets_key(user_id), sockets, timeout=_COUNTER_SECONDS)
        return False
    cache.delete_many([_key(user_id), _sockets_key(user_id)])
    _notify(user_id, False)
    return True


def is_online(user_id) -> bool:
    return cache.get(_key(user_id)) is not None


def online(user_ids) -> set[str]:
    """Which of ``user_ids`` are online (one cache round trip)."""
    keys = {_key(user_id): str(user_id) for user_id in user_ids}
    return {keys[key] for key in cache.get_many(list(keys))}
