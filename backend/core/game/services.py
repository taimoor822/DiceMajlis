"""
Runs live games. This is the ONLY module that changes game state: views, the
socket consumer, the turn timer and the bot loop all call into it.

It works for any game in the ``game_platform`` registry: the room's
``game_type`` picks the engine, and the game's table (``game.tables``) adds
what that game needs on top (for Ludo: Token rows and the socket messages
today's app understands).

Each action runs in one DB transaction:
    lock game → load engine state → server randomness (dice) → engine → save new
    state (only if nobody else saved first) → log action → the game's table
and the resulting messages are broadcast after the transaction commits.
"""

from __future__ import annotations

import logging
import math
import random
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.conf import settings
from django.db import close_old_connections, transaction
from django.utils import timezone

import game_platform
from game_platform import PlatformError, SecureRandom, TurnInfo
from ludo_engine.board import SEAT_COLORS

from realtime.publish import publish

from .models import Game, GameAction, Player, Room
from .tables import table_for

logger = logging.getLogger(__name__)

# Seats are handed out by colour (TODO 1.13 rooms v2: seats per game type).
COLOR_BY_SEAT = SEAT_COLORS  # ("red", "blue", "green", "yellow")
SEAT_BY_COLOR = {"red": 0, "blue": 1, "green": 2, "yellow": 3, "orange": 3, "amber": 3}

# Seats handed out as people join: the second player sits opposite the host,
# like the engine's default two-player game.
JOIN_SEAT_ORDER = (0, 2, 1, 3)

MAX_BOT_ACTIONS_PER_RUN = 500

# Every server-side random choice (dice, later shuffled tiles). Tests swap it
# for game_platform.ScriptedRandom.
SERVER_RANDOM = SecureRandom()


class GameConflict(Exception):
    """Another request changed the game first. The client should resync and retry."""

    code = "stale_version"


class TimerNotDue(Exception):
    """A timeout was requested before the turn's deadline (e.g. a racing timer sweep)."""

    code = "timer_not_due"


class LegacyGame(Exception):
    """Game was started before the engine existed; its positions use the old 0..100 scale."""

    code = "legacy_game"


@dataclass(frozen=True)
class ActionResult:
    state: Any  # the engine's new state
    events: tuple[Any, ...]
    info: TurnInfo
    next_is_bot: bool
    # From the game's table, for the HTTP answer (Ludo: dice, movable_token_ids).
    details: dict[str, Any]


def rule_errors() -> tuple[type[Exception], ...]:
    """Errors an action can be refused with: every engine's rules, plus the platform's."""
    return game_platform.rule_errors() + (PlatformError,)


# ---------------------------------------------------------------------------
# Seats
# ---------------------------------------------------------------------------


def preferred_seat(color: str) -> int | None:
    return SEAT_BY_COLOR.get((color or "").strip().lower())


def assign_seats(players: list[Player]) -> dict[str, int]:
    """
    Players keep the seat of their colour when it is free (earlier joiners win).
    Everyone else gets the next free seat. The app hard-codes red for the host
    and blue for every joiner today, so this is what stops colour clashes.
    """
    if len(players) > len(COLOR_BY_SEAT):
        raise ValueError("more players than seats")
    seats: dict[str, int] = {}
    taken: set[int] = set()
    pending: list[Player] = []
    for player in players:
        seat = preferred_seat(player.color)
        if seat is not None and seat not in taken:
            seats[str(player.id)] = seat
            taken.add(seat)
        else:
            pending.append(player)
    free = [s for s in range(len(COLOR_BY_SEAT)) if s not in taken]
    for player, seat in zip(pending, free):
        seats[str(player.id)] = seat
    return seats


def color_for_new_player(room: Room, requested: str | None = None) -> str:
    """
    Colour (= seat) for someone joining ``room``: the one they asked for if it
    is free, otherwise the next free seat. Call with the room row locked.
    """
    taken = {preferred_seat(c) for c in room.players.values_list("color", flat=True)}
    seat = preferred_seat(requested or "")
    if seat is None or seat in taken:
        seat = next((s for s in JOIN_SEAT_ORDER if s not in taken), None)
    if seat is None:
        raise ValueError("no free seat")
    return COLOR_BY_SEAT[seat]


def bot_seat_for(used_seats: set[int], host_seat: int) -> int:
    """Classic 2-player Ludo: the bot sits opposite the host when it can."""
    for offset in (2, 1, 3):
        seat = (host_seat + offset) % len(COLOR_BY_SEAT)
        if seat not in used_seats:
            return seat
    raise ValueError("no free seat for a bot")


# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------


def start_game(room: Room, host: Player) -> tuple[Game, Any]:
    """Create the room's game on its engine and seat everyone. Call inside a transaction."""
    game_def = game_platform.get_game(room.game_type)
    players = list(room.players.order_by("joined_at"))
    seats = assign_seats(players)
    for player in players:
        seat = seats[str(player.id)]
        if preferred_seat(player.color) != seat:
            # Colour decides the board path in the app, so it must match the seat.
            player.color = COLOR_BY_SEAT[seat]
            player.save(update_fields=["color"])

    state = game_def.new_game(
        str(room.id),
        [str(p.id) for p in players],
        variant=room.variant,
        seats=[seats[str(p.id)] for p in players],
        first_player_id=str(host.id),
    )
    snapshot = game_def.dump(state)
    info = game_def.info(state)
    game = Game.objects.create(
        room=room,
        game_type=room.game_type,
        variant=room.variant,
        current_turn=host,
        state=snapshot,
        initial_state=snapshot,
        version=info.version,
        turn_deadline=_deadline(info, timezone.now()),
    )
    table_for(room.game_type).on_start(room, state)
    return game, state


# ---------------------------------------------------------------------------
# Seats held by accounts
# ---------------------------------------------------------------------------


def seats_of(user, *, exclude_room: Room | None = None) -> list[Player]:
    """``user``'s seats in rooms that are not over yet, newest first."""
    seats = (
        Player.objects.filter(user=user, is_bot=False)
        .exclude(room__game__is_finished=True)
        .select_related("room")
        .order_by("-joined_at")
    )
    if exclude_room is not None:
        seats = seats.exclude(room=exclude_room)
    return list(seats)


def seat_in_play(player: Player) -> bool:
    """
    Whether ``player`` still has something to come back to: a room that has not
    started, or a running game they have not finished, left or timed out of.
    """
    room = player.room
    if not room.is_started:
        return True
    game = Game.objects.filter(room=room).only("state", "is_finished", "game_type").first()
    if game is None or game.is_finished or game.state is None:
        return False
    try:
        game_def = game_platform.get_game(game.game_type)
        info = game_def.info(game_def.load(game.state))
    except rule_errors():
        return False
    return str(player.id) in info.active_player_ids


def active_seat_for(user) -> dict[str, Any] | None:
    """The room ``user`` goes back to when the app opens (session restore), or None."""
    for seat in seats_of(user):
        if seat_in_play(seat):
            room = seat.room
            return {
                "code": room.code,
                "room_id": str(room.id),
                "seat_id": str(seat.id),
                "is_host": seat.is_host,
                "max_players": room.max_players,
                "started": room.is_started,
                "game_type": room.game_type,
                "variant": room.variant,
            }
    return None


def game_in_progress_for(user, *, exclude_room: Room | None = None) -> Room | None:
    """A started game ``user`` is still playing (one game at a time), or None."""
    for seat in seats_of(user, exclude_room=exclude_room):
        if seat.room.is_started and seat_in_play(seat):
            return seat.room
    return None


def leave_waiting_rooms(user, *, keep: Room | None = None) -> None:
    """Free ``user``'s seats in rooms that have not started (except ``keep``)."""
    for seat in seats_of(user, exclude_room=keep):
        if not seat.room.is_started:
            leave_room(seat, forfeit=False)


def leave_room(player: Player, *, forfeit: bool = True) -> None:
    """
    The account at ``player`` leaves its room.

    Room not started: the seat is freed, the host role passes to the next
    person, and a room with nobody left closes. Game started: they forfeit
    (through perform(), like every game change) unless ``forfeit`` is False.
    Already out of the game, or the game is over: nothing to do.
    """
    with transaction.atomic():
        room = Room.objects.select_for_update().filter(pk=player.room_id).first()
        if room is None:
            return
        started = room.is_started
        closed = False if started else _free_seat(room, player)
    if not started:
        if not closed:
            broadcast_players(room)
        return
    if not forfeit:
        return

    action = {"type": "forfeit", "player_id": str(player.id), "reason": "left"}
    for attempt in range(3):
        try:
            result = perform(room.code, action)
        except GameConflict:
            if attempt == 2:
                raise
            continue
        except (*rule_errors(), LegacyGame, Game.DoesNotExist):
            return  # already out, or the game is over
        if result.next_is_bot:
            schedule_bots(room.code)
        return


