from django.contrib import admin

from .levels import level_for_xp
from .models import Profile


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ("display_name", "player_id", "country", "level", "xp", "updated_at")
    search_fields = ("display_name", "=user__player_id")
    list_filter = ("country",)
    readonly_fields = ("user", "created_at", "updated_at")

    @admin.display(ordering="user__player_id")
    def player_id(self, profile):
        return profile.user.player_id

    @admin.display(ordering="xp")
    def level(self, profile):
        return level_for_xp(profile.xp)
