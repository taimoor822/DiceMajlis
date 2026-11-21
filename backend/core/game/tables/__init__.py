"""
Tables: the per-game part of the server that the game service calls.

The game service (``game.services``) is the same for every game: lock, load,
engine, save, log, broadcast. What a game needs on top — extra database rows,
the socket messages today's app understands, the extra fields of its
``game_started`` snapshot — lives in its table, picked by ``game_type``.

A game without its own table gets :class:`Table`: no extra rows, and every
engine event goes to the app as it is.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from game_platform import LUDO


class Table:
    def on_start(self, room, state) -> None:
        """Called once, in the start transaction, after the game row exists."""

    def record(self, room, old_state, transition, *, deadline: datetime | None, now: datetime) -> tuple[list[dict], dict[str, Any]]:
        """
        Called in the action's transaction. Returns the socket messages for the
        room and details for the HTTP answer (e.g. Ludo's dice and movable tokens).
        """
        messages = []
        for event in transition.events:
            data = event.to_dict()
            messages.append({
                "type": "game_event",
                "payload": {"type": data["type"], **data["data"], "version": data["version"]},
            })
        return messages, {}

    def snapshot(self, room, game, state) -> dict[str, Any]:
        """Extra fields for the ``game_started`` snapshot (game/state may be None)."""
        return {}


from .ludo import LudoTable  # noqa: E402  (needs Table above)

_TABLES: dict[str, Table] = {LUDO: LudoTable()}
_DEFAULT = Table()


def table_for(game_type: str) -> Table:
    return _TABLES.get(game_type, _DEFAULT)
