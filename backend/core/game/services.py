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
import random
import threading
import time
from dataclasses import dataclass
from typing import Any

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.conf import settings
from django.db import close_old_connections, transaction

import ludo_engine as engine
from ludo_engine import EngineError, EventType, GameState, SecureDice, TurnPhase
from ludo_engine.board import HOME_PROGRESS

from .models import Game, GameAction, Player, Room, Token

logger = logging.getLogger(__name__)

COLOR_BY_SEAT = ("red", "blue", "green", "yellow")
SEAT_BY_COLOR = {"red": 0, "blue": 1, "green": 2, "yellow": 3, "orange": 3, "amber": 3}

MAX_BOT_ACTIONS_PER_RUN = 500


class GameConflict(Exception):
    """Another request changed the game first. The client should resync and retry."""

    code = "stale_version"


class LegacyGame(Exception):
    """Game was started before the engine existed; its positions use the old 0..100 scale."""

    code = "legacy_game"


@dataclass(frozen=True)
class ActionResult:
    state: GameState
    events: tuple[engine.Event, ...]
    dice: int | None
    next_is_bot: bool


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
    )
    for player in players:
        for _ in range(state.rules.tokens_per_player):
            Token.objects.create(player=player)
    return game, state


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


def perform(room_code: str, action: dict[str, Any]) -> ActionResult:
    """
    Apply one action. ``action`` uses ludo_engine.apply_action's format, plus:
      - "roll" without "value": the server rolls with SecureDice
      - "bot_move": the server picks the move with ludo_engine.choose_move
    Raises EngineError (rule violations), GameConflict, LegacyGame,
    Room.DoesNotExist / Game.DoesNotExist.
    """
    with transaction.atomic():
        room = Room.objects.select_for_update().get(code=room_code)
        game = Game.objects.select_for_update().get(room=room)
        if game.state is None:
            raise LegacyGame("this game was started before the rules update")

        state = GameState.from_dict(game.state)
        if state.version != game.version:
            raise GameConflict("stored state and version disagree")

        resolved = _resolve(state, action)
        transition = engine.apply_action(state, resolved)
        new_state = transition.state

        # Optimistic check: only save if nobody saved a newer version meanwhile.
        # (SQLite ignores SELECT ... FOR UPDATE, so this is the real guard there.)
        current = new_state.current_player.player_id
        saved = Game.objects.filter(pk=game.pk, version=state.version).update(
            state=new_state.to_dict(),
            version=new_state.version,
            current_turn_id=current,
            last_dice=new_state.dice_value,
            is_finished=new_state.is_finished,
        )
        if saved != 1:
            raise GameConflict("the game changed while this action was running")

        GameAction.objects.create(game=game, version=new_state.version, action=resolved)
        token_ids = token_ids_by_player(room)
        _mirror_tokens(state, new_state, token_ids)
        messages = socket_messages(transition, token_ids)
        next_is_bot = (
            not new_state.is_finished
            and Player.objects.filter(id=current, is_bot=True).exists()
        )

    broadcast(room_code, messages)
    dice = next(
        (e.data["value"] for e in transition.events if e.type is EventType.DICE_RESULT), None
    )
    return ActionResult(new_state, transition.events, dice, next_is_bot)


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
    if kind == "timeout" and "dice_value" not in action:
        return {**action, "dice_value": SecureDice().roll()}
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
# Socket messages
# ---------------------------------------------------------------------------


def socket_messages(transition: engine.Transition, token_ids: dict[str, list[str]]) -> list[dict]:
    """Engine events → the messages the Flutter app already understands (+ version)."""

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
                "version": version,
            })
        elif event.type is EventType.GAME_FINISHED:
            payloads.append({
                "type": "game_finished",
                "winner_id": data["winner_id"],
                "standings": data["standings"],
                "version": version,
            })
        elif event.type in (
            EventType.PLAYER_TIMEOUT,
            EventType.PLAYER_FINISHED,
            EventType.PLAYER_FORFEITED,
        ):
            payloads.append({"type": event.type.value, **data, "version": version})
        # token_captured / token_finished / turn_ended are folded into the messages above.
    return [{"type": "game_event", "payload": p} for p in payloads]


def group_name(room_code: str) -> str:
    return f"lobby_{room_code}"


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
