"""
Sign-in API.

    POST /api/auth/guest/          {device_id, platform}   -> 201 tokens + account
    POST /api/auth/refresh/        {refresh}               -> 200 new tokens + account
    POST /api/auth/logout/         (signed in)             -> 204, this device signed out
    POST /api/auth/logout-others/  (signed in)             -> 200 {signed_out: n}
    GET  /api/me/                  (signed in)             -> 200 account

Errors: {"error": "...", "code": "..."} like the rest of the API.
"""

from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import (
    api_view,
    authentication_classes,
    permission_classes,
    throttle_classes,
)
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from game import services as game_services

from . import tokens
from .models import User
from .serializers import GuestLoginInput, RefreshInput
from .throttles import GuestSignupThrottle, RefreshThrottle


def account_payload(user: User) -> dict:
    return {
        "player_id": user.player_id,
        "display_name": user.public_name,
        "is_guest": user.is_guest,
        "created_at": user.created_at.isoformat(),
        # The room this account is in right now, so the app can go straight back to it.
        "active_room": game_services.active_seat_for(user),
    }


def _tokens_response(pair: tokens.TokenPair, http_status=status.HTTP_200_OK) -> Response:
    return Response(
        {
            "access": pair.access,
            "refresh": pair.refresh,
            "token_type": "Bearer",
            "access_expires_in": pair.access_expires_in,
            "account": account_payload(pair.session.user),
        },
        status=http_status,
    )


def _invalid(form) -> Response:
    return Response(
        {"error": "Invalid request", "code": "invalid_input", "fields": form.errors},
        status=status.HTTP_400_BAD_REQUEST,
    )


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
@throttle_classes([GuestSignupThrottle])
def guest_login(request):
    form = GuestLoginInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    with transaction.atomic():
        user = User.objects.create_guest()
        pair = tokens.start_session(
            user,
            device_id=form.validated_data["device_id"],
            platform=form.validated_data["platform"],
        )
    return _tokens_response(pair, status.HTTP_201_CREATED)


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
@throttle_classes([RefreshThrottle])
def refresh(request):
    form = RefreshInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    try:
        pair = tokens.refresh_session(form.validated_data["refresh"])
    except tokens.RefreshRefused as exc:
        return Response(
            {"error": str(exc), "code": exc.code}, status=status.HTTP_401_UNAUTHORIZED
        )
    return _tokens_response(pair)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout(request):
    request.auth.revoke("logout")
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout_others(request):
    signed_out = (
        request.user.sessions.filter(revoked_at__isnull=True)
        .exclude(id=request.auth.id)
        .update(revoked_at=timezone.now(), revoked_reason="logout_others")
    )
    return Response({"signed_out": signed_out})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def me(request):
    return Response(account_payload(request.user))
