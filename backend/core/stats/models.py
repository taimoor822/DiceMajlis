"""
Player statistics from real online games (SOCIAL_MAJLIS §4, step S2). Bot games
and offline games never count. Each finished game leaves one ``PlayerGameResult``
per account at the table (the record of what happened, once per game), and the
account's ``PlayerStats`` for that game type are updated in the same transaction.
"""

from django.conf import settings
from django.db import models
from django.db.models import Q


class PlayerGameResult(models.Model):
    """One account's result in one finished game (written once, never changed)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="game_results", on_delete=models.CASCADE)
    game_id = models.BigIntegerField()
    room_code = models.CharField(max_length=6)
    game_type = models.CharField(max_length=20)
    variant = models.CharField(max_length=30)
    place = models.PositiveSmallIntegerField()
    player_count = models.PositiveSmallIntegerField()
    won = models.BooleanField()
    # Left the game before the end (counts as a loss).
    forfeited = models.BooleanField(default=False)
    finished_at = models.DateTimeField()

    class Meta:
        ordering = ["-finished_at", "-id"]
        constraints = [models.UniqueConstraint(fields=["user", "game_id"], name="one_result_per_game")]
        indexes = [models.Index(fields=["user", "finished_at"], name="result_user_time_idx")]

    def __str__(self) -> str:
        return f"{self.user} game {self.game_id}: place {self.place}/{self.player_count}"


class PlayerStats(models.Model):
    """An account's totals for one game type. Changed only by stats.services."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="stats", on_delete=models.CASCADE)
    game_type = models.CharField(max_length=20)
    games_played = models.PositiveIntegerField(default=0)
    # 1st place.
    wins = models.PositiveIntegerField(default=0)
    # Games left before the end (also counted as played, not won).
    forfeits = models.PositiveIntegerField(default=0)
    # Wins in a row, now and at best.
    win_streak = models.PositiveIntegerField(default=0)
    best_win_streak = models.PositiveIntegerField(default=0)
    last_game_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "game_type"], name="one_stats_row_per_game_type"),
            models.CheckConstraint(condition=Q(wins__lte=models.F("games_played")), name="wins_within_games"),
            models.CheckConstraint(
                condition=Q(win_streak__lte=models.F("best_win_streak")), name="streak_within_best"
            ),
        ]

    @property
    def losses(self) -> int:
        return self.games_played - self.wins

    def __str__(self) -> str:
        return f"{self.user} {self.game_type}: {self.wins}/{self.games_played}"
