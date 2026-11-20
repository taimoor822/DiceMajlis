"""
The wallet: one account per player per currency, and an append-only ledger.

Balances change only through wallet.services.post(). Every change is one
WalletTransaction row; rows are never edited or deleted (mistakes are fixed by a
reversal). See SOCIAL_MAJLIS.md §5.
"""

import uuid

from django.conf import settings
from django.db import models
from django.db.models import F, Q


class Currency(models.TextChoices):
    GOLD = "gold", "Gold"  # everyday
    DIAMOND = "diamond", "Diamonds"  # premium


class TransactionType(models.TextChoices):
    REWARD_DAILY = "reward_daily", "Daily reward"
    ADMIN_GRANT = "admin_grant", "Admin grant"
    ADMIN_REVOKE = "admin_revoke", "Admin revoke"
    REVERSAL = "reversal", "Reversal"
    # Later: gift_send, game_reward, reward_achievement, reward_event, purchase, ...


class WalletAccount(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, related_name="wallet_accounts", on_delete=models.CASCADE
    )
    currency = models.CharField(max_length=16, choices=Currency.choices)
    # Cached sum of the account's transactions (checked by `manage.py audit_wallets`).
    balance = models.BigIntegerField(default=0)
    # Number of the latest entry: entries are numbered 1, 2, 3 ... per account.
    last_sequence = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "currency"], name="one_wallet_account_per_currency"),
            models.CheckConstraint(condition=Q(balance__gte=0), name="wallet_balance_not_negative"),
        ]

    def __str__(self) -> str:
        return f"{self.user} {self.currency}: {self.balance}"


class LedgerIsAppendOnly(Exception):
    pass


class WalletTransaction(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    account = models.ForeignKey(WalletAccount, related_name="transactions", on_delete=models.PROTECT)
    # 1, 2, 3 ... within the account: a gap or a repeat would show up in the audit.
    sequence = models.PositiveIntegerField()
    amount = models.BigIntegerField(help_text="+ added, − taken")
    balance_before = models.BigIntegerField()
    balance_after = models.BigIntegerField()
    type = models.CharField(max_length=32, choices=TransactionType.choices)
    # What exactly it was, e.g. "daily_login:day3" or "admin:<adjustment id>".
    source = models.CharField(max_length=100, blank=True, default="")
    reference_type = models.CharField(max_length=40, blank=True, default="")
    reference_id = models.CharField(max_length=64, blank=True, default="")
    # The same key twice = the same entry (never two).
    idempotency_key = models.CharField(max_length=120)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["account", "created_at"])]
        constraints = [
            models.UniqueConstraint(fields=["account", "idempotency_key"], name="one_entry_per_idempotency_key"),
            models.UniqueConstraint(fields=["account", "sequence"], name="one_entry_per_sequence"),
            models.CheckConstraint(condition=~Q(amount=0), name="wallet_amount_not_zero"),
            models.CheckConstraint(condition=Q(balance_after__gte=0), name="wallet_balance_after_not_negative"),
            models.CheckConstraint(
                condition=Q(balance_after=F("balance_before") + F("amount")),
                name="wallet_balance_after_adds_up",
            ),
        ]

    @property
    def reference(self) -> str:
        """Short id for support: TXN-xxxxxxxx."""
        return f"TXN-{str(self.id)[:8].upper()}"

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise LedgerIsAppendOnly("Ledger entries can't be changed; post a reversal instead.")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise LedgerIsAppendOnly("Ledger entries can't be deleted; post a reversal instead.")

    def __str__(self) -> str:
        return f"{self.reference} {self.amount:+} {self.account.currency}"


class WalletAdjustment(models.Model):
    """
    A grant or correction by the team, made in the Django admin. Saving it posts
    one ledger entry (keyed by this row, so it can never post twice).
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, related_name="wallet_adjustments", on_delete=models.PROTECT
    )
    currency = models.CharField(max_length=16, choices=Currency.choices)
    amount = models.BigIntegerField(help_text="+ to give, − to take back")
    reason = models.CharField(max_length=200)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, related_name="+", null=True, on_delete=models.SET_NULL
    )
    transaction = models.OneToOneField(
        WalletTransaction, null=True, blank=True, related_name="adjustment", on_delete=models.PROTECT
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"{self.amount:+} {self.currency} for {self.user} ({self.reason})"
