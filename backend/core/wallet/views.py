"""
Wallet API (read only: balances change through services.post, never from the app).

    GET /api/wallet/                        -> {"balances": {"gold": n, "diamond": n}}
    GET /api/wallet/transactions/?before=ID -> {"transactions": [...], "next": ID | null}
"""

import uuid

from django.db.models import Q
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from . import services
from .models import WalletTransaction

PAGE_SIZE = 30


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def wallet(request):
    return Response({"balances": services.balances(request.user)})


def entry_payload(entry: WalletTransaction) -> dict:
    return {
        "id": str(entry.id),
        "reference": entry.reference,
        "currency": entry.account.currency,
        "amount": entry.amount,
        "balance_after": entry.balance_after,
        "type": entry.type,
        "created_at": entry.created_at.isoformat(),
    }


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def transactions(request):
    """Newest first, a page at a time. ``before`` is the last id of the previous page."""
    entries = (
        WalletTransaction.objects.filter(account__user=request.user)
        .select_related("account")
        .order_by("-created_at", "-id")
    )
    before = request.query_params.get("before")
    if before:
        last = entries.filter(id=before).first() if _is_uuid(before) else None
        if last is None:
            return Response({"error": "Unknown page", "code": "invalid_input"}, status=400)
        entries = entries.filter(
            Q(created_at__lt=last.created_at) | Q(created_at=last.created_at, id__lt=last.id)
        )
    page = list(entries[: PAGE_SIZE + 1])
    more = len(page) > PAGE_SIZE
    page = page[:PAGE_SIZE]
    return Response(
        {
            "transactions": [entry_payload(e) for e in page],
            "next": str(page[-1].id) if more else None,
        }
    )


def _is_uuid(value: str) -> bool:
    try:
        uuid.UUID(value)
    except ValueError:
        return False
    return True
