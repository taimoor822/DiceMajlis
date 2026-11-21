"""
Ludo's table: the Token rows the app's board reads (a mirror of the engine
state), and the socket messages today's Flutter app understands
(dice_rolled, token_moved, turn_changed, game_finished …, each with ``version``).
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from ludo_engine import EventType, legal_moves
from ludo_engine.board import HOME_PROGRESS

from ..models import Game, Token
from . import Table


def token_ids_by_player(room) -> dict[str, list[str]]:
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


class LudoTable(Table):
    def on_start(self, room, state) -> None:
        for player in room.players.all():
            for _ in range(state.rules.tokens_per_player):
                Token.objects.create(player=player)

    def record(self, room, old_state, transition, *, deadline, now):
        Game.objects.filter(room=room).update(last_dice=transition.state.dice_value)
        token_ids = token_ids_by_player(room)
        _mirror_tokens(old_state, transition.state, token_ids)
        details: dict[str, Any] = {"dice": None, "movable_token_ids": []}
        for event in transition.events:
            if event.type is EventType.DICE_RESULT:
                ids = token_ids.get(event.data["player_id"], [])
                details = {
                    "dice": event.data["value"],
                    "movable_token_ids": [ids[k] for k in event.data["movable_tokens"] if k < len(ids)],
                }
        return socket_messages(transition, token_ids, deadline=deadline, now=now), details

    def snapshot(self, room, game, state) -> dict[str, Any]:
        extra: dict[str, Any] = {
            "tokens": [
                {
                    "id": str(t.id),
                    "player_id": str(t.player_id),
                    "position": t.position,
                    "is_finished": t.is_finished,
                }
                for t in Token.objects.filter(player__room=room).order_by("created_at")
            ],
            "last_dice": game.last_dice if game is not None else None,
            "movable_token_ids": [],
        }
        if state is not None:
            ids = token_ids_by_player(room).get(state.current_player.player_id, [])
            extra["movable_token_ids"] = [
                ids[m.token_index] for m in legal_moves(state) if m.token_index < len(ids)
            ]
        return extra


def _mirror_tokens(old, new, token_ids: dict[str, list[str]]) -> None:
    for old_player, new_player in zip(old.players, new.players):
        ids = token_ids.get(new_player.player_id, [])
        for index, (before, after) in enumerate(zip(old_player.tokens, new_player.tokens)):
            if before != after and index < len(ids):
                Token.objects.filter(id=ids[index]).update(
                    position=after, is_finished=after == HOME_PROGRESS
                )


def socket_messages(
    transition,
    token_ids: dict[str, list[str]],
    *,
    deadline: datetime | None = None,
    now: datetime | None = None,
) -> list[dict]:
    """Engine events → the messages the Flutter app already understands (+ version)."""
    from ..services import seconds_left

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
