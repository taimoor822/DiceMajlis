from django.contrib import admin

from .models import RewardClaim


@admin.register(RewardClaim)
class RewardClaimAdmin(admin.ModelAdmin):
    """Every reward given (read only: rewards are given by the server, not by hand)."""

    list_display = ("user", "kind", "reward_day", "streak_day", "bundle", "created_at")
    list_filter = ("kind",)
    search_fields = ("=user__player_id", "idempotency_key")
    date_hierarchy = "created_at"

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
