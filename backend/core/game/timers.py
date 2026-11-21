"""
Server-side turn timer.

Each running game stores ``Game.turn_deadline``, written by game.services in
the same transaction as the game state. A sweep runs every second, finds
overdue turns and:
  - human player: applies the game's "timeout" action (Ludo: auto-roll with
    server dice and the bot's move; after ``rules.max_missed_turns`` misses in
    a row they forfeit)
  - bot player: just lets the bot act. An overdue bot means its thread died,
    and a bot shouldn't be penalised for a server hiccup.

Running several sweeps at once (several server processes) is safe: every
timeout carries the turn number it was meant for, so only one can apply and
the rest are rejected as stale.

Where it runs:
  - Development: inside the ASGI server process (core/asgi.py starts it).
  - Production (optional): GAME_TIMER_IN_PROCESS=false and
    `python manage.py run_turn_timers` as a separate process.
"""

from __future__ import annotations

import logging
import threading
import time
from datetime import datetime

from django.db import close_old_connections
from django.utils import timezone

import game_platform
from events.outbox import dispatch_pending
from items.services import expire_due

from . import connections, rooms, services
from .models import Game, Player

logger = logging.getLogger(__name__)

SWEEP_BATCH_SIZE = 200

_start_lock = threading.Lock()
_started = False


def due_room_codes(now: datetime, limit: int = SWEEP_BATCH_SIZE) -> list[str]:
    return list(
        Game.objects.filter(is_finished=False, turn_deadline__lte=now)
        .exclude(state__isnull=True)
        .order_by("turn_deadline")
        .values_list("room__code", flat=True)[:limit]
    )


def process_due_turns(now: datetime | None = None) -> int:
    """One sweep. Returns how many overdue turns were handled."""
    now = now or timezone.now()
    handled = 0
    for room_code in due_room_codes(now):
        try:
            if _handle_overdue(room_code, now):
                handled += 1
        except Exception:  # one broken game must not stop the timer for everyone
            logger.exception("turn timer failed for room %s", room_code)
    return handled


def _handle_overdue(room_code: str, now: datetime) -> bool:
    game = (
        Game.objects.filter(room__code=room_code)
        .only("state", "turn_deadline", "is_finished", "game_type")
        .first()
    )
    if game is None or game.state is None or game.is_finished:
        return False
    if game.turn_deadline is None or game.turn_deadline > now:
        return False

    game_def = game_platform.get_game(game.game_type)
    info = game_def.info(game_def.load(game.state))
    current = info.current_player_id

    if Player.objects.filter(id=current, is_bot=True).exists():
        services.schedule_bots(room_code)
        return True

    try:
        result = services.perform(
            room_code,
            {"type": "timeout", "turn_number": info.turn_number},
            now=now,
        )
    except (*services.rule_errors(), services.GameConflict, services.TimerNotDue):
        return False  # the player acted just in time, or another sweep got there first
    if result.next_is_bot:
        services.schedule_bots(room_code)
    return True


# How often the sweep looks for seats whose sockets died with an old server.
STALE_CHECK_SECONDS = 15.0


def run_forever(interval: float = 1.0, stop: threading.Event | None = None) -> None:
    stop = stop or threading.Event()
    logger.info("turn timer running every %.1fs", interval)
    try:
        connections.resume_after_restart()  # bot turns lived in the old server's threads
    except Exception:
        logger.exception("resuming bot turns failed")
    last_stale_check = time.monotonic()
    while not stop.is_set():
        close_old_connections()
        try:
            process_due_turns()
            rooms.start_due_rooms()  # start countdowns that ran out
            if time.monotonic() - last_stale_check >= STALE_CHECK_SECONDS:
                last_stale_check = time.monotonic()
                connections.mark_stale()
                dispatch_pending()  # domain events missed after a crash, or failed before
                expire_due()  # time-limited items whose time is up
        except Exception:
            logger.exception("turn timer sweep failed")
        finally:
            close_old_connections()
        stop.wait(interval)


def start_in_background(interval: float = 1.0) -> bool:
    """Start the sweep thread once per process. Returns False if it was already running."""
    global _started
    with _start_lock:
        if _started:
            return False
        _started = True
    threading.Thread(
        target=run_forever, args=(interval,), name="turn-timer", daemon=True
    ).start()
    return True
