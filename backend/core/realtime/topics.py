"""
The channels a socket can subscribe to (PLATFORM.md §13), and who may.

A channel name is ``<kind>/<key>``, e.g. ``room/2f6c…`` or ``user/112156630``.
Each kind is a :class:`Topic`: it checks the key, decides who may subscribe, and
gives the events a new subscriber gets first (the current state), so the app
never misses what happened before it subscribed.

``user/`` and ``notifications/`` live here; features register their own kinds
(``game.topics`` adds ``room/`` and ``game/``) with :func:`register`. Chat,
tournaments and events add theirs when they are built.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from .protocol import ProtocolError
from .protocol import event as make_event

_KIND = re.compile(r"^[a-z]{1,20}$")
_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_PLAYER_ID = re.compile(r"^[0-9]{9}$")
_NUMBER = re.compile(r"^[1-9][0-9]{0,18}$")


@dataclass(frozen=True)
class Channel:
    kind: str
    key: str

    @property
    def name(self) -> str:
        return f"{self.kind}/{self.key}"

    @property
    def group(self) -> str:
        """The Channels group every subscriber of this channel joins."""
        return f"v1.{self.kind}.{self.key}"


class Topic:
    """One kind of channel. Subclasses override the three checks."""

    kind = ""

    def parse_key(self, key: str) -> str:
        """The key in its one accepted spelling, or ProtocolError('unknown_channel')."""
        raise NotImplementedError

    def authorize(self, user, key: str) -> None:
        """Raise ProtocolError when ``user`` may not subscribe."""
        raise NotImplementedError

    def initial_events(self, user, key: str) -> list[dict[str, Any]]:
        """Events a new subscriber gets right after the ack (the current state)."""
        return []

    def catch_up(self, user, key: str, since: int) -> list[dict[str, Any]] | None:
        """
        For a subscriber coming back with ``since`` (the last version it saw):
        only what it missed, or None to send :meth:`initial_events` instead.
        """
        return None


def uuid_key(key: str) -> str:
    key = key.lower()
    if not _UUID.match(key):
        raise ProtocolError("unknown_channel", "Unknown channel")
    return key


def number_key(key: str) -> str:
    """A database id that is a whole number (e.g. games)."""
    if not _NUMBER.match(key):
        raise ProtocolError("unknown_channel", "Unknown channel")
    return key


def player_id_key(key: str) -> str:
    if not _PLAYER_ID.match(key):
        raise ProtocolError("unknown_channel", "Unknown channel")
    return key


def only_self(user, key: str) -> None:
    if str(user.player_id) != key:
        raise ProtocolError("forbidden", "Not your channel")


class UserTopic(Topic):
    """``user/<player id>``: your own account (wallet today; items and invites later)."""

    kind = "user"

    def parse_key(self, key):
        return player_id_key(key)

    def authorize(self, user, key):
        only_self(user, key)

    def initial_events(self, user, key):
        from wallet.services import balances

        return [event(Channel(self.kind, key), "balances_changed", {"balances": balances(user)})]


class NotificationsTopic(Topic):
    """``notifications/<player id>``: your inbox. Nothing is sent here until Phase 5."""

    kind = "notifications"

    def parse_key(self, key):
        return player_id_key(key)

    def authorize(self, user, key):
        only_self(user, key)


_TOPICS: dict[str, Topic] = {}


def register(topic: Topic) -> Topic:
    if not _KIND.match(topic.kind):
        raise ValueError(f"bad channel kind {topic.kind!r}")
    if topic.kind in _TOPICS and _TOPICS[topic.kind] is not topic:
        raise ValueError(f"channel kind {topic.kind!r} is already registered")
    _TOPICS[topic.kind] = topic
    return topic


def unregister(kind: str) -> None:
    _TOPICS.pop(kind, None)


def resolve(name: Any) -> tuple[Topic, Channel]:
    """``"room/…"`` → its topic and channel, or ProtocolError('unknown_channel')."""
    if not isinstance(name, str) or name.count("/") != 1 or len(name) > 80:
        raise ProtocolError("unknown_channel", "Unknown channel")
    kind, key = name.split("/")
    topic = _TOPICS.get(kind)
    if topic is None:
        raise ProtocolError("unknown_channel", "Unknown channel")
    return topic, Channel(kind, topic.parse_key(key))


def event(channel: Channel, type: str, data: dict[str, Any], *, version: int | None = None) -> dict[str, Any]:
    """An event on ``channel`` (for a topic's initial events)."""
    return make_event(channel.name, type, data, version=version)


register(UserTopic())
register(NotificationsTopic())
