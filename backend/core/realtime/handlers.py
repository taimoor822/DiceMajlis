"""
Requests features answer over the socket. The socket itself handles ``auth``,
``ping``, ``subscribe`` and ``unsubscribe``; everything else is a handler
registered here (game actions arrive in 1.12, chat in Phase 5)::

    @handler("roll_dice", bucket="game")
    def roll_dice(ctx: Context, data: dict) -> dict:
        ...  # raise ProtocolError(code) to refuse; return the ack's data

Handlers are plain (synchronous) functions: they run in a worker thread and may
use the database. ``changes_state=True`` (the default) makes the request need a
``req_id`` and remembers its reply, so a retry is never applied twice.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

from . import protocol


@dataclass(frozen=True)
class Context:
    user: Any  # accounts.User
    session_id: str


@dataclass(frozen=True)
class Handler:
    type: str
    fn: Callable[[Context, dict], dict | None]
    bucket: str
    changes_state: bool


_RESERVED = {protocol.AUTH, protocol.PING, protocol.SUBSCRIBE, protocol.UNSUBSCRIBE}
_HANDLERS: dict[str, Handler] = {}


def register(type: str, fn, *, bucket: str, changes_state: bool = True) -> Handler:
    if type in _RESERVED:
        raise ValueError(f"{type!r} is handled by the socket itself")
    if type in _HANDLERS and _HANDLERS[type].fn is not fn:
        raise ValueError(f"a handler for {type!r} is already registered")
    entry = Handler(type, fn, bucket, changes_state)
    _HANDLERS[type] = entry
    return entry


def handler(type: str, *, bucket: str, changes_state: bool = True):
    """Decorator form of :func:`register`."""

    def wrap(fn):
        register(type, fn, bucket=bucket, changes_state=changes_state)
        return fn

    return wrap


def unregister(type: str) -> None:
    _HANDLERS.pop(type, None)


def get(type: str) -> Handler | None:
    return _HANDLERS.get(type)
