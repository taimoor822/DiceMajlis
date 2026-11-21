"""
Items: owning, granting, taking, expiring and wearing (equip). Views, rewards,
achievements and the admin all go through here, never through the models.

    grant(user, "dice_desert_gold", idempotency_key="achievement:first_win:<user>",
          type=ItemTransaction.Type.ACHIEVEMENT, source="achievement:first_win")
    equip(user, "dice", "dice_desert_gold")
    cosmetics_payload(user) -> {"dice": "dice_desert_gold", "board": "board_majlis", "frame": None}
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Iterable

from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone

from .models import (
    EquippedCosmetic,
    InventoryItem,
    ItemDefinition,
    ItemTransaction,
    ItemType,
    Slot,
)

# Slots that always show something: with nothing chosen, the first starter item.
# A frame may be empty.
REQUIRED_SLOTS = (Slot.DICE, Slot.BOARD)


class ItemError(Exception):
    def __init__(self, code: str, message: str = ""):
        super().__init__(message or code)
        self.code = code


@dataclass(frozen=True)
class Changed:
    entry: ItemTransaction | None  # None: nothing changed (already done, or already owned)
    created: bool


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------


def get_item(code: str) -> ItemDefinition:
    item = ItemDefinition.objects.filter(code=code).first()
    if item is None:
        raise ItemError("unknown_item", f"no item {code!r}")
    return item


def _valid(now: datetime) -> Q:
    return Q(quantity__gt=0) & (Q(expires_at__isnull=True) | Q(expires_at__gt=now))


def starter_items() -> list[ItemDefinition]:
    return list(ItemDefinition.objects.filter(is_starter=True))


def may_use(user, item: ItemDefinition) -> bool:
    """Owning isn't always enough: some items need a privilege (entitlements engine)."""
    if not item.requires_privilege:
        return True
    from entitlements import engine

    return engine.has(user, item.requires_privilege)


def owns(user, item: ItemDefinition, now: datetime | None = None) -> bool:
    if item.is_starter:
        return True
    now = now or timezone.now()
    return InventoryItem.objects.filter(_valid(now), user=user, item=item).exists()


def owned_items(user, now: datetime | None = None) -> list[dict[str, Any]]:
    """Everything the account owns now, one entry per item (copies added up)."""
    now = now or timezone.now()
    owned: dict[str, dict[str, Any]] = {}
    for item in starter_items():
        owned[item.code] = {"item": item, "quantity": 1, "expires_at": None, "starter": True}
    rows = InventoryItem.objects.filter(_valid(now), user=user).select_related("item")
    for row in rows:
        entry = owned.get(row.item.code)
        if entry is None:
            owned[row.item.code] = {
                "item": row.item, "quantity": row.quantity, "expires_at": row.expires_at, "starter": False,
            }
            continue
        if not row.item.stackable:
            # One copy is enough; the permanent one (or the latest expiry) wins.
            if entry["expires_at"] is not None and (row.expires_at is None or row.expires_at > entry["expires_at"]):
                entry["expires_at"] = row.expires_at
            continue
        entry["quantity"] += row.quantity
        if entry["expires_at"] is not None and (row.expires_at is None or row.expires_at > entry["expires_at"]):
            entry["expires_at"] = row.expires_at
    entries = list(owned.values())
    entries.sort(key=lambda e: (e["item"].type, e["item"].subtype, e["item"].sort_order, e["item"].code))
    return entries


def _slot_defaults() -> dict[str, ItemDefinition]:
    defaults = {}
    for item in ItemDefinition.objects.filter(is_starter=True, type=ItemType.COSMETIC).order_by("sort_order", "code"):
        if item.subtype in REQUIRED_SLOTS and item.subtype not in defaults:
            defaults[item.subtype] = item
    return defaults


