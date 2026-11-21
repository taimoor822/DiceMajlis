"""
Items API (what you own and wear; never what anything costs).

    GET  /api/me/items/        -> {"items": [...], "equipped": {slot: code}, "cosmetics": {slot: asset}}
    POST /api/me/items/equip/  {"slot": "dice", "item": "dice_pearl" | null} -> the same
"""

from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.api_errors import invalid_input_response

from . import services
from .models import Slot


class EquipInput(serializers.Serializer):
    slot = serializers.ChoiceField(choices=Slot.values)
    item = serializers.SlugField(max_length=64, allow_null=True)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def my_items(request):
    return Response(services.inventory_payload(request.user))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def equip(request):
    form = EquipInput(data=request.data)
    if not form.is_valid():
        return invalid_input_response(form)
    try:
        payload = services.equip(request.user, form.validated_data["slot"], form.validated_data["item"])
    except services.ItemError as e:
        code = {
            "unknown_item": status.HTTP_404_NOT_FOUND,
            "needs_privilege": status.HTTP_403_FORBIDDEN,
        }.get(e.code, status.HTTP_409_CONFLICT)
        return Response({"error": str(e), "code": e.code}, status=code)
    return Response(payload)
