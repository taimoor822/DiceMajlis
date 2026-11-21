"""
One item system (ROYAL_VIP_ECONOMY §4): every kind of item (cosmetics today;
gifts, magic cards, props, tickets and chests later) is an ``ItemDefinition``.
Ownership is ``InventoryItem`` and every change is an append-only
``ItemTransaction`` (like the wallet ledger). Cosmetics are worn through
``EquippedCosmetic``, one per slot. Change these only through items.services.
"""

import uuid

from django.conf import settings
from django.db import models
from django.db.models import F, Q


class ItemType(models.TextChoices):
    COSMETIC = "cosmetic", "Cosmetic"
    GIFT = "gift", "Gift"
    MAGIC_CARD = "magic_card", "Magic card"
    PROP = "prop", "Prop"
    RECHARGE_TICKET = "recharge_ticket", "Recharge ticket"
    CHEST = "chest", "Chest"


class Slot(models.TextChoices):
    """Where a cosmetic is worn (its subtype). More slots come with later phases."""

    DICE = "dice", "Dice"
    BOARD = "board", "Board"
    FRAME = "frame", "Profile frame"


class Rarity(models.TextChoices):
    COMMON = "common", "Common"
    RARE = "rare", "Rare"
    EPIC = "epic", "Epic"
    LEGENDARY = "legendary", "Legendary"


class ItemDefinition(models.Model):
    """The catalog, managed in the admin."""

    code = models.SlugField(max_length=64, unique=True)
    type = models.CharField(max_length=20, choices=ItemType.choices, default=ItemType.COSMETIC)
    # For cosmetics: the slot it is worn in.
    subtype = models.CharField(max_length=20, choices=Slot.choices, blank=True, default="")
    name = models.CharField(max_length=60)
    description = models.CharField(max_length=200, blank=True, default="")
    rarity = models.CharField(max_length=12, choices=Rarity.choices, default=Rarity.COMMON)
    # The look the app draws for it (a key it knows; unknown keys get a plain look).
    asset = models.CharField(max_length=64)
    # Extra settings for the look or the effect (later: animations, sounds ...).
    effect = models.JSONField(default=dict, blank=True)
    # Several of the same can be owned (gifts, cards). Cosmetics are not stackable.
    stackable = models.BooleanField(default=False)
    # Owned by every account, from the start (and can't be lost).
    is_starter = models.BooleanField(default=False)
    # Hidden from new grants and lists, but kept for whoever owns it.
    active = models.BooleanField(default=True)
    sort_order = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["type", "subtype", "sort_order", "code"]
        constraints = [
            models.CheckConstraint(
                condition=~Q(type="cosmetic") | ~Q(subtype=""), name="cosmetic_has_a_slot"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.name} ({self.code})"


class InventoryItem(models.Model):
    """What an account owns. Copies with a different expiry are separate rows."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="inventory", on_delete=models.CASCADE)
    item = models.ForeignKey(ItemDefinition, related_name="+", on_delete=models.PROTECT)
    quantity = models.PositiveIntegerField(default=0)
    # NULL = never expires.
    expires_at = models.DateTimeField(null=True, blank=True, db_index=True)
    acquired_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["item__sort_order", "expires_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "item"], condition=Q(expires_at__isnull=True), name="one_row_per_permanent_item"
            ),
            models.UniqueConstraint(
                fields=["user", "item", "expires_at"],
                condition=Q(expires_at__isnull=False),
                name="one_row_per_item_expiry",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.quantity} × {self.item.code}"


class ItemIsAppendOnly(Exception):
    pass


class ItemTransaction(models.Model):
    """One change of what an account owns (append-only)."""

    class Type(models.TextChoices):
        REWARD = "reward", "Reward"
        ACHIEVEMENT = "achievement", "Achievement"
        ADMIN_GRANT = "admin_grant", "Admin grant"
        ADMIN_REVOKE = "admin_revoke", "Admin revoke"
        PURCHASE = "purchase", "Purchase"
        EXPIRED = "expired", "Expired"
        USED = "used", "Used"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="item_transactions", on_delete=models.CASCADE)
    item = models.ForeignKey(ItemDefinition, related_name="+", on_delete=models.PROTECT)
    quantity = models.IntegerField(help_text="+ added, − taken")
    quantity_before = models.PositiveIntegerField()
    quantity_after = models.PositiveIntegerField()
    # Which copies (their expiry), if they expire.
    expires_at = models.DateTimeField(null=True, blank=True)
    type = models.CharField(max_length=20, choices=Type.choices)
    source = models.CharField(max_length=100, blank=True, default="")
    idempotency_key = models.CharField(max_length=120)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "created_at"], name="item_tx_user_idx")]
        constraints = [
            models.UniqueConstraint(fields=["user", "idempotency_key"], name="one_item_entry_per_key"),
            models.CheckConstraint(condition=~Q(quantity=0), name="item_quantity_not_zero"),
            models.CheckConstraint(
                condition=Q(quantity_after=F("quantity_before") + F("quantity")),
                name="item_quantity_after_adds_up",
            ),
        ]

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise ItemIsAppendOnly("Item entries can't be changed; post another entry.")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ItemIsAppendOnly("Item entries can't be deleted.")

    def __str__(self) -> str:
        return f"{self.quantity:+} {self.item.code} ({self.type})"


class EquippedCosmetic(models.Model):
    """The cosmetic worn in one slot. No row = the slot's default (items.services)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="equipped_cosmetics", on_delete=models.CASCADE)
    slot = models.CharField(max_length=20, choices=Slot.choices)
    item = models.ForeignKey(ItemDefinition, related_name="+", on_delete=models.PROTECT)
    equipped_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user", "slot"], name="one_cosmetic_per_slot")]

    def __str__(self) -> str:
        return f"{self.slot}: {self.item.code}"


class ItemAdjustment(models.Model):
    """
    A grant or take-back by the team, made in the Django admin. Saving it posts
    one item entry (keyed by this row, so it can never post twice).
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="item_adjustments", on_delete=models.PROTECT)
    item = models.ForeignKey(ItemDefinition, related_name="+", on_delete=models.PROTECT)
    quantity = models.IntegerField(default=1, help_text="+ to give, − to take back")
    # Time-limited copies: how many days they last (empty = forever).
    days = models.PositiveIntegerField(null=True, blank=True)
    reason = models.CharField(max_length=200)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="+", null=True, on_delete=models.SET_NULL)
    entry = models.OneToOneField(
        ItemTransaction, null=True, blank=True, related_name="adjustment", on_delete=models.PROTECT
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"{self.quantity:+} {self.item.code} for {self.user} ({self.reason})"
