"""
Profile API.

    GET   /api/profile/options/  -> what a profile may hold (avatars, languages, name length)
    PATCH /api/me/profile/       -> change your own profile; returns your account
"""

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from accounts.views import account_payload
from core.api_errors import invalid_input_response

from . import choices, services
from .serializers import ProfileUpdateInput


@api_view(["GET"])
def profile_options(request):
    return Response(
        {
            "avatars": list(choices.AVATARS),
            "languages": list(choices.LANGUAGES),
            "max_languages": choices.MAX_LANGUAGES,
            "name_min_length": choices.NAME_MIN_LENGTH,
            "name_max_length": choices.NAME_MAX_LENGTH,
        }
    )


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def update_my_profile(request):
    form = ProfileUpdateInput(data=request.data, partial=True)
    if not form.is_valid():
        return invalid_input_response(form)
    services.update_profile(request.user, form.validated_data)
    return Response(account_payload(request.user))
