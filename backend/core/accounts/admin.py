from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import DeviceSession, User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ("-created_at",)
    list_display = ("player_id", "username", "email", "is_guest", "is_active", "is_staff", "created_at")
    list_filter = ("is_guest", "is_active", "is_staff")
    search_fields = ("=player_id", "username", "email")
    readonly_fields = ("player_id", "created_at", "last_login")
    fieldsets = (
        (None, {"fields": ("player_id", "username", "email", "password", "is_guest")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Dates", {"fields": ("created_at", "last_login")}),
    )
    add_fieldsets = ((None, {"classes": ("wide",), "fields": ("username", "password1", "password2")}),)


@admin.register(DeviceSession)
class DeviceSessionAdmin(admin.ModelAdmin):
    list_display = ("user", "platform", "created_at", "last_seen_at", "revoked_at", "revoked_reason")
    list_filter = ("platform", "revoked_reason")
    search_fields = ("=user__player_id", "device_id")
    readonly_fields = [f.name for f in DeviceSession._meta.fields]
    actions = ["sign_out"]

    @admin.action(description="Sign these devices out")
    def sign_out(self, request, queryset):
        for session in queryset:
            session.revoke("admin")