def equipped_for_users(user_ids: Iterable, now: datetime | None = None) -> dict[Any, dict[str, ItemDefinition | None]]:
    """What each account wears, per slot (defaults filled in). One query for many accounts."""
    now = now or timezone.now()
    user_ids = list(user_ids)
    defaults = _slot_defaults()
    result = {uid: {slot: defaults.get(slot) for slot in Slot.values} for uid in user_ids}
    rows = list(EquippedCosmetic.objects.filter(user_id__in=user_ids).select_related("item", "user"))
    # Worn items must still be owned (an expired one falls back before the sweep runs).
    timed = {
        (uid, item_id)
        for uid, item_id in InventoryItem.objects.filter(
            _valid(now), user_id__in=user_ids, item_id__in=[r.item_id for r in rows]
        ).values_list("user_id", "item_id")
    }
    for row in rows:
        if row.item.is_starter or (row.user_id, row.item_id) in timed:
            if row.item.requires_privilege and not may_use(row.user, row.item):
                continue  # lost the privilege: back to the default look
            result[row.user_id][row.slot] = row.item
    return result


def equipped(user, now: datetime | None = None) -> dict[str, ItemDefinition | None]:
    return equipped_for_users([user.pk], now)[user.pk]


def _assets(worn: dict[str, ItemDefinition | None]) -> dict[str, str | None]:
    return {slot: item.asset if item else None for slot, item in worn.items()}


def cosmetics_payload(user, now: datetime | None = None) -> dict[str, str | None]:
    """What the app draws for this account: ``{slot: asset key or None}``."""
    return _assets(equipped(user, now))


def cosmetics_for_users(user_ids: Iterable, now: datetime | None = None) -> dict[Any, dict[str, str | None]]:
    return {uid: _assets(worn) for uid, worn in equipped_for_users(user_ids, now).items()}


def item_payload(item: ItemDefinition) -> dict[str, Any]:
    return {
        "code": item.code,
        "type": item.type,
        "slot": item.subtype or None,
        "name": item.name,
        "description": item.description,
        "rarity": item.rarity,
        "asset": item.asset,
    }


def inventory_payload(user, now: datetime | None = None) -> dict[str, Any]:
    now = now or timezone.now()
    worn = equipped(user, now)
    entries = owned_items(user, now)
    needed = {e["item"].requires_privilege for e in entries if e["item"].requires_privilege}
    names = {}
    if needed:
        from entitlements.models import Privilege

        names = dict(Privilege.objects.filter(code__in=needed).values_list("code", "name"))
    return {
        "items": [
            {
                **item_payload(entry["item"]),
                "quantity": entry["quantity"],
                "expires_at": entry["expires_at"].isoformat() if entry["expires_at"] else None,
                "starter": entry["starter"],
                # Owned, but it needs a privilege this account doesn't have.
                "locked": not may_use(user, entry["item"]),
                "requires_privilege": entry["item"].requires_privilege or None,
                "requires_privilege_name": names.get(entry["item"].requires_privilege),
            }
            for entry in entries
        ],
        "equipped": {slot: item.code if item else None for slot, item in worn.items()},
        "cosmetics": _assets(worn),
    }


# ---------------------------------------------------------------------------
# Changing what an account owns
# ---------------------------------------------------------------------------


def change(
    user,
    item: ItemDefinition,
    quantity: int,
    *,
    type: str,
    idempotency_key: str,
    source: str = "",
    expires_at: datetime | None = None,
    metadata: dict | None = None,
) -> Changed:
    """
    Add (+) or take (−) copies of ``item``, once per ``idempotency_key``.
    Cosmetics and other non-stackable items are owned once: giving one that is
    already owned for good changes nothing.
    """
    if not isinstance(quantity, int) or isinstance(quantity, bool) or quantity == 0:
        raise ValueError(f"bad quantity: {quantity!r}")
    if type not in ItemTransaction.Type.values:
        raise ValueError(f"unknown item entry type {type!r}")
    with transaction.atomic():
        earlier = ItemTransaction.objects.filter(user=user, idempotency_key=idempotency_key).first()
        if earlier is not None:
            return Changed(earlier, created=False)
        if quantity > 0 and not item.stackable:
            if item.is_starter or InventoryItem.objects.filter(
                user=user, item=item, expires_at__isnull=True, quantity__gt=0
            ).exists():
                return Changed(None, created=False)  # already theirs for good
            quantity = 1
        row, _ = InventoryItem.objects.select_for_update().get_or_create(
            user=user, item=item, expires_at=expires_at
        )
        if quantity > 0 and not item.stackable and row.quantity >= 1:
            return Changed(None, created=False)  # this copy is already there
        if row.quantity + quantity < 0:
            raise ItemError("not_enough", f"only {row.quantity} {item.code}")
        try:
            with transaction.atomic():
                entry = ItemTransaction.objects.create(
                    user=user,
                    item=item,
                    quantity=quantity,
                    quantity_before=row.quantity,
                    quantity_after=row.quantity + quantity,
                    expires_at=expires_at,
                    type=type,
                    source=source,
                    idempotency_key=idempotency_key,
                    metadata=metadata or {},
                )
        except IntegrityError:  # the same key won a race on another connection
            return Changed(ItemTransaction.objects.get(user=user, idempotency_key=idempotency_key), created=False)
        row.quantity = entry.quantity_after
        row.save(update_fields=["quantity", "updated_at"])
        if row.quantity == 0:
            _unequip_if_gone(user, item)
        from entitlements import engine

        engine.forget(user)  # items can give privileges
        transaction.on_commit(lambda: _push(user, "inventory_changed"))
    return Changed(entry, created=True)


