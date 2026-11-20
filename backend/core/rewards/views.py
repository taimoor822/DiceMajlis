"""
Daily reward API. The app only asks to claim; the server decides what is given.

    GET  /api/rewards/daily/        -> status (day in the cycle, claimed today, the 7 days, countdown)
    POST /api/rewards/daily/claim/  -> {"claimed": {day, gold, diamond}, "balances", "daily"}; 409 already_claimed
"""

from rest_framework import status as http
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from wallet import services as wallet

from . import daily


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
    claim = result.claim
    return Response(
        {
            "claimed": {
                "day": claim.streak_day,
                "gold": claim.bundle.get("gold", 0),
                "diamond": claim.bundle.get("diamond", 0),
            },
            "balances": wallet.balances(request.user),
            "daily": daily.status(request.user),
        }
    )
