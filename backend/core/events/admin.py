from django.contrib import admin

from .models import DomainEvent


@admin.register(DomainEvent)
class DomainEventAdmin(admin.ModelAdmin):
    list_display = ("id", "kind", "created_at", "processed_at", "attempts")
    list_filter = ("kind", "processed_at")
    readonly_fields = ("kind", "payload", "created_at", "processed_at", "attempts", "next_attempt_at", "last_error")
