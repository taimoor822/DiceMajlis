"""
The one reward engine (ROYAL_VIP_ECONOMY §5): every "you got something" goes
through grant(). One DB transaction writes the claim and every ledger entry, or
nothing. The idempotency key makes double claims impossible.

Today a bundle holds currencies ({"gold": 100, "diamond": 5}). Items and EXP join
in Phase 2 (S6b) without changing callers.
"""

from __future__ import annotations

from dataclasses import dataclass

from django.db import IntegrityError, transaction

from wallet import services as wallet
from wallet.models import Currency, TransactionType

from .models import RewardClaim

# Which ledger entry type each kind of reward writes.
LEDGER_TYPES = {
    "daily_login": TransactionType.REWARD_DAILY,
}


@dataclass(frozen=True)
class Granted:
    claim: RewardClaim
    created: bool  # False: this reward was already given (same key)


def check_bundle(bundle: dict) -> dict[str, int]:
    if not bundle:
        raise ValueError("empty reward bundle")
    for key, amount in bundle.items():
        if key not in Currency.values:
            raise ValueError(f"unknown reward {key!r}")
        if not isinstance(amount, int) or isinstance(amount, bool) or amount < 0:
            raise ValueError(f"bad amount for {key}: {amount!r}")
    if not any(bundle.values()):
        raise ValueError("a reward must give something")
    return dict(bundle)


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
    bundle = check_bundle(bundle)
    ledger_type = LEDGER_TYPES[kind]
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
                    idempotency_key=idempotency_key,
                )
        except IntegrityError:  # the same claim won a race on another connection
            return Granted(RewardClaim.objects.get(idempotency_key=idempotency_key), created=False)
        for currency, amount in bundle.items():
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
        return Granted(claim, created=True)
