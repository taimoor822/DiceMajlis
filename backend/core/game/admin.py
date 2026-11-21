from django.contrib import admin
from .models import Room, RoomInvite, Player, Game, GameAction, Turn

admin.site.register(Player)
admin.site.register(Turn)


@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    list_display = ('code', 'game_type', 'variant', 'status', 'max_players', 'is_locked', 'created_at')
    list_filter = ('game_type', 'variant', 'status', 'is_locked')
    search_fields = ('code',)
    raw_id_fields = ('next_room',)
    filter_horizontal = ('kicked_users',)


@admin.register(RoomInvite)
class RoomInviteAdmin(admin.ModelAdmin):
    list_display = ('room', 'from_user', 'to_user', 'created_at')
    raw_id_fields = ('room', 'from_user', 'to_user')


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
