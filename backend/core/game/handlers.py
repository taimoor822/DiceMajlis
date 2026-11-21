"""
Game actions over the socket (``/ws/v1/``, step 1.12).

The app asks; the server decides. A request names the game (``game_id``) or its
room (``code``); the server finds the player's seat from the signed-in account,
never from the request. Every action goes through ``services.perform`` (the one
write path), and the events reach everyone on ``game/<id>`` through
``services.broadcast``.

``expected_version`` (optional) is the last state version the app has drawn.
If the game has moved on, the request is refused with ``stale_version`` and the
app asks for the state again (``request_state``) before acting.

Requests (all in the "game" rate-limit bucket):

  roll_dice      {game_id|code, expected_version?}            → {version, dice, movable_token_ids}
  move_token     {game_id|code, token_id|token_index, expected_version?} → {version, finished, winner}
  game_action    {game_id|code, action: {type, …}, expected_version?}   → {version, …}  any game
  leave_game     {game_id|code}                                → {left: true}  (a forfeit once started)
  request_state  {game_id|code}                                → the game_started snapshot
"""

from __future__ import annotations

from typing import Any

import game_platform
from game_platform import LUDO
from realtime.handlers import Context, handler
from realtime.protocol import ProtocolError

from . import services
from .models import Game, Player, Room
from .tables.ludo import token_ids_by_player


def _whole_number(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        if isinstance(value, str) and value.isdigit():
            return int(value)
        raise ProtocolError("invalid_request", f"{field} must be a whole number")
    return value


def _seat(ctx: Context, data: dict) -> tuple[Player, Room]:
    """The account's own seat in the game or room the request names."""
    if data.get("game_id") is not None:
        game = Game.objects.select_related("room").filter(id=_whole_number(data["game_id"], "game_id")).first()
        if game is None:
            raise ProtocolError("game_not_found", "No such game")
        room = game.room
    elif data.get("code"):
        room = Room.objects.filter(code=str(data["code"]).strip().upper()).first()
        if room is None:
            raise ProtocolError("room_not_found", "No such room")
    else:
        raise ProtocolError("invalid_request", "Send game_id or code")
    seat = room.players.filter(user=ctx.user, is_bot=False).first()
    if seat is None:
        raise ProtocolError("not_in_game", "You have no seat in this game")
    return seat, room


def _expected_version(data: dict) -> int | None:
    value = data.get("expected_version")
    return None if value is None else _whole_number(value, "expected_version")


def _ludo_only(room: Room) -> None:
    if room.game_type != LUDO:
        raise ProtocolError("wrong_game", "This room plays another game")


def _perform(room: Room, action: dict, expected_version: int | None) -> services.ActionResult:
    """Run one action and turn every refusal into the code the app shows."""
    try:
        result = services.perform(room.code, action, expected_version=expected_version)
    except Game.DoesNotExist:
        raise ProtocolError("game_not_started", "The game has not started")
    except services.GameConflict as exc:
        raise ProtocolError(exc.code, str(exc))
    except services.LegacyGame as exc:
        raise ProtocolError(exc.code, "This game was started before the rules update")
    except services.rule_errors() as exc:
        raise ProtocolError(getattr(exc, "code", "invalid_action"), str(exc))
    if result.next_is_bot:
        services.schedule_bots(room.code)
    return result


@handler("roll_dice", bucket="game")
def roll_dice(ctx: Context, data: dict) -> dict:
    seat, room = _seat(ctx, data)
    _ludo_only(room)
    result = _perform(room, {"type": "roll", "player_id": str(seat.id)}, _expected_version(data))
    return {
        "version": result.info.version,
        "dice": result.details.get("dice"),
        "movable_token_ids": list(result.details.get("movable_token_ids", [])),
    }


@handler("move_token", bucket="game")
def move_token(ctx: Context, data: dict) -> dict:
    seat, room = _seat(ctx, data)
    _ludo_only(room)
    player_id = str(seat.id)
    if data.get("token_id") is not None:
        mine = token_ids_by_player(room).get(player_id, [])
        token_id = str(data["token_id"])
        if token_id not in mine:
            raise ProtocolError("token_not_found", "That token is not yours")
        token_index = mine.index(token_id)
    elif data.get("token_index") is not None:
        token_index = _whole_number(data["token_index"], "token_index")
    else:
        raise ProtocolError("invalid_request", "Send token_id or token_index")
    result = _perform(
        room,
        {"type": "move", "player_id": player_id, "token_index": token_index},
        _expected_version(data),
    )
    return {
        "version": result.info.version,
        "finished": result.info.finished,
        "winner": result.info.finished and result.info.winner_id == player_id,
    }


@handler("game_action", bucket="game")
def game_action(ctx: Context, data: dict) -> dict:
    """Any game's own actions, e.g. ``{"type": "move", "token_index": 2}`` for Ludo."""
    seat, room = _seat(ctx, data)
    action = data.get("action")
    if not isinstance(action, dict):
        raise ProtocolError("invalid_request", "Send the action as an object")
    allowed = game_platform.get_game(room.game_type).player_action_types
    if action.get("type") not in allowed:
        raise ProtocolError("invalid_action", f"Players can send: {', '.join(sorted(allowed))}")
    result = _perform(room, {**action, "player_id": str(seat.id)}, _expected_version(data))
    return {"version": result.info.version, **result.details}


@handler("leave_game", bucket="game")
def leave_game(ctx: Context, data: dict) -> dict:
    seat, _room = _seat(ctx, data)
    try:
        services.leave_room(seat)
    except services.GameConflict as exc:
        raise ProtocolError(exc.code, str(exc))
    return {"left": True}


@handler("request_state", bucket="game", changes_state=False)
def request_state(ctx: Context, data: dict) -> dict:
    """The whole current state (the same snapshot a new subscriber gets first)."""
    _seat_, room = _seat(ctx, data)
    snapshot = services.game_snapshot(room)
    snapshot.pop("type", None)
    return snapshot
