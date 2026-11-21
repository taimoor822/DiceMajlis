"""
Players who drop and come back (step 1.14, PLATFORM.md §5 "Disconnect and
reconnect").

- The seat is kept. When an account's last socket goes, its seats in rooms
  that are on get ``disconnected_at`` and everyone hears ``player_disconnected``;
  when it is back, ``player_reconnected``. The turn timer keeps running for
  them meanwhile (missed turns are auto-played; three in a row forfeit).
- Coming back, the app re-subscribes with the last version it saw and gets
  ``state_delta`` (what it missed, from ``GameAction.messages``) or the whole
  state (``game/topics.py``); the ``sync`` request does the same on demand.
- A server restart loses nothing: games, actions and rooms are in the database;
  :func:`resume_after_restart` restarts bot turns and the sweep catches seats
  whose sockets died with the old server (:func:`mark_stale`).
"""

from __future__ import annotations

import logging
from datetime import datetime

from django.utils import timezone

from realtime import presence

from . import services
from .models import Game, Player, Room

logger = logging.getLogger(__name__)

Status = Room.Status
# Rooms where being away matters to the others.
LIVE = (Status.WAITING, Status.READY, Status.STARTING, Status.PLAYING)


def _live_seats(**filters):
    return Player.objects.filter(
        is_bot=False, has_left=False, room__status__in=LIVE, **filters
    ).select_related("room")


def on_presence(user_id, online: bool, *, now: datetime | None = None) -> None:
    """The presence listener: an account came online or went offline."""
    now = now or timezone.now()
    for seat in _live_seats(user_id=user_id):
        _mark(seat, online, now)


def _mark(seat: Player, online: bool, now: datetime) -> None:
    if online:
        changed = Player.objects.filter(pk=seat.pk, disconnected_at__isnull=False).update(
            disconnected_at=None
        )
    else:
        changed = Player.objects.filter(pk=seat.pk, disconnected_at__isnull=True).update(
            disconnected_at=now
        )
    if not changed:
        return
    kind = "player_reconnected" if online else "player_disconnected"
    services.broadcast(seat.room.code, [
        {"type": kind, "player_id": str(seat.id)},
        {"type": "players_updated", "players": services.players_payload(seat.room)},
    ])


def mark_stale(now: datetime | None = None) -> int:
    """
    Seats shown as connected whose account has no live socket (its server
    died without saying goodbye): mark them away. Run by the timer sweep.
    """
    now = now or timezone.now()
    seats = list(_live_seats(disconnected_at__isnull=True, user__isnull=False))
    if not seats:
        return 0
    online = presence.online({seat.user_id for seat in seats})
    marked = 0
    for seat in seats:
        if str(seat.user_id) not in online:
            _mark(seat, False, now)
            marked += 1
    return marked


def resume_after_restart() -> int:
    """
    Bot turns lived in the old server's threads: start them again for every
    game waiting on a bot. Called once when the timer sweep starts.
    """
    codes = list(
        Game.objects.filter(is_finished=False, state__isnull=False, current_turn__is_bot=True)
        .values_list("room__code", flat=True)
    )
    for code in codes:
        services.schedule_bots(code)
    if codes:
        logger.info("resumed bot turns in %d game(s)", len(codes))
    return len(codes)
