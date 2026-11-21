"""
Private rooms v2 (PLATFORM.md §5): the ready system, host controls, invites,
custom rules, the start countdown and rematches.

    WAITING ⇄ READY ──host starts──► STARTING (countdown) ──► PLAYING ──► FINISHED
                                                                         │    │
                                     rematch: a new room, same people ◄──┘    ▼
                                                                           CLOSED

- READY means every guest is ready (the host always is), so a host alone may
  start: the Majlis AI joins as before.
- Changing the rules or a new guest makes the room WAITING again; so does a
  guest who stops being ready, even during the countdown.
- Locked rooms take only invited people; kicked people can't come back unless
  the host invites them again.
- The rematch is played in a new room with the same people and colours (the old
  room closes and points to it), so every game keeps its own history.

Nothing here knows which game the room plays: the variant and its options come
from the game_platform registry. Every change is broadcast on ``room/<id>`` as
``players_updated`` + ``room_updated`` (after the change is committed).
"""

from __future__ import annotations

import logging
import secrets
import string
from datetime import datetime, timedelta
from typing import Any

from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

import game_platform
from accounts.models import User
from realtime.publish import publish

from . import services
from .models import Player, Room, RoomInvite

logger = logging.getLogger(__name__)

Status = Room.Status
BEFORE_START = (Status.WAITING, Status.READY, Status.STARTING)
CAN_JOIN = (Status.WAITING, Status.READY)

ROOM_CODE_LENGTH = 4
ROOM_CODE_ALPHABET = string.ascii_uppercase + string.digits


class RoomError(Exception):
    """A room request refused. ``code`` is sent to the app."""

    def __init__(self, code: str, message: str = ""):
        super().__init__(message or code)
        self.code = code
        self.message = message or code


def countdown_seconds() -> int:
    return int(getattr(settings, "GAME_START_COUNTDOWN_SECONDS", 3))


def new_room_code() -> str:
    """A room code nobody uses (call inside a transaction)."""
    while True:
        code = "".join(secrets.choice(ROOM_CODE_ALPHABET) for _ in range(ROOM_CODE_LENGTH))
        if not Room.objects.filter(code=code).exists():
            return code


# ---------------------------------------------------------------------------
# What the app sees
# ---------------------------------------------------------------------------


def room_options(room: Room) -> dict[str, Any]:
    """The room's rules choices, every option filled in (defaults where unset)."""
    variant = game_platform.get_variant(room.game_type, room.variant)
    try:
        return variant.check_options(room.options)
    except game_platform.InvalidOption:
        return variant.check_options(None)


def room_info(room: Room, now: datetime | None = None) -> dict[str, Any]:
    """The ``room_updated`` message (and part of the waiting room's first state)."""
    host = room.players.filter(is_host=True).first()
    next_room = room.next_room
    return {
        "room_id": str(room.id),
        "code": room.code,
        "status": room.status,
        "is_locked": room.is_locked,
        "game_type": room.game_type,
        "variant": room.variant,
        "max_players": room.max_players,
        "options": room_options(room),
        # What the host may pick (the app shows these; it never knows the rules).
        "option_choices": [
            option.to_dict()
            for option in game_platform.get_variant(room.game_type, room.variant).options
        ],
        "host_id": str(host.id) if host else None,
        "starts_in": (
            services.seconds_left(room.starts_at, now) if room.status == Status.STARTING else None
        ),
        "next_room": (
            {"code": next_room.code, "room_id": str(next_room.id)} if next_room else None
        ),
    }


def broadcast_room(room: Room | str) -> None:
    """Tell everyone in the room who is seated and how the room stands."""
    room = Room.objects.filter(code=room).first() if isinstance(room, str) else room
    if room is None:
        return
    room.refresh_from_db()
    services.broadcast(room.code, [
        {"type": "players_updated", "players": services.players_payload(room)},
        {"type": "room_updated", **room_info(room)},
    ])


