"""
Entitlements API: what your account may do (the server re-checks every action).

    GET /api/me/entitlements/ -> {"entitlements": {code: value}, "privileges": [...]}
"""

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from . import engine


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_entitlements(request):
    return Response(engine.payload(request.user))
