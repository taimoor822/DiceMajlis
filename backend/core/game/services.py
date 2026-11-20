"""
Runs live games on ``ludo_engine``. This is the ONLY module that changes game
state: views, the socket consumer and the bot loop all call into it.

Each action runs in one DB transaction:
    lock game → load engine state → server dice → engine → save new state
    (only if nobody else saved first) → log action → mirror Token rows
and the resulting events are broadcast after the transaction commits.

Socket messages keep the names the Flutter app already handles
(dice_rolled, token_moved, turn_changed, game_finished) and add ``version``.
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

import ludo_engine as engine
from ludo_engine import EngineError, EventType, GameState, SecureDice, TurnPhase
from ludo_engine.board import HOME_PROGRESS

from .models import Game, GameAction, Player, Room, Token

logger = logging.getLogger(__name__)

COLOR_BY_SEAT = engine.SEAT_COLORS  # ("red", "blue", "green", "yellow")
SEAT_BY_COLOR = {"red": 0, "blue": 1, "green": 2, "yellow": 3, "orange": 3, "amber": 3}

# Seats handed out as people join: the second player sits opposite the host,
# like the engine's default two-player game.
JOIN_SEAT_ORDER = (0, 2, 1, 3)

MAX_BOT_ACTIONS_PER_RUN = 500


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
    state: GameState
    events: tuple[engine.Event, ...]
    dice: int | None
    next_is_bot: bool
    # After a roll: the DB ids of the tokens that may move with it.
    movable_token_ids: tuple[str, ...] = ()


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


def start_game(room: Room, host: Player) -> tuple[Game, GameState]:
    """Create the engine game, seat everyone, create tokens. Call inside a transaction."""
    players = list(room.players.order_by("joined_at"))
    seats = assign_seats(players)
    for player in players:
        seat = seats[str(player.id)]
        if preferred_seat(player.color) != seat:
            # Colour decides the board path in the app, so it must match the seat.
            player.color = COLOR_BY_SEAT[seat]
            player.save(update_fields=["color"])

    state = engine.new_game(
        str(room.id),
        [str(p.id) for p in players],
        seats=[seats[str(p.id)] for p in players],
        first_player_id=str(host.id),
    )
    snapshot = state.to_dict()
    game = Game.objects.create(
        room=room,
        current_turn=host,
        state=snapshot,
        initial_state=snapshot,
        version=state.version,
        turn_deadline=timezone.now() + turn_duration(state),
    )
    for player in players:
        for _ in range(state.rules.tokens_per_player):
            Token.objects.create(player=player)
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
    game = Game.objects.filter(room=room).only("state", "is_finished").first()
    if game is None or game.is_finished or game.state is None:
        return False
    try:
        status = GameState.from_dict(game.state).player(str(player.id)).status
    except EngineError:
        return False
    return status is engine.PlayerStatus.ACTIVE


def active_seat_for(user) -> dict[str, Any] | None:
    """The room ``user`` goes back to when the app opens (session restore), or None."""
    for seat in seats_of(user):
        if seat_in_play(seat):
            room = seat.room
            return {
                "code": room.code,
                "seat_id": str(seat.id),
                "is_host": seat.is_host,
                "max_players": room.max_players,
                "started": room.is_started,
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
        except (EngineError, LegacyGame, Game.DoesNotExist):
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


def token_ids_by_player(room: Room) -> dict[str, list[str]]:
    """
    Engine token index ↔ DB token id. Ordered by id string, the same order the
    Flutter board uses for labels, so "token 1" means the same thing everywhere.
    """
    result: dict[str, list[str]] = {}
    for token in Token.objects.filter(player__room=room).only("id", "player_id"):
        result.setdefault(str(token.player_id), []).append(str(token.id))
    for ids in result.values():
        ids.sort()
    return result


def turn_duration(state: GameState) -> timedelta:
    return timedelta(seconds=state.rules.turn_timeout_seconds)


def seconds_left(deadline: datetime | None, now: datetime | None = None) -> int | None:
    """Whole seconds until ``deadline`` (never negative), or None when there is no timer."""
    if deadline is None:
        return None
    remaining = (deadline - (now or timezone.now())).total_seconds()
    return max(0, math.ceil(remaining))


def perform(room_code: str, action: dict[str, Any], *, now: datetime | None = None) -> ActionResult:
    """
    Apply one action. ``action`` uses ludo_engine.apply_action's format, plus:
      - "roll" without "value": the server rolls with SecureDice
      - "bot_move": the server picks the move with ludo_engine.choose_move
    Raises EngineError (rule violations), GameConflict, LegacyGame, TimerNotDue,
    Room.DoesNotExist / Game.DoesNotExist.
    """
    now = now or timezone.now()
    with transaction.atomic():
        room = Room.objects.select_for_update().get(code=room_code)
        game = Game.objects.select_for_update().get(room=room)
        if game.state is None:
            raise LegacyGame("this game was started before the rules update")

        state = GameState.from_dict(game.state)
        if state.version != game.version:
            raise GameConflict("stored state and version disagree")
        if action.get("type") == "timeout" and (
            game.turn_deadline is None or game.turn_deadline > now
        ):
            raise TimerNotDue("this turn has not run out yet")

        resolved = _resolve(state, action)
        transition = engine.apply_action(state, resolved)
        new_state = transition.state

        # Optimistic check: only save if nobody saved a newer version meanwhile.
        # (SQLite ignores SELECT ... FOR UPDATE, so this is the real guard there.)
        current = new_state.current_player.player_id
        if new_state.is_finished:
            deadline = None
        elif new_state.turn_number != state.turn_number:
            deadline = now + turn_duration(new_state)  # a new turn gets a fresh clock
        else:
            deadline = game.turn_deadline  # same turn (roll -> move): clock keeps running
        saved = Game.objects.filter(pk=game.pk, version=state.version).update(
            state=new_state.to_dict(),
            version=new_state.version,
            current_turn_id=current,
            last_dice=new_state.dice_value,
            is_finished=new_state.is_finished,
            turn_deadline=deadline,
        )
        if saved != 1:
            raise GameConflict("the game changed while this action was running")

        GameAction.objects.create(game=game, version=new_state.version, action=resolved)
        token_ids = token_ids_by_player(room)
        _mirror_tokens(state, new_state, token_ids)
        messages = socket_messages(transition, token_ids, deadline=deadline, now=now)
        next_is_bot = (
            not new_state.is_finished
            and Player.objects.filter(id=current, is_bot=True).exists()
        )

        dice, movable = None, ()
        for event in transition.events:
            if event.type is EventType.DICE_RESULT:
                ids = token_ids.get(event.data["player_id"], [])
                dice = event.data["value"]
                movable = tuple(ids[k] for k in event.data["movable_tokens"] if k < len(ids))

    broadcast(room_code, messages)
    return ActionResult(new_state, transition.events, dice, next_is_bot, movable)


def _resolve(state: GameState, action: dict[str, Any]) -> dict[str, Any]:
    """Fill in server-side choices so the logged action can be replayed exactly."""
    kind = action.get("type")
    if kind == "roll":
        # Never trust a client value: the server always rolls, and only when a roll is legal.
        engine.check_roll(state, str(action["player_id"]))
        return {"type": "roll", "player_id": str(action["player_id"]), "value": SecureDice().roll()}
    if kind == "bot_move":
        if state.phase is not TurnPhase.AWAITING_MOVE:
            raise engine.WrongPhase("bot has nothing to move")
        if state.current_player.player_id != str(action["player_id"]):
            raise engine.NotYourTurn("not the bot's turn")
        chosen = engine.choose_move(state)
        return {"type": "move", "player_id": str(action["player_id"]), "token_index": chosen.token_index}
    if kind == "timeout":
        expected_turn = action.get("turn_number", state.turn_number)
        engine.check_timeout(state, expected_turn)  # stale timers never touch the dice
        rolling = state.phase is TurnPhase.AWAITING_ROLL
        return {
            "type": "timeout",
            "turn_number": expected_turn,
            "dice_value": SecureDice().roll() if rolling else None,
        }
    return dict(action)


def _mirror_tokens(old: GameState, new: GameState, token_ids: dict[str, list[str]]) -> None:
    for old_player, new_player in zip(old.players, new.players):
        ids = token_ids.get(new_player.player_id, [])
        for index, (before, after) in enumerate(zip(old_player.tokens, new_player.tokens)):
            if before != after and index < len(ids):
                Token.objects.filter(id=ids[index]).update(
                    position=after, is_finished=after == HOME_PROGRESS
                )


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
    ``game_started`` socket message.
    """
    snapshot: dict[str, Any] = {
        "type": "game_started",
        "room_code": room.code,
        "players": players_payload(room),
        "tokens": [
            {
                "id": str(t.id),
                "player_id": str(t.player_id),
                "position": t.position,
                "is_finished": t.is_finished,
            }
            for t in Token.objects.filter(player__room=room).order_by("created_at")
        ],
        "current_turn_player_id": None,
        "last_dice": None,
        "movable_token_ids": [],
        "version": None,
        "seconds_left": None,
        "warning_seconds": None,
        "winner_id": None,
    }
    game = Game.objects.filter(room=room).first()
    if game is None:
        return snapshot
    snapshot.update(
        current_turn_player_id=str(game.current_turn_id) if game.current_turn_id else None,
        last_dice=game.last_dice,
        version=game.version,
        seconds_left=seconds_left(game.turn_deadline),
    )
    if game.state is not None:
        state = GameState.from_dict(game.state)
        ids = token_ids_by_player(room).get(state.current_player.player_id, [])
        snapshot.update(
            movable_token_ids=[
                ids[m.token_index] for m in engine.legal_moves(state) if m.token_index < len(ids)
            ],
            warning_seconds=state.rules.timeout_warning_seconds,
            winner_id=state.winner_id,
        )
    return snapshot