def invite_payload(invite: RoomInvite) -> dict[str, Any]:
    room = invite.room
    return {
        "room_code": room.code,
        "room_id": str(room.id),
        "game_type": room.game_type,
        "variant": room.variant,
        "from": {"name": invite.from_user.public_name, "player_id": invite.from_user.player_id},
        "invited_at": invite.created_at.isoformat(),
    }


def pending_invites(user) -> list[dict[str, Any]]:
    """Invites to rooms that can still be joined, newest first."""
    invites = (
        RoomInvite.objects.filter(to_user=user, room__status__in=CAN_JOIN)
        .exclude(room__players__user=user)
        .select_related("room", "from_user")
        .order_by("-created_at")
    )
    return [invite_payload(invite) for invite in invites]


# ---------------------------------------------------------------------------
# Helpers (inside a transaction)
# ---------------------------------------------------------------------------


def _locked_room(code: str) -> Room:
    room = Room.objects.select_for_update().filter(code=str(code).strip().upper()).first()
    if room is None:
        raise RoomError("room_not_found", "No such room")
    return room


def _seat(room: Room, user) -> Player:
    seat = room.players.filter(user=user, is_bot=False, has_left=False).first()
    if seat is None:
        raise RoomError("not_in_room", "You are not in this room")
    return seat


def _host(room: Room, user) -> Player:
    seat = _seat(room, user)
    if not seat.is_host:
        raise RoomError("not_host", "Only the host can do that")
    return seat


def _before_start(room: Room) -> None:
    if room.status not in BEFORE_START:
        raise RoomError("game_already_started", "The game has started")


def _not_counting_down(room: Room) -> None:
    if room.status == Status.STARTING:
        raise RoomError("game_starting", "The game is starting")


def settle(room: Room) -> None:
    """
    WAITING or READY from the ready flags (call after any change before the
    start). A running countdown stops when someone is no longer ready.
    """
    if room.status not in BEFORE_START:
        return
    not_ready = room.players.filter(is_bot=False, is_host=False, is_ready=False).exists()
    if room.status == Status.STARTING and not not_ready:
        return  # the countdown goes on
    room.status = Status.WAITING if not_ready else Status.READY
    room.starts_at = None
    room.save(update_fields=["status", "starts_at"])


def _player(room: Room, player_id: Any) -> Player:
    try:
        seat = room.players.filter(id=str(player_id)).first()
    except Exception:  # not a UUID
        seat = None
    if seat is None:
        raise RoomError("player_not_found", "No such player in this room")
    return seat


# ---------------------------------------------------------------------------
# Ready, host controls, rules
# ---------------------------------------------------------------------------


def set_ready(user, code: str, ready: bool) -> None:
    with transaction.atomic():
        room = _locked_room(code)
        seat = _seat(room, user)
        _before_start(room)
        if seat.is_host:
            raise RoomError("host_always_ready", "The host starts the game")
        seat.is_ready = bool(ready)
        seat.save(update_fields=["is_ready"])
        settle(room)
    broadcast_room(room)


def kick(user, code: str, player_id: Any) -> None:
    with transaction.atomic():
        room = _locked_room(code)
        host = _host(room, user)
        _before_start(room)
        target = _player(room, player_id)
        if target.pk == host.pk:
            raise RoomError("cannot_kick_yourself", "You can't remove yourself")
        if target.user_id is not None:
            room.kicked_users.add(target.user_id)
            RoomInvite.objects.filter(room=room, to_user_id=target.user_id).delete()
        kicked_id = str(target.id)
        target.delete()
        settle(room)
    services.broadcast(room.code, [{"type": "player_kicked", "player_id": kicked_id}])
    broadcast_room(room)


def set_locked(user, code: str, locked: bool) -> None:
    with transaction.atomic():
        room = _locked_room(code)
        _host(room, user)
        _before_start(room)
        room.is_locked = bool(locked)
        room.save(update_fields=["is_locked"])
    broadcast_room(room)