def _free_seat(room: Room, player: Player) -> bool:
    """Remove a seat from a room that has not started. True if the room closed."""
    was_host = player.is_host
    Player.objects.filter(pk=player.pk).delete()
    successor = room.players.filter(is_bot=False).order_by("joined_at").first()
    if successor is None:
        room.delete()
        return True
    if was_host:
        Player.objects.filter(pk=successor.pk).update(is_host=True)
    return False


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------


def _deadline(info: TurnInfo, now: datetime) -> datetime | None:
    """When the current turn runs out, or None (game over, or a game without a timer)."""
    if info.finished or not info.turn_seconds:
        return None
    return now + timedelta(seconds=info.turn_seconds)


def seconds_left(deadline: datetime | None, now: datetime | None = None) -> int | None:
    """Whole seconds until ``deadline`` (never negative), or None when there is no timer."""
    if deadline is None:
        return None
    remaining = (deadline - (now or timezone.now())).total_seconds()
    return max(0, math.ceil(remaining))


def perform(
    room_code: str,
    action: dict[str, Any],
    *,
    now: datetime | None = None,
    expected_version: int | None = None,
) -> ActionResult:
    """
    Apply one action, in the engine's own action format. The engine fills in
    the server's part first (``prepare_action``): for Ludo a "roll" gets the
    server's dice, a "bot" action becomes the bot's roll or move, and a
    "timeout" gets dice when a roll is due.
    Raises the engine's rule errors, PlatformError, GameConflict, LegacyGame,
    TimerNotDue, Room.DoesNotExist / Game.DoesNotExist.
    """
    now = now or timezone.now()
    with transaction.atomic():
        room = Room.objects.select_for_update().get(code=room_code)
        game = Game.objects.select_for_update().get(room=room)
        if game.state is None:
            raise LegacyGame("this game was started before the rules update")

        game_def = game_platform.get_game(game.game_type)
        state = game_def.load(game.state)
        if game_def.info(state).version != game.version:
            raise GameConflict("stored state and version disagree")
        if expected_version is not None and expected_version != game.version:
            # The player acted on an older picture of the game: they resync first.
            raise GameConflict(f"the game is at version {game.version}, not {expected_version}")
        if action.get("type") == "timeout" and (
            game.turn_deadline is None or game.turn_deadline > now
        ):
            raise TimerNotDue("this turn has not run out yet")

        resolved = game_def.prepare_action(state, action, SERVER_RANDOM)
        transition = game_def.apply_action(state, resolved)
        new_state = transition.state
        info = game_def.info(new_state)
        old_info = game_def.info(state)

        if info.finished:
            deadline = None
        elif info.turn_number != old_info.turn_number:
            deadline = _deadline(info, now)  # a new turn gets a fresh clock
        else:
            deadline = game.turn_deadline  # same turn (roll -> move): clock keeps running

        # Optimistic check: only save if nobody saved a newer version meanwhile.
        # (SQLite ignores SELECT ... FOR UPDATE, so this is the real guard there.)
        saved = Game.objects.filter(pk=game.pk, version=game.version).update(
            state=game_def.dump(new_state),
            version=info.version,
            current_turn_id=info.current_player_id,
            is_finished=info.finished,
            turn_deadline=deadline,
        )
        if saved != 1:
            raise GameConflict("the game changed while this action was running")

        GameAction.objects.create(game=game, version=info.version, action=resolved)
        messages, details = table_for(game.game_type).record(
            room, state, transition, deadline=deadline, now=now
        )
        next_is_bot = (
            not info.finished
            and Player.objects.filter(id=info.current_player_id, is_bot=True).exists()
        )

    broadcast(room_code, messages)
    return ActionResult(new_state, tuple(transition.events), info, next_is_bot, details)


# ---------------------------------------------------------------------------
# Snapshots (read only)
# ---------------------------------------------------------------------------


def players_payload(room: Room) -> list[dict[str, Any]]:
    return [
        {
            "id": str(p.id),
            "name": p.name,
            "color": p.color,
            "is_host": p.is_host,
            "is_bot": p.is_bot,
        }
        for p in room.players.order_by("joined_at")
    ]


