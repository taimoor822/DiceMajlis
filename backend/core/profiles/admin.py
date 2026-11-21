from django.contrib import admin

from .levels import level_for_xp
from .models import Profile, XpEntry


class XpEntryInline(admin.TabularInline):
    model = XpEntry
    fields = ("created_at", "amount", "xp_after", "reason", "reference_type", "reference_id")
    readonly_fields = fields
    extra = 0
    max_num = 0
    can_delete = False
    ordering = ("-created_at",)
    show_change_link = False

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ("display_name", "player_id", "country", "level", "xp", "updated_at")
    search_fields = ("display_name", "=user__player_id")
    list_filter = ("country",)
    # XP changes only through profiles.xp.add_xp (its entries are listed below).
    readonly_fields = ("user", "xp", "created_at", "updated_at")
    inlines = [XpEntryInline]

    @admin.display(ordering="user__player_id")
    def player_id(self, profile):
        return profile.user.player_id

    @admin.display(ordering="xp")
    def level(self, profile):
        return level_for_xp(profile.xp)


@admin.register(XpEntry)
class XpEntryAdmin(admin.ModelAdmin):
    """Every XP change (read only: XP is given by the server, not by hand)."""

    list_display = ("profile", "amount", "xp_after", "reason", "reference_id", "reward_day", "created_at")
    list_filter = ("reason",)
    search_fields = ("=profile__user__player_id", "idempotency_key")
    date_hierarchy = "created_at"

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
