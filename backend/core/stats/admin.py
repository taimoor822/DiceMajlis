from django.contrib import admin

from .models import PlayerGameResult, PlayerStats


class ReadOnlyAdmin(admin.ModelAdmin):
    """Statistics come from finished games only; nothing is changed by hand."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(PlayerStats)
class PlayerStatsAdmin(ReadOnlyAdmin):
    list_display = ("user", "game_type", "games_played", "wins", "forfeits", "win_streak", "best_win_streak")
    list_filter = ("game_type",)
    search_fields = ("=user__player_id",)


@admin.register(PlayerGameResult)
class PlayerGameResultAdmin(ReadOnlyAdmin):
    list_display = ("user", "game_id", "game_type", "place", "player_count", "won", "forfeited", "finished_at")
    list_filter = ("game_type", "won", "forfeited")
    search_fields = ("=user__player_id", "room_code")
    date_hierarchy = "finished_at"