def transfer_host(user, code: str, player_id: Any) -> None:
    with transaction.atomic():
        room = _locked_room(code)
        host = _host(room, user)
        if room.status == Status.CLOSED:
            raise RoomError("room_closed", "This room is closed")
        target = _player(room, player_id)
        if target.is_bot or target.has_left:
            raise RoomError("player_not_found", "They can't host this room")
        if target.pk == host.pk:
            return
        Player.objects.filter(pk=host.pk).update(is_host=False, is_ready=False)
        Player.objects.filter(pk=target.pk).update(is_host=True, is_ready=True)
        settle(room)
    broadcast_room(room)


def change_settings(user, code: str, *, variant: str | None = None, options: dict | None = None) -> None:
    """The host picks the variant and custom rules. Guests have to get ready again."""
    with transaction.atomic():
        room = _locked_room(code)
        _host(room, user)
        _before_start(room)
        _not_counting_down(room)
        try:
            chosen = game_platform.get_variant(room.game_type, variant or room.variant)
            if options is None:
                options = room.options if chosen.code == room.variant else {}
            checked = chosen.check_options(options)
        except game_platform.PlatformError as exc:
            raise RoomError(exc.code, str(exc))
        if room.max_players > chosen.max_players or room.max_players < chosen.min_players:
            raise RoomError("wrong_player_count", "This variant needs a different number of players")
        room.variant = chosen.code
        room.options = checked
        room.save(update_fields=["variant", "options"])
        room.players.filter(is_host=False).update(is_ready=False)
        settle(room)
    broadcast_room(room)


# ---------------------------------------------------------------------------
# Invites
# ---------------------------------------------------------------------------


def invite(user, code: str, player_number: Any) -> None:
    """Invite an account by its 9-digit Player ID; it hears about it on ``user/<id>``."""
    try:
        number = int(str(player_number).replace(" ", ""))
    except ValueError:
        raise RoomError("player_not_found", "No player with that ID")
    with transaction.atomic():
        room = _locked_room(code)
        seat = _seat(room, user)
        if room.status not in CAN_JOIN:
            raise RoomError("game_already_started", "The game has started")
        target = User.objects.filter(player_id=number).first()
        if target is None:
            raise RoomError("player_not_found", "No player with that ID")
        if target.pk == user.pk:
            raise RoomError("cannot_invite_yourself", "That's you")
        if room.players.filter(user=target).exists():
            raise RoomError("already_in_room", "They are already in this room")
        if room.is_locked and not seat.is_host:
            raise RoomError("not_host", "Only the host invites to a locked room")
        if room.kicked_users.filter(pk=target.pk).exists():
            if not seat.is_host:
                raise RoomError("player_kicked", "The host removed them from this room")
            room.kicked_users.remove(target)  # the host changed their mind
        RoomInvite.objects.filter(room=room, to_user=target).delete()
        sent = RoomInvite.objects.create(room=room, from_user=user, to_user=target)
        payload = invite_payload(sent)
        channel = f"user/{target.player_id}"
    transaction.on_commit(lambda: publish(channel, "room_invite", payload))


def decline_invite(user, code: str) -> None:
    RoomInvite.objects.filter(to_user=user, room__code=str(code).strip().upper()).delete()


def check_can_join(room: Room, user) -> None:
    """For join-room (inside its transaction): status, kicks and the lock."""
    if room.status == Status.STARTING:
        raise RoomError("game_starting", "The game is starting")
    if room.status not in CAN_JOIN:
        raise RoomError("game_already_started", "The game has started")
    if room.kicked_users.filter(pk=user.pk).exists():
        raise RoomError("player_kicked", "The host removed you from this room")
    if room.is_locked and not RoomInvite.objects.filter(room=room, to_user=user).exists():
        raise RoomError("room_locked", "This room takes invited players only")


# ---------------------------------------------------------------------------
# Starting
# ---------------------------------------------------------------------------