def grant(
    user,
    code: str,
    quantity: int = 1,
    *,
    idempotency_key: str,
    type: str = ItemTransaction.Type.REWARD,
    source: str = "",
    days: int | None = None,
    now: datetime | None = None,
) -> Changed:
    """Give ``quantity`` of item ``code`` (for ``days`` days, or for good)."""
    if quantity <= 0:
        raise ValueError("grant a positive quantity")
    item = get_item(code)
    expires_at = (now or timezone.now()) + timedelta(days=days) if days else None
    return change(
        user, item, quantity, type=type, idempotency_key=idempotency_key, source=source, expires_at=expires_at
    )


def expire_due(now: datetime | None = None, limit: int = 200) -> int:
    """The sweep: copies whose time is up are taken back (and taken off). Returns how many rows."""
    now = now or timezone.now()
    due = list(
        InventoryItem.objects.filter(quantity__gt=0, expires_at__lte=now)
        .select_related("item", "user")[:limit]
    )
    for row in due:
        change(
            row.user,
            row.item,
            -row.quantity,
            type=ItemTransaction.Type.EXPIRED,
            idempotency_key=f"expired:{row.pk}:{row.expires_at.isoformat()}",
            source="expired",
            expires_at=row.expires_at,
        )
    return len(due)


# ---------------------------------------------------------------------------
# Wearing
# ---------------------------------------------------------------------------


def equip(user, slot: str, code: str | None, now: datetime | None = None) -> dict[str, Any]:
    """Wear item ``code`` in ``slot`` (None = back to the default). Returns the new inventory view."""
    if slot not in Slot.values:
        raise ItemError("unknown_slot", f"no slot {slot!r}")
    with transaction.atomic():
        if code is None:
            EquippedCosmetic.objects.filter(user=user, slot=slot).delete()
        else:
            item = get_item(code)
            if item.type != ItemType.COSMETIC or item.subtype != slot:
                raise ItemError("wrong_slot", f"{code} isn't worn as {slot}")
            if not owns(user, item, now):
                raise ItemError("not_owned", f"you don't own {code}")
            if not may_use(user, item):
                raise ItemError("needs_privilege", f"{code} needs {item.requires_privilege}")
            EquippedCosmetic.objects.update_or_create(user=user, slot=slot, defaults={"item": item})
        transaction.on_commit(lambda: _push_cosmetics(user))
    return inventory_payload(user, now)


def _unequip_if_gone(user, item: ItemDefinition) -> None:
    if item.type != ItemType.COSMETIC or owns(user, item):
        return
    if EquippedCosmetic.objects.filter(user=user, slot=item.subtype, item=item).delete()[0]:
        transaction.on_commit(lambda: _push_cosmetics(user))


def _push(user, kind: str, data: dict | None = None) -> None:
    from realtime.publish import publish

    publish(f"user/{user.player_id}", kind, data or {})


def _push_cosmetics(user) -> None:
    _push(user, "cosmetics_changed", {"cosmetics": cosmetics_payload(user)})
