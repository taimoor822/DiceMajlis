from django.contrib import admin

from .models import Privilege, PrivilegeGrant, UserPrivilegeOverride


class GrantInline(admin.TabularInline):
    model = PrivilegeGrant
    extra = 0
    fields = ("source_type", "source_key", "rank", "mode", "value", "starts_at", "ends_at")


@admin.register(Privilege)
class PrivilegeAdmin(admin.ModelAdmin):
    """The privilege catalog. "Built" = the app acts on it; others show as coming soon."""

    list_display = ("code", "name", "value_type", "merge", "category", "built", "active")
    list_filter = ("value_type", "category", "built", "active")
    search_fields = ("code", "name")
    inlines = [GrantInline]

    def has_delete_permission(self, request, obj=None):
        return False  # untick "active"


@admin.register(PrivilegeGrant)
class PrivilegeGrantAdmin(admin.ModelAdmin):
    """Which source gives which privilege: "base" = everyone, "item:<code>" = owning that item."""

    list_display = ("privilege", "source_type", "source_key", "rank", "mode", "value", "ends_at")
    list_filter = ("source_type", "mode")
    search_fields = ("source_key", "privilege__code")


@admin.register(UserPrivilegeOverride)
class UserPrivilegeOverrideAdmin(admin.ModelAdmin):
    """Allow or deny one privilege for one account. A deny wins over everything."""

    list_display = ("user", "privilege", "mode", "value", "reason", "ends_at", "created_by", "created_at")
    list_filter = ("mode", "privilege")
    search_fields = ("=user__player_id", "reason")
    autocomplete_fields = ("user",)
    fields = ("user", "privilege", "mode", "value", "reason", "ends_at")

    def save_model(self, request, obj, form, change):
        if not change:
            obj.created_by = request.user
        super().save_model(request, obj, form, change)
