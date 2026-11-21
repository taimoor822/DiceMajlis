"""
The one reward engine (ROYAL_VIP_ECONOMY §5): every "you got something" goes
through grant(). One DB transaction writes the claim and every ledger entry
(wallet, XP, items), or nothing. The idempotency key makes double claims
impossible.

A bundle (also what admin ``RewardBundle``s hold):

    {"gold": 500, "diamond": 5, "xp": 50,
     "items": [{"code": "dice_pearl", "quantity": 1, "days": 7}]}

Every part is optional, but a bundle must give something. Items without
``days`` are kept for good.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from django.db import IntegrityError, transaction

from wallet import services as wallet
from wallet.models import Currency, TransactionType

from .models import RewardClaim

# Which wallet entry type each kind of reward writes.
LEDGER_TYPES = {
    "daily_login": TransactionType.REWARD_DAILY,
    "achievement": TransactionType.REWARD_ACHIEVEMENT,
}


@dataclass(frozen=True)
class Granted:
    claim: RewardClaim
    created: bool  # False: this reward was already given (same key)


def _count(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def check_bundle(bundle: dict) -> dict[str, Any]:
    """The bundle, checked and tidied (zero amounts dropped). ValueError when it's wrong."""
    from items.models import ItemDefinition

    if not isinstance(bundle, dict) or not bundle:
        raise ValueError("empty reward bundle")
    clean: dict[str, Any] = {}
    for key, value in bundle.items():
        if key in Currency.values or key == "xp":
            if not _count(value) or value < 0:
                raise ValueError(f"bad amount for {key}: {value!r}")
            if value:
                clean[key] = value
        elif key == "items":
            if not isinstance(value, list):
                raise ValueError("items must be a list")
            items = []
            for entry in value:
                if not isinstance(entry, dict) or not set(entry) <= {"code", "quantity", "days"}:
                    raise ValueError(f"bad item entry {entry!r}")
                code, quantity, days = entry.get("code"), entry.get("quantity", 1), entry.get("days")
                if not isinstance(code, str) or not ItemDefinition.objects.filter(code=code, active=True).exists():
                    raise ValueError(f"unknown item {code!r}")
                if not _count(quantity) or quantity < 1:
                    raise ValueError(f"bad quantity for {code}: {quantity!r}")
                if days is not None and (not _count(days) or days < 1):
                    raise ValueError(f"bad days for {code}: {days!r}")
                items.append({"code": code, "quantity": quantity, **({"days": days} if days else {})})
            if items:
                clean["items"] = items
        else:
            raise ValueError(f"unknown reward {key!r}")
    if not clean:
        raise ValueError("a reward must give something")
    return clean


def grant(
    user,
    bundle: dict,
    *,
    kind: str,
    idempotency_key: str,
    reward_day=None,
    streak_day: int | None = None,
    source: str = "",
) -> Granted:
    from items import services as items
    from items.models import ItemTransaction
    from profiles.xp import add_xp

    bundle = check_bundle(bundle)
    ledger_type = LEDGER_TYPES[kind]
    item_type = ItemTransaction.Type.ACHIEVEMENT if kind == "achievement" else ItemTransaction.Type.REWARD
    with transaction.atomic():
        earlier = RewardClaim.objects.filter(idempotency_key=idempotency_key).first()
        if earlier is not None:
            return Granted(earlier, created=False)
        try:
            with transaction.atomic():
                claim = RewardClaim.objects.create(
                    user=user,
                    kind=kind,
                    reward_day=reward_day,
                    streak_day=streak_day,
                    bundle=bundle,
                    source=source,
                    idempotency_key=idempotency_key,
                )
        except IntegrityError:  # the same claim won a race on another connection
            return Granted(RewardClaim.objects.get(idempotency_key=idempotency_key), created=False)
        for currency in Currency.values:
            amount = bundle.get(currency)
            if amount:
                wallet.post(
                    user,
                    currency,
                    amount,
                    ledger_type,
                    f"{idempotency_key}:{currency}",
                    source=source or kind,
                    reference_type="reward_claim",
                    reference_id=str(claim.id),
                )
        if bundle.get("xp"):
            add_xp(
                user,
                bundle["xp"],
                reason="reward",
                idempotency_key=f"{idempotency_key}:xp",
                reference_type="reward_claim",
                reference_id=str(claim.id),
            )
        for index, entry in enumerate(bundle.get("items", [])):
            items.grant(
                user,
                entry["code"],
                entry["quantity"],
                idempotency_key=f"{idempotency_key}:item:{index}",
                type=item_type,
                source=source or kind,
                days=entry.get("days"),
            )
        return Granted(claim, created=True)


def bundle_payload(bundle: dict) -> dict[str, Any]:
    """A bundle as the app shows it: amounts, XP and the items with their names and looks."""
    from items.models import ItemDefinition

    entries = bundle.get("items", [])
    found = {i.code: i for i in ItemDefinition.objects.filter(code__in=[e["code"] for e in entries])}
    return {
        **{currency: bundle.get(currency, 0) for currency in Currency.values},
        "xp": bundle.get("xp", 0),
        "items": [
            {
                "code": entry["code"],
                "name": found[entry["code"]].name if entry["code"] in found else entry["code"],
                "asset": found[entry["code"]].asset if entry["code"] in found else "",
                "slot": (found[entry["code"]].subtype or None) if entry["code"] in found else None,
                "rarity": found[entry["code"]].rarity if entry["code"] in found else "common",
                "quantity": entry.get("quantity", 1),
                "days": entry.get("days"),
            }
            for entry in entries
        ],
    }