def game_snapshot(room: Room) -> dict[str, Any]:
    """
    Everything the app needs to draw a started game from scratch: sent when the
    game starts and to anyone who (re)connects. Same shape as the
    ``game_started`` socket message; the game's table adds its own fields.
    """
    snapshot: dict[str, Any] = {
        "type": "game_started",
        "room_code": room.code,
        "room_id": str(room.id),
        "game_type": room.game_type,
        "variant": room.variant,
        "game_id": None,
        "players": players_payload(room),
        "current_turn_player_id": None,
        "version": None,
        "seconds_left": None,
        "warning_seconds": None,
        "winner_id": None,
    }
    game = Game.objects.filter(room=room).first()
    state = None
    if game is not None:
        snapshot.update(
            game_id=str(game.id),
            current_turn_player_id=str(game.current_turn_id) if game.current_turn_id else None,
            version=game.version,
            seconds_left=seconds_left(game.turn_deadline),
        )
        if game.state is not None:
            game_def = game_platform.get_game(game.game_type)
            state = game_def.load(game.state)
            info = game_def.info(state)
            snapshot.update(warning_seconds=info.warning_seconds, winner_id=info.winner_id)
    snapshot.update(table_for(room.game_type).snapshot(room, game, state))
    return snapshot


# ---------------------------------------------------------------------------
# Socket messages (each game's table writes them; see game.tables)
# ---------------------------------------------------------------------------


def group_name(room_code: str) -> str:
    return f"lobby_{room_code}"


def broadcast_players(room: Room) -> None:
    """Tell everyone watching ``room`` who is seated now."""
    broadcast(room.code, [{"type": "players_updated", "players": players_payload(room)}])


def broadcast(room_code: str, messages: list[dict]) -> None:
    """
    Send room/game messages, after the change is saved. They go to the legacy
    lobby socket (``/ws/lobby/<code>/``, today's app) and to the ``/ws/v1/``
    channels ``room/<room id>`` and ``game/<game id>`` (game.topics).
    """
    if not messages:
        return
    layer = get_channel_layer()
    if layer is None:
        return
    send = async_to_sync(layer.group_send)
    for message in messages:
        send(group_name(room_code), message)
    _publish_v1(room_code, messages)


def _publish_v1(room_code: str, messages: list[dict]) -> None:
    room = Room.objects.filter(code=room_code).only("id").first()
    if room is None:
        return
    game_id = Game.objects.filter(room=room).values_list("id", flat=True).first()
    for message in messages:
        kind = message["type"]
        if kind == "game_event" and game_id is not None:
            data = dict(message["payload"])
            event_type = data.pop("type")
            version = data.pop("version", None)
            publish(f"game/{game_id}", event_type, data, version=version)
        elif kind == "players_updated":
            publish(f"room/{room.id}", "players_updated", {"players": message["players"]})
        elif kind == "game_started":
            data = {k: v for k, v in message.items() if k != "type"}
            publish(f"room/{room.id}", "game_started", data, version=data.get("version"))


# ---------------------------------------------------------------------------
# Bots
# ---------------------------------------------------------------------------

_BOT_LOCK = threading.Lock()
_BOT_ROOMS: set[str] = set()


def schedule_bots(room_code: str) -> None:
    """Let bots play while it is their turn. Background thread (inline in tests)."""
    if getattr(settings, "GAME_BOTS_INLINE", False):
        _run_bots(room_code)
        return
    with _BOT_LOCK:
        if room_code in _BOT_ROOMS:
            return
        _BOT_ROOMS.add(room_code)
    threading.Thread(target=_run_bots_in_thread, args=(room_code,), daemon=True).start()


def _run_bots_in_thread(room_code: str) -> None:
    close_old_connections()
    try:
        _run_bots(room_code)
    except Exception:  # never let a bot crash take the server thread down silently
        logger.exception("bot loop failed in room %s", room_code)
    finally:
        with _BOT_LOCK:
            _BOT_ROOMS.discard(room_code)
        close_old_connections()


def _run_bots(room_code: str) -> None:
    conflicts = 0
    for _ in range(MAX_BOT_ACTIONS_PER_RUN):
        game = (
            Game.objects.filter(room__code=room_code)
            .only("state", "is_finished", "game_type")
            .first()
        )
        if game is None or game.state is None or game.is_finished:
            return
        game_def = game_platform.get_game(game.game_type)
        bot_id = game_def.info(game_def.load(game.state)).current_player_id
        if not Player.objects.filter(id=bot_id, is_bot=True).exists():
            return

        _bot_pause()
        try:
            # The engine picks the bot's roll or move inside the action's lock.
            perform(room_code, {"type": "bot", "player_id": bot_id})
            conflicts = 0
        except GameConflict:
            conflicts += 1
            if conflicts > 3:
                return
        except rule_errors():
            return  # someone else acted first; the next action will reschedule us


def _bot_pause() -> None:
    low, high = getattr(settings, "GAME_BOT_DELAY_SECONDS", (0.6, 1.2))
    if high > 0:
        time.sleep(random.uniform(low, high))
