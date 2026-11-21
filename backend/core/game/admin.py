from django.contrib import admin
from .models import Room, Player, Game, GameAction, Turn

admin.site.register(Player)
admin.site.register(Turn)


@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    list_display = ('code', 'game_type', 'variant', 'max_players', 'is_started', 'created_at')
    list_filter = ('game_type', 'variant', 'is_started')
    search_fields = ('code',)


@admin.register(Game)
class GameAdmin(admin.ModelAdmin):
    list_display = ('room', 'game_type', 'variant', 'version', 'is_finished')
    list_filter = ('game_type', 'variant', 'is_finished')


@admin.register(GameAction)
class GameActionAdmin(admin.ModelAdmin):
    """Read-only audit log of every accepted game action."""

    list_display = ('game', 'version', 'created_at')
    list_filter = ('created_at',)
    readonly_fields = ('game', 'version', 'action', 'created_at')

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False
