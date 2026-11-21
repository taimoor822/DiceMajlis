"""
Rewards API. The app only asks to claim; the server decides what is given.

    GET  /api/rewards/daily/          -> status (day in the cycle, claimed today, the days, countdown)
    POST /api/rewards/daily/claim/    -> {"claimed": {day, gold, diamond, xp, items}, "balances", "daily"};
                                         409 already_claimed / daily_reward_unavailable
    GET  /api/rewards/history/?before=ID -> {"claims": [...], "next": ID | null}  (newest first)
"""

import uuid

from django.db.models import Q

from rest_framework import status as http
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from wallet import services as wallet

from . import daily
from .engine import bundle_payload
from .models import RewardClaim

PAGE_SIZE = 30


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def daily_status(request):
    return Response(daily.status(request.user))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def daily_claim(request):
    try:
        result = daily.claim(request.user)
    except daily.AlreadyClaimed:
        return Response(
            {"error": "Today's reward is already claimed", "code": "already_claimed"},
            status=http.HTTP_409_CONFLICT,
        )
    except daily.NotAvailable:
        return Response(
            {"error": "There is no daily reward right now", "code": "daily_reward_unavailable"},
            status=http.HTTP_409_CONFLICT,
        )
    claim = result.claim
    return Response(
        {
            "claimed": {"day": claim.streak_day, **bundle_payload(claim.bundle)},
            "balances": wallet.balances(request.user),
            "daily": daily.status(request.user),
        }
    )


def _what_for(claim: RewardClaim) -> dict:
    """What a claim was for, for the app to name it: the daily day, or the achievement."""
    if claim.kind == daily.KIND:
        return {"day": claim.streak_day}
    if claim.kind == "achievement" and claim.source.startswith("achievement:"):
        from progress.models import Achievement

        _, code, threshold = (claim.source.split(":") + ["", ""])[:3]
        achievement = Achievement.objects.filter(code=code).first()
        return {
            "achievement": achievement.name if achievement else code,
            "threshold": int(threshold) if threshold.isdigit() else None,
        }
    return {}


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def history(request):
    """Every reward you got, newest first, a page at a time."""
    claims = RewardClaim.objects.filter(user=request.user).order_by("-created_at", "-id")
    before = request.query_params.get("before")
    if before:
        last = claims.filter(id=before).first() if _is_uuid(before) else None
        if last is None:
            return Response({"error": "Unknown page", "code": "invalid_input"}, status=http.HTTP_400_BAD_REQUEST)
        claims = claims.filter(Q(created_at__lt=last.created_at) | Q(created_at=last.created_at, id__lt=last.id))
    page = list(claims[: PAGE_SIZE + 1])
    more = len(page) > PAGE_SIZE
    page = page[:PAGE_SIZE]
    return Response(
        {
            "claims": [
                {
                    "id": str(c.id),
                    "kind": c.kind,
                    **_what_for(c),
                    "reward": bundle_payload(c.bundle),
                    "created_at": c.created_at.isoformat(),
                }
                for c in page
            ],
            "next": str(page[-1].id) if more else None,
        }
    )


def _is_uuid(value: str) -> bool:
    try:
        uuid.UUID(value)
    except ValueError:
        return False
    return True
