from django import forms
from django.contrib import admin
from django.db import transaction

from . import services
from .models import TransactionType, WalletAccount, WalletAdjustment, WalletTransaction


class ReadOnlyAdmin(admin.ModelAdmin):
    """The ledger is append-only: nothing here can be added, changed or deleted by hand."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(WalletAccount)
class WalletAccountAdmin(ReadOnlyAdmin):
    list_display = ("user", "currency", "balance", "last_sequence", "updated_at")
    list_filter = ("currency",)
    search_fields = ("=user__player_id", "user__email")


@admin.register(WalletTransaction)
class WalletTransactionAdmin(ReadOnlyAdmin):
    list_display = ("reference", "account", "amount", "balance_after", "type", "source", "created_at")
    list_filter = ("type", "account__currency")
    search_fields = ("=account__user__player_id", "idempotency_key", "source")
    date_hierarchy = "created_at"


class WalletAdjustmentForm(forms.ModelForm):
    class Meta:
        model = WalletAdjustment
        fields = ("user", "currency", "amount", "reason")

    def clean(self):
        data = super().clean()
        user, currency, amount = data.get("user"), data.get("currency"), data.get("amount")
        if amount == 0:
            self.add_error("amount", "Use a positive amount to give, negative to take back.")
        elif user is not None and currency and amount is not None and amount < 0:
            balance = services.balances(user)[currency]
            if balance + amount < 0:
                self.add_error("amount", f"The player only has {balance}.")
        return data


@admin.register(WalletAdjustment)
class WalletAdjustmentAdmin(admin.ModelAdmin):
    """Give or take back currency. Saving posts one ledger entry; it can't be edited after."""

    form = WalletAdjustmentForm
    list_display = ("user", "currency", "amount", "reason", "created_by", "created_at")
    list_filter = ("currency",)
    search_fields = ("=user__player_id", "reason")
    autocomplete_fields = ("user",)

    def has_change_permission(self, request, obj=None):
        return obj is None  # the add form only

    def has_delete_permission(self, request, obj=None):
        return False

    @transaction.atomic
    def save_model(self, request, obj, form, change):
        kind = TransactionType.ADMIN_GRANT if obj.amount > 0 else TransactionType.ADMIN_REVOKE
        obj.created_by = request.user
        super().save_model(request, obj, form, change)
        obj.transaction = services.post(
            obj.user,
            obj.currency,
            obj.amount,
            kind,
            f"admin:{obj.pk}",
            source=f"admin:{obj.pk}",
            reference_type="wallet_adjustment",
            reference_id=str(obj.pk),
            metadata={"reason": obj.reason, "by": request.user.get_username()},
        )
        obj.save(update_fields=["transaction"])
