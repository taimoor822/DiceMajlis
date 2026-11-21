"""
Statistics API (read only; real online games against people only).

    GET /api/me/stats/ -> {"total": {...}, "game_types": {"ludo": {...}}, "recent": [...]}
"""

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from . import services


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_stats(request):
    return Response(services.stats_payload(request.user))