# ---------------------------------------------------------------------------
# Socket messages
# ---------------------------------------------------------------------------


def socket_messages(
    transition: engine.Transition,
    token_ids: dict[str, list[str]],
    *,
    deadline: datetime | None = None,
    now: datetime | None = None,
) -> list[dict]:
    """Engine events → the messages the Flutter app already understands (+ version)."""
    rules = transition.state.rules

    def token_id(player_id: str, index: int) -> str | None:
        ids = token_ids.get(player_id, [])
        return ids[index] if index < len(ids) else None

    events = list(transition.events)
    payloads: list[dict[str, Any]] = []
    for i, event in enumerate(events):
        data, version = event.data, event.version
        if event.type is EventType.DICE_RESULT:
            payloads.append({
                "type": "dice_rolled",
                "player_id": data["player_id"],
                "dice": data["value"],
                "movable_token_ids": [token_id(data["player_id"], k) for k in data["movable_tokens"]],
                "version": version,
            })
        elif event.type is EventType.TOKEN_MOVED:
            killed = []
            for later in events[i + 1:]:
                if later.type is not EventType.TOKEN_CAPTURED:
                    break
                killed.append(token_id(later.data["player_id"], later.data["token_index"]))
            payloads.append({
                "type": "token_moved",
                "player_id": data["player_id"],
                "token_id": token_id(data["player_id"], data["token_index"]),
                "from": data["from_progress"],
                "to": data["to_progress"],
                "dice": data["dice"],
                "killed": killed,
                "version": version,
            })
        elif event.type is EventType.TURN_STARTED:
            payloads.append({
                "type": "turn_changed",
                "player_id": data["player_id"],
                "turn_number": data["turn_number"],
                "extra_turn": data["extra_turn"],
                # Countdown for the app. seconds_left avoids trusting the phone's clock.
                "seconds_left": seconds_left(deadline, now),
                "turn_deadline": deadline.isoformat() if deadline else None,
                "warning_seconds": rules.timeout_warning_seconds,
                "version": version,
            })
        elif event.type is EventType.GAME_FINISHED:
            payloads.append({
                "type": "game_finished",
                "winner_id": data["winner_id"],
                "standings": data["standings"],
                "version": version,
            })
        elif event.type is EventType.PLAYER_TIMEOUT:
            payloads.append({
                "type": "player_timeout",
                **data,
                "max_missed_turns": rules.max_missed_turns,
                "version": version,
            })
        elif event.type in (EventType.PLAYER_FINISHED, EventType.PLAYER_FORFEITED):
            payloads.append({"type": event.type.value, **data, "version": version})
        # token_captured / token_finished / turn_ended are folded into the messages above.
    return [{"type": "game_event", "payload": p} for p in payloads]


