from django.contrib import admin
from .models import Room, Player, Game, GameAction, Turn

admin.site.register(Room)
admin.site.register(Player)
admin.site.register(Game)
admin.site.register(Turn)


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
