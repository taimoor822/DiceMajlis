"""
Statistics: kept up to date from ``game_finished`` (game.results), read by the
API and by achievements (which listen to ``player_stats_changed``).

Rules: only real games count (2+ accounts, no bots: ``payload["counts"]``);
1st place = a win; every other place, and leaving early, is a loss. Ludo has no
draws.
"""

from __future__ import annotations

from typing import Any

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.utils.dateparse import parse_datetime

from .models import PlayerGameResult, PlayerStats

STATS_CHANGED = "player_stats_changed"
RECENT_RESULTS = 10


def on_game_finished(payload: dict[str, Any], event=None) -> None:
    if not payload.get("counts"):
        return
    User = get_user_model()
    finished_at = parse_datetime(payload["finished_at"])
    for seat in payload["players"]:
        if seat["is_bot"] or not seat.get("user_id"):
            continue
        user = User.objects.filter(pk=seat["user_id"]).first()
        if user is None:  # account deleted since
            continue
        record_result(
            user,
            game_id=payload["game_id"],
            room_code=payload["room_code"],
            game_type=payload["game_type"],
            variant=payload["variant"],
            place=seat["place"],
            player_count=payload["player_count"],
            forfeited=seat["status"] == "forfeited",
            finished_at=finished_at,
        )


def record_result(user, *, game_id, room_code, game_type, variant, place, player_count, forfeited, finished_at) -> bool:
    """Save one account's result and update its stats. False when it was saved before."""
    from events.outbox import emit

    won = place == 1 and not forfeited
    with transaction.atomic():
        try:
            with transaction.atomic():
                PlayerGameResult.objects.create(
                    user=user,
                    game_id=game_id,
                    room_code=room_code,
                    game_type=game_type,
                    variant=variant,
                    place=place,
                    player_count=player_count,
                    won=won,
                    forfeited=forfeited,
                    finished_at=finished_at,
                )
        except IntegrityError:
            return False  # this game was counted already
        PlayerStats.objects.get_or_create(user=user, game_type=game_type)
        stats = PlayerStats.objects.select_for_update().get(user=user, game_type=game_type)
        stats.games_played += 1
        stats.forfeits += int(forfeited)
        if won:
            stats.wins += 1
            stats.win_streak += 1
            stats.best_win_streak = max(stats.best_win_streak, stats.win_streak)
        else:
            stats.win_streak = 0
        if stats.last_game_at is None or finished_at > stats.last_game_at:
            stats.last_game_at = finished_at
        stats.save()
        # Achievements and the app react to this (after the commit).
        emit(
            STATS_CHANGED,
            {
                "user_id": str(user.pk),
                "game_type": game_type,
                "game_id": game_id,
                "won": won,
                "stats": stats_row(stats),
                "total": totals(user),
            },
        )
        transaction.on_commit(lambda: _push(user, game_type))
    return True


def _push(user, game_type: str) -> None:
    from realtime.publish import publish

    publish(f"user/{user.player_id}", "stats_changed", {"game_type": game_type})


def _win_rate(wins: int, games: int) -> int:
    """Whole percent, rounded half up; 0 before the first game."""
    return (wins * 100 * 2 + games) // (games * 2) if games else 0


def stats_row(stats: PlayerStats | None) -> dict[str, int]:
    if stats is None:
        return {"games_played": 0, "wins": 0, "losses": 0, "forfeits": 0, "win_rate": 0,
                "win_streak": 0, "best_win_streak": 0}
    return {
        "games_played": stats.games_played,
        "wins": stats.wins,
        "losses": stats.losses,
        "forfeits": stats.forfeits,
        "win_rate": _win_rate(stats.wins, stats.games_played),
        "win_streak": stats.win_streak,
        "best_win_streak": stats.best_win_streak,
    }


def totals(user) -> dict[str, int]:
    """Every game type added up. Streaks: the best of any one game type."""
    rows = list(PlayerStats.objects.filter(user=user))
    games = sum(r.games_played for r in rows)
    wins = sum(r.wins for r in rows)
    return {
        "games_played": games,
        "wins": wins,
        "losses": games - wins,
        "forfeits": sum(r.forfeits for r in rows),
        "win_rate": _win_rate(wins, games),
        "win_streak": max((r.win_streak for r in rows), default=0),
        "best_win_streak": max((r.best_win_streak for r in rows), default=0),
    }


def stats_payload(user) -> dict[str, Any]:
    """What the player sees: totals, each game type, and the latest results."""
    rows = PlayerStats.objects.filter(user=user).order_by("game_type")
    recent = PlayerGameResult.objects.filter(user=user)[:RECENT_RESULTS]
    return {
        "total": totals(user),
        "game_types": {row.game_type: stats_row(row) for row in rows},
        "recent": [
            {
                "game_type": r.game_type,
                "variant": r.variant,
                "place": r.place,
                "player_count": r.player_count,
                "won": r.won,
                "forfeited": r.forfeited,
                "finished_at": r.finished_at.isoformat(),
            }
            for r in recent
        ],
    }
