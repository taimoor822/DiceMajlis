from django import forms
from django.contrib import admin
from django.db import transaction

from . import services
from .models import EquippedCosmetic, InventoryItem, ItemAdjustment, ItemDefinition, ItemTransaction


@admin.register(ItemDefinition)
class ItemDefinitionAdmin(admin.ModelAdmin):
    """The catalog. Untick "active" instead of deleting: owners keep what they have."""

    list_display = (
        "code", "name", "type", "subtype", "rarity", "asset", "is_starter", "requires_privilege", "active",
        "sort_order",
    )
    list_filter = ("type", "subtype", "rarity", "is_starter", "active")
    search_fields = ("code", "name")

    def has_delete_permission(self, request, obj=None):
        return False


class ReadOnlyAdmin(admin.ModelAdmin):
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(InventoryItem)
class InventoryItemAdmin(ReadOnlyAdmin):
    list_display = ("user", "item", "quantity", "expires_at", "updated_at")
    list_filter = ("item__type", "item__subtype")
    search_fields = ("=user__player_id", "item__code")


@admin.register(ItemTransaction)
class ItemTransactionAdmin(ReadOnlyAdmin):
    list_display = ("user", "item", "quantity", "quantity_after", "type", "source", "created_at")
    list_filter = ("type",)
    search_fields = ("=user__player_id", "item__code", "idempotency_key", "source")
    date_hierarchy = "created_at"


@admin.register(EquippedCosmetic)
class EquippedCosmeticAdmin(ReadOnlyAdmin):
    list_display = ("user", "slot", "item", "equipped_at")
    list_filter = ("slot",)
    search_fields = ("=user__player_id",)


class ItemAdjustmentForm(forms.ModelForm):
    class Meta:
        model = ItemAdjustment
        fields = ("user", "item", "quantity", "days", "reason")

    def clean(self):
        data = super().clean()
        quantity, days = data.get("quantity"), data.get("days")
        if quantity == 0:
            self.add_error("quantity", "Use a positive number to give, negative to take back.")
        elif quantity is not None and quantity < 0 and days:
            self.add_error("days", "Taking back removes permanent copies only.")
        elif data.get("item") is not None and data["item"].is_starter:
            self.add_error("item", "Everyone owns starter items.")
        return data


@admin.register(ItemAdjustment)
class ItemAdjustmentAdmin(admin.ModelAdmin):
    """Give or take back items. Saving posts one item entry; it can't be edited after."""

    form = ItemAdjustmentForm
    list_display = ("user", "item", "quantity", "days", "reason", "created_by", "created_at")
    search_fields = ("=user__player_id", "reason", "item__code")
    autocomplete_fields = ("user",)

    def has_change_permission(self, request, obj=None):
        return obj is None

    def has_delete_permission(self, request, obj=None):
        return False

    @transaction.atomic
    def save_model(self, request, obj, form, change):
        obj.created_by = request.user
        super().save_model(request, obj, form, change)
        key = f"admin:{obj.pk}"
        if obj.quantity > 0:
            changed = services.grant(
                obj.user, obj.item.code, obj.quantity, idempotency_key=key,
                type="admin_grant", source=key, days=obj.days,
            )
        else:
            changed = services.change(
                obj.user, obj.item, obj.quantity, type="admin_revoke", idempotency_key=key, source=key,
            )
        if changed.entry is not None:
            obj.entry = changed.entry
            obj.save(update_fields=["entry"])