def group_name(room_code: str) -> str:
    return f"lobby_{room_code}"


def broadcast_players(room: Room) -> None:
    """Tell everyone watching ``room`` who is seated now."""
    broadcast(room.code, [{"type": "players_updated", "players": players_payload(room)}])


def broadcast(room_code: str, messages: list[dict]) -> None:
    if not messages:
        return
    layer = get_channel_layer()
    if layer is None:
        return
    send = async_to_sync(layer.group_send)
    for message in messages:
        send(group_name(room_code), message)


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
        game = Game.objects.filter(room__code=room_code).only("state", "is_finished").first()
        if game is None or game.state is None or game.is_finished:
            return
        state = GameState.from_dict(game.state)
        bot_id = state.current_player.player_id
        if not Player.objects.filter(id=bot_id, is_bot=True).exists():
            return

        _bot_pause()
        kind = "roll" if state.phase is TurnPhase.AWAITING_ROLL else "bot_move"
        try:
            perform(room_code, {"type": kind, "player_id": bot_id})
            conflicts = 0
        except GameConflict:
            conflicts += 1
            if conflicts > 3:
                return
        except EngineError:
            return  # someone else acted first; the next action will reschedule us


def _bot_pause() -> None:
    low, high = getattr(settings, "GAME_BOT_DELAY_SECONDS", (0.6, 1.2))
    if high > 0:
        time.sleep(random.uniform(low, high))
