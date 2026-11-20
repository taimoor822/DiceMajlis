"""
The only code that changes balances (rule: SOCIAL_MAJLIS §5).

    post(user, currency, amount, type, idempotency_key, ...)  -> WalletTransaction
    reverse(transaction, reason, idempotency_key)            -> WalletTransaction
    balances(user)                                            -> {"gold": n, "diamond": n}

post() runs in one DB transaction: lock the account row, check the balance,
write one ledger row, update the cached balance. The same idempotency key twice
returns the first entry instead of posting again.
"""

from __future__ import annotations

from django.db import IntegrityError, transaction

from .models import Currency, TransactionType, WalletAccount, WalletTransaction


class WalletError(Exception):
    code = "wallet_error"


class InsufficientFunds(WalletError):
    code = "insufficient_funds"


class IdempotencyConflict(WalletError):
    """The key was used before for a different entry: a bug in the caller."""

    code = "idempotency_conflict"


def _locked_account(user, currency: str) -> WalletAccount:
    WalletAccount.objects.get_or_create(user=user, currency=currency)
    return WalletAccount.objects.select_for_update().get(user=user, currency=currency)


def post(
    user,
    currency: str,
    amount: int,
    type: str,
    idempotency_key: str,
    *,
    source: str = "",
    reference_type: str = "",
    reference_id: str = "",
    metadata: dict | None = None,
) -> WalletTransaction:
    if currency not in Currency.values:
        raise ValueError(f"unknown currency {currency!r}")
    if type not in TransactionType.values:
        raise ValueError(f"unknown transaction type {type!r}")
    if not isinstance(amount, int) or isinstance(amount, bool) or amount == 0:
        raise ValueError("amount must be a non-zero whole number")
    if not idempotency_key:
        raise ValueError("an idempotency key is required")

    with transaction.atomic():
        account = _locked_account(user, currency)
        earlier = account.transactions.filter(idempotency_key=idempotency_key).first()
        if earlier is not None:
            if earlier.amount != amount or earlier.type != type:
                raise IdempotencyConflict(f"key {idempotency_key!r} was used for another entry")
            return earlier

        after = account.balance + amount
        if after < 0:
            raise InsufficientFunds(f"needs {-amount} {currency}, has {account.balance}")
        try:
            with transaction.atomic():
                entry = WalletTransaction.objects.create(
                    account=account,
                    sequence=account.last_sequence + 1,
                    amount=amount,
                    balance_before=account.balance,
                    balance_after=after,
                    type=type,
                    source=source,
                    reference_type=reference_type,
                    reference_id=reference_id,
                    idempotency_key=idempotency_key,
                    metadata=metadata or {},
                )
        except IntegrityError:  # the same key won a race on another connection
            return account.transactions.get(idempotency_key=idempotency_key)
        WalletAccount.objects.filter(pk=account.pk).update(
            balance=after, last_sequence=entry.sequence
        )
        return entry


def reverse(entry: WalletTransaction, reason: str, idempotency_key: str) -> WalletTransaction:
    """Undo an entry with a new one of the opposite amount (rows are never edited)."""
    return post(
        entry.account.user,
        entry.account.currency,
        -entry.amount,
        TransactionType.REVERSAL,
        idempotency_key,
        source=f"reversal:{entry.reference}",
        reference_type="wallet_transaction",
        reference_id=str(entry.id),
        metadata={"reason": reason},
    )


def balances(user) -> dict[str, int]:
    """Every currency, 0 when the account doesn't exist yet."""
    result = {currency: 0 for currency in Currency.values}
    for currency, balance in WalletAccount.objects.filter(user=user).values_list("currency", "balance"):
        result[currency] = balance
    return result


def audit() -> list[str]:
    """
    Problems found in the ledger (empty list = all good): entries are numbered
    without gaps, each starts where the one before it ended, and the account's
    balance equals the sum of its entries.
    """
    problems: list[str] = []
    for account in WalletAccount.objects.select_related("user").iterator():
        running, expected = 0, 1
        for entry in account.transactions.order_by("sequence").iterator():
            if entry.sequence != expected:
                problems.append(f"{account}: entry {expected} is missing (found {entry.sequence})")
            if entry.balance_before != running:
                problems.append(
                    f"{account}: {entry.reference} starts at {entry.balance_before}, expected {running}"
                )
            running, expected = entry.balance_after, entry.sequence + 1
        if running != account.balance:
            problems.append(f"{account}: balance {account.balance}, ledger says {running}")
        if expected - 1 != account.last_sequence:
            problems.append(f"{account}: {expected - 1} entries, account says {account.last_sequence}")
    return problems
