"""
What a finished game says about its players (any game type).

When a game ends, ``services.perform()`` calls ``emit_game_finished`` inside the
same transaction, which writes a ``game_finished`` domain event (events app).
Other parts of the server react to it: account XP (profiles.xp), statistics and
achievements later. They all read the same payload:

    {
      "game_id": 12, "room_code": "AB12CD", "game_type": "ludo", "variant": "classic",
      "finished_at": "2026-11-21T12:00:00+00:00",
      "player_count": 4, "human_count": 4, "bot_count": 0,
      "counts": true,                 # a real game: see counts_for_progress()
      "players": [
        {"seat_id": "<Player.id>", "user_id": "<User.id>" | null, "is_bot": false,
         "place": 1, "status": "finished"},    # active / finished / forfeited
        ...
      ]
    }
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Iterable, Mapping

from .models import Game, Player, Room

GAME_FINISHED = "game_finished"

# A game needs at least this many people (accounts) at the table to count.
MIN_HUMANS_TO_COUNT = 2


def counts_for_progress(players: Iterable[Mapping[str, Any]]) -> bool:
    """
    Does this game count for XP, statistics and achievements? Only real games
    between people: at least two accounts and no bots at the table (SOCIAL_MAJLIS
    §4: "bot games don't count", or anyone could farm the bot). Offline games
    never reach the server at all.
    """
    players = list(players)
    humans = [p for p in players if not p["is_bot"] and p.get("user_id")]
    bots = [p for p in players if p["is_bot"]]
    return len(humans) >= MIN_HUMANS_TO_COUNT and not bots


def game_finished_payload(
    game: Game, room: Room, standings: list[dict[str, Any]], now: datetime
) -> dict[str, Any]:
    seats = {str(p.id): p for p in Player.objects.filter(room=room)}
    players = []
    for row in standings:
        seat = seats.get(str(row["player_id"]))
        players.append(
            {
                "seat_id": str(row["player_id"]),
                "user_id": str(seat.user_id) if seat is not None and seat.user_id else None,
                "is_bot": bool(seat.is_bot) if seat is not None else False,
                "place": row["place"],
                "status": row["status"],
            }
        )
    bot_count = sum(1 for p in players if p["is_bot"])
    return {
        "game_id": game.pk,
        "room_code": room.code,
        "game_type": game.game_type,
        "variant": game.variant,
        "finished_at": now.isoformat(),
        "player_count": len(players),
        "human_count": sum(1 for p in players if not p["is_bot"] and p["user_id"]),
        "bot_count": bot_count,
        "counts": counts_for_progress(players),
        "players": players,
    }


def emit_game_finished(game: Game, room: Room, standings: list[dict[str, Any]], now: datetime):
    """Call inside the transaction that saved the finished game."""
    from events.outbox import emit

    return emit(GAME_FINISHED, game_finished_payload(game, room, standings, now))
