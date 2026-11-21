"""
The ``/ws/v1/`` message format (ARCHITECTURE.md §7). Pure Python, no Django.

Client → server (a request)::

    {"v": 1, "type": "subscribe", "req_id": "5b1e…", "data": {"channel": "room/…"}}

Server → client::

    {"v": 1, "type": "ack",   "req_id": "5b1e…", "data": {…}}                # it worked
    {"v": 1, "type": "error", "req_id": "5b1e…", "code": "…", "message": "…"}  # it didn't
    {"v": 1, "type": "token_moved", "channel": "game/…", "version": 42, "data": {…}}  # an event

``code`` values are stable: the app switches on them, never on ``message``.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any

VERSION = 1

# Close codes (the app reacts to these).
CLOSE_BAD_TOKEN = 4401  # sign in again (refresh the access token, then reconnect)
CLOSE_FORBIDDEN = 4403
CLOSE_AUTH_TIMEOUT = 4408  # no auth message in time
CLOSE_RATE_LIMITED = 4429  # far too many messages: wait before reconnecting
CLOSE_TOO_BIG = 1009  # standard "message too big"

# Request types the server understands before and after signing in.
AUTH = "auth"
PING = "ping"
SUBSCRIBE = "subscribe"
UNSUBSCRIBE = "unsubscribe"

_TYPE = re.compile(r"^[a-z][a-z0-9_]{0,39}$")
_REQ_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


class ProtocolError(Exception):
    """A message the server refuses. ``code`` is sent to the app."""

    def __init__(self, code: str, message: str = ""):
        super().__init__(message or code)
        self.code = code
        self.message = message or code


@dataclass(frozen=True)
class Request:
    type: str
    req_id: str | None
    data: dict[str, Any] = field(default_factory=dict)


def parse(text: str) -> Request:
    """One client message → :class:`Request`, or ProtocolError."""
    try:
        raw = json.loads(text)
    except (TypeError, ValueError):
        raise ProtocolError("invalid_message", "Not JSON") from None
    if not isinstance(raw, dict):
        raise ProtocolError("invalid_message", "Expected a JSON object")
    if raw.get("v") != VERSION:
        raise ProtocolError("unsupported_version", f"Use protocol version {VERSION}")
    kind = raw.get("type")
    if not isinstance(kind, str) or not _TYPE.match(kind):
        raise ProtocolError("invalid_message", "Missing or bad type")
    req_id = raw.get("req_id")
    if req_id is not None and (not isinstance(req_id, str) or not _REQ_ID.match(req_id)):
        raise ProtocolError("invalid_message", "Bad req_id")
    data = raw.get("data", {})
    if data is None:
        data = {}
    if not isinstance(data, dict):
        raise ProtocolError("invalid_message", "data must be an object")
    return Request(kind, req_id, data)


def req_id_of(text: str) -> str | None:
    """Best effort: the req_id of a message that failed to parse (for the error reply)."""
    try:
        raw = json.loads(text)
    except (TypeError, ValueError):
        return None
    req_id = raw.get("req_id") if isinstance(raw, dict) else None
    return req_id if isinstance(req_id, str) and _REQ_ID.match(req_id) else None


def ack(req_id: str | None, data: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"v": VERSION, "type": "ack", "req_id": req_id, "data": data or {}}


def error(req_id: str | None, code: str, message: str = "") -> dict[str, Any]:
    return {"v": VERSION, "type": "error", "req_id": req_id, "code": code, "message": message or code}


def pong(req_id: str | None) -> dict[str, Any]:
    return {"v": VERSION, "type": "pong", "req_id": req_id}


def event(channel: str, type: str, data: dict[str, Any], *, version: int | None = None) -> dict[str, Any]:
    """A server push on ``channel``. ``version`` = the game state version, when there is one."""
    message: dict[str, Any] = {"v": VERSION, "type": type, "channel": channel, "data": data}
    if version is not None:
        message["version"] = version
    return message