def request_start(user, code: str, *, now: datetime | None = None) -> str:
    """
    The host starts: a countdown (``GAME_START_COUNTDOWN_SECONDS``), then the
    game. Returns "starting", or "started" when there is no countdown.
    """
    now = now or timezone.now()
    snapshot = None
    with transaction.atomic():
        room = _locked_room(code)
        _host(room, user)
        if room.status == Status.STARTING:
            return "starting"
        _before_start(room)
        if room.status != Status.READY:
            raise RoomError("not_everyone_ready", "Everyone has to be ready")
        seconds = countdown_seconds()
        if seconds > 0:
            room.status = Status.STARTING
            room.starts_at = now + timedelta(seconds=seconds)
            room.save(update_fields=["status", "starts_at"])
        else:
            snapshot = _begin(room)
    if snapshot is not None:
        services.broadcast(room.code, [snapshot])
    broadcast_room(room)
    return "started" if snapshot is not None else "starting"


def _begin(room: Room) -> dict[str, Any]:
    """Start the game now (inside the caller's transaction). Returns the snapshot."""
    host = room.players.filter(is_host=True).first()
    if host is None:
        raise RoomError("not_host", "The room has no host")
    # Alone: the Majlis AI joins, sitting opposite the host.
    if (
        room.players.filter(is_bot=False).count() == 1
        and not room.players.filter(is_bot=True).exists()
    ):
        seats = services.assign_seats(list(room.players.order_by("joined_at")))
        ai_seat = services.bot_seat_for(set(seats.values()), seats[str(host.id)])
        Player.objects.create(
            room=room,
            name="Majlis AI",
            color=services.COLOR_BY_SEAT[ai_seat],
            is_bot=True,
            is_ready=True,
        )
    room.is_started = True
    room.status = Status.PLAYING
    room.starts_at = None
    room.save(update_fields=["is_started", "status", "starts_at"])
    try:
        services.start_game(room, host)
    except (*services.rule_errors(), game_platform.PlatformError) as exc:
        raise RoomError(getattr(exc, "code", "invalid_setup"), str(exc))
    RoomInvite.objects.filter(room=room).delete()
    return services.game_snapshot(room)


def start_due_rooms(now: datetime | None = None) -> int:
    """Start every room whose countdown has run out (the timer sweep calls this)."""
    now = now or timezone.now()
    codes = list(
        Room.objects.filter(status=Status.STARTING, starts_at__lte=now)
        .order_by("starts_at")
        .values_list("code", flat=True)[:200]
    )
    started = 0
    for code in codes:
        try:
            started += _start_now(code, now)
        except Exception:
            logger.exception("starting room %s failed", code)
    return started


def _start_now(code: str, now: datetime) -> int:
    snapshot = None
    with transaction.atomic():
        room = Room.objects.select_for_update().filter(code=code).first()
        if room is None or room.status != Status.STARTING or room.starts_at > now:
            return 0
        try:
            with transaction.atomic():
                snapshot = _begin(room)
        except RoomError:
            logger.warning("room %s could not start; back to waiting", code)
            room.refresh_from_db()
            room.status = Status.WAITING
            room.starts_at = None
            room.save(update_fields=["status", "starts_at"])
            settle(room)
    if snapshot is not None:
        services.broadcast(room.code, [snapshot])
        services.schedule_bots(room.code)
    broadcast_room(room)
    return 1 if snapshot is not None else 0


# ---------------------------------------------------------------------------
# After the game: rematch, closing
# ---------------------------------------------------------------------------


def vote_rematch(user, code: str, want: bool, *, now: datetime | None = None) -> dict[str, Any]:
    """
    Ask (or stop asking) to play again. When everyone still in the room asks,
    the rematch room is made and ``rematch_started`` tells everyone where.
    Returns the new room once there is one.
    """
    now = now or timezone.now()
    with transaction.atomic():
        room = _locked_room(code)
        seat = _seat(room, user)
        if room.status == Status.CLOSED and room.next_room_id:
            return _next_room_answer(room, seat)
        if room.status != Status.FINISHED:
            raise RoomError("game_not_finished", "The game isn't over")
        seat.wants_rematch = bool(want)
        seat.save(update_fields=["wants_rematch"])
        made = _maybe_rematch(room, now)
    _announce(room, made)
    room.refresh_from_db()
    return _next_room_answer(room, seat) if room.next_room_id else {"next_room": None}


