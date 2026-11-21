"""
Achievements API (read only: they unlock on the server from real progress).

    GET /api/me/achievements/ -> {"achievements": [...], "unlocked_tiers": n,
                                  "total_tiers": n, "hidden_left": n}
"""

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from . import services


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_achievements(request):
    return Response(services.achievements_payload(request.user))
