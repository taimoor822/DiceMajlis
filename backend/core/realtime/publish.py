"""
Push an event to everyone subscribed to a channel. Call it from synchronous
server code (views, services, ``transaction.on_commit``), after the change is
saved: what was sent must never be rolled back.

    publish("user/112156630", "balances_changed", {"balances": {...}})
    publish(f"game/{game.id}", "token_moved", {...}, version=42)
"""

from __future__ import annotations

import logging
from typing import Any

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from . import topics
from .protocol import event

logger = logging.getLogger(__name__)

# The Channels message type; consumers handle it in ``realtime_event``.
MESSAGE_TYPE = "realtime.event"


def publish(channel: str, type: str, data: dict[str, Any], *, version: int | None = None) -> None:
    """
    Send ``type`` + ``data`` on ``channel``. A failure is logged, never raised: the
    change it reports is already saved, and the app resyncs from a snapshot.
    """
    try:
        _topic, resolved = topics.resolve(channel)
        layer = get_channel_layer()
        if layer is None:
            return
        async_to_sync(layer.group_send)(
            resolved.group,
            {"type": MESSAGE_TYPE, "event": event(resolved.name, type, data, version=version)},
        )
    except Exception:
        logger.exception("could not publish %s on %s", type, channel)