def _next_room_answer(room: Room, seat: Player) -> dict[str, Any]:
    new_room = room.next_room
    new_seat = new_room.players.filter(user_id=seat.user_id).first() if new_room else None
    return {
        "next_room": {"code": new_room.code, "room_id": str(new_room.id)} if new_room else None,
        "seat_id": str(new_seat.id) if new_seat else None,
    }


def after_leave(code: str) -> None:
    """Someone left a started room: in a finished one the rest may rematch, or it closes."""
    made = None
    with transaction.atomic():
        room = Room.objects.select_for_update().filter(code=code).first()
        if room is None:
            return
        if room.status == Status.FINISHED:
            made = _maybe_rematch(room, timezone.now())
    _announce(room, made)


def on_game_finished(room_code: str) -> None:
    """The game service calls this once a game is over (after it committed)."""
    with transaction.atomic():
        room = Room.objects.select_for_update().filter(code=room_code).first()
        if room is None or room.status in (Status.FINISHED, Status.CLOSED):
            return
        room.status = Status.FINISHED
        room.save(update_fields=["status"])
        if not room.players.filter(is_bot=False, has_left=False).exists():
            room.status = Status.CLOSED
            room.save(update_fields=["status"])
    broadcast_room(room)


def _maybe_rematch(room: Room, now: datetime) -> dict[str, Any] | None:
    """Inside a transaction, room locked and FINISHED. Makes the rematch room when all agree."""
    voters = list(room.players.filter(is_bot=False, has_left=False).order_by("joined_at"))
    if not voters:
        room.status = Status.CLOSED
        room.save(update_fields=["status"])
        return None
    if not all(v.wants_rematch for v in voters):
        return None

    old_host = room.players.filter(is_host=True).first()
    host_user_id = (
        old_host.user_id if old_host is not None and old_host in voters else voters[0].user_id
    )
    new_room = Room.objects.create(
        code=new_room_code(),
        game_type=room.game_type,
        variant=room.variant,
        max_players=room.max_players,
        options=room.options,
        is_locked=room.is_locked,
        status=Status.READY,
    )
    seats: dict[str, str] = {}
    # Humans still here, and the bots, keep their colours.
    for old in room.players.filter(Q(is_bot=True) | Q(has_left=False)).order_by("joined_at"):
        new = Player.objects.create(
            room=new_room,
            user_id=old.user_id,
            name=old.user.public_name if old.user_id else old.name,
            color=old.color,
            is_host=old.user_id is not None and old.user_id == host_user_id,
            is_bot=old.is_bot,
            is_ready=True,
        )
        seats[str(old.id)] = str(new.id)
    room.status = Status.CLOSED
    room.next_room = new_room
    room.save(update_fields=["status", "next_room"])

    snapshot = None
    seconds = countdown_seconds()
    if seconds > 0:
        new_room.status = Status.STARTING
        new_room.starts_at = now + timedelta(seconds=seconds)
        new_room.save(update_fields=["status", "starts_at"])
    else:
        snapshot = _begin(new_room)
    return {
        "room": new_room,
        "seats": seats,
        "snapshot": snapshot,
        "users": [v.user_id for v in voters],
    }


def _announce(room: Room, made: dict[str, Any] | None) -> None:
    """After the commit: the old room's news, and the new room's start."""
    if made is not None:
        new_room: Room = made["room"]
        # Rematch players' other waiting seats are left (one room at a time).
        for user_id in made["users"]:
            user = User.objects.filter(pk=user_id).first()
            if user is not None:
                services.leave_waiting_rooms(user, keep=new_room)
        services.broadcast(room.code, [{
            "type": "rematch_started",
            "room_code": new_room.code,
            "room_id": str(new_room.id),
            "seats": made["seats"],
        }])
        if made["snapshot"] is not None:
            services.broadcast(new_room.code, [made["snapshot"]])
    broadcast_room(room)
