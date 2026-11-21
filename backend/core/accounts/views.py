"""
Sign-in API.

    POST /api/auth/guest/                  {device_id, platform}            -> 201 tokens + account
    POST /api/auth/register/               {email, password, device_id, platform} -> 201 tokens + account
    POST /api/auth/login/                  {email, password, device_id, platform} -> 200 tokens + account
    POST /api/auth/refresh/                {refresh}                        -> 200 new tokens + account
    POST /api/auth/save-account/           (guest) {email, password}        -> 200 account
    POST /api/auth/password-reset/         {email}                          -> 200 (always)
    POST /api/auth/password-reset/confirm/ {email, code, new_password}      -> 200
    POST /api/auth/logout/                 (signed in)                      -> 204, this device signed out
    POST /api/auth/logout-others/          (signed in)                      -> 200 {signed_out: n}
    GET  /api/me/                          (signed in)                      -> 200 account
    GET  /api/auth/providers/              -> 200 {google: bool, apple: bool}   (set up on this server?)
    POST /api/auth/social/<provider>/      {id_token, nonce?, device_id, platform} -> 200/201 tokens + account
    POST /api/me/link/<provider>/          (signed in) {id_token, nonce?}  -> 200 account (a guest keeps everything)
    POST /api/me/unlink/<provider>/        (signed in)                      -> 200 account

Errors: {"error": "...", "code": "..."} like the rest of the API.
"""

from django.contrib.auth.hashers import make_password
from django.contrib.auth.models import update_last_login
from django.db import IntegrityError, transaction
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

from core.api_errors import invalid_input_response
from game import services as game_services
from items.services import cosmetics_payload
from profiles.services import profile_payload

from . import limits, recovery, social, tokens
from .models import SocialAccount, User
from .serializers import (
    EmailLoginInput,
    GuestLoginInput,
    PasswordResetConfirmInput,
    PasswordResetRequestInput,
    RefreshInput,
    RegisterInput,
    SaveAccountInput,
    SocialLoginInput,
    SocialTokenInput,
)
from .throttles import (
    EmailSignupThrottle,
    GuestSignupThrottle,
    LoginThrottle,
    PasswordResetThrottle,
    RefreshThrottle,
    SocialLoginThrottle,
)


def _error(message: str, code: str, http_status: int, **extra) -> Response:
    return Response({"error": message, "code": code, **extra}, status=http_status)


def _email_taken() -> Response:
    return _error("That email already has an account", "email_taken", status.HTTP_409_CONFLICT)


def account_payload(user: User) -> dict:
    """Everything the signed-in player sees about their own account."""
    return {
        "player_id": user.player_id,
        "is_guest": user.is_guest,
        "email": user.email,
        "created_at": user.created_at.isoformat(),
        # Google / Apple sign-ins attached to this account.
        "linked": sorted(user.social_accounts.values_list("provider", flat=True)),
        # display_name, avatar, country, languages, level, xp, level_xp, next_level_xp
        **profile_payload(user),
        # What the app draws for you: {"dice": asset, "board": asset, "frame": asset | null}
        "cosmetics": cosmetics_payload(user),
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
    return invalid_input_response(form)


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
@throttle_classes([EmailSignupThrottle])
def register(request):
    """A new account with email + password (and its own Player ID)."""
    form = RegisterInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    if User.objects.filter(email__iexact=data["email"]).exists():
        return _email_taken()
    try:
        with transaction.atomic():
            user = User.objects.create_email_user(data["email"], data["password"])
            pair = tokens.start_session(
                user, device_id=data["device_id"], platform=data["platform"]
            )
    except IntegrityError:  # the same email signed up a moment ago
        return _email_taken()
    return _tokens_response(pair, status.HTTP_201_CREATED)


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
@throttle_classes([LoginThrottle])
def login(request):
    form = EmailLoginInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    email = data["email"]

    wait = limits.blocked_for(email)
    if wait is not None:
        return _error(
            "Too many wrong passwords", "rate_limited", status.HTTP_429_TOO_MANY_REQUESTS,
            retry_after=wait,
        )

    user = User.objects.filter(email__iexact=email).first()
    if user is None:
        make_password(data["password"])  # take as long as a real check
        signed_in = False
    else:
        signed_in = user.is_active and user.check_password(data["password"])
    if not signed_in:
        limits.record_failure(email)
        return _error(
            "Wrong email or password", "invalid_credentials", status.HTTP_401_UNAUTHORIZED
        )

    limits.clear_failures(email)
    update_last_login(None, user)
    pair = tokens.start_session(user, device_id=data["device_id"], platform=data["platform"])
    return _tokens_response(pair)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def save_account(request):
    """A guest adds email + password: same account, same Player ID, now recoverable."""
    user = request.user
    if not user.is_guest:
        return _error("This account is already saved", "already_saved", status.HTTP_409_CONFLICT)
    form = SaveAccountInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    if User.objects.filter(email__iexact=data["email"]).exclude(pk=user.pk).exists():
        return _email_taken()
    user.email = data["email"]
    user.set_password(data["password"])
    user.is_guest = False
    try:
        with transaction.atomic():
            user.save(update_fields=["email", "password", "is_guest"])
    except IntegrityError:
        return _email_taken()
    return Response(account_payload(user))


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
@throttle_classes([PasswordResetThrottle])
def password_reset_request(request):
    """Emails a code if the address has an account. The answer is the same either way."""
    form = PasswordResetRequestInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    recovery.send_reset_code(form.validated_data["email"])
    return Response({"status": "sent"})


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
@throttle_classes([PasswordResetThrottle])
def password_reset_confirm(request):
    form = PasswordResetConfirmInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    try:
        recovery.reset_password(data["email"], data["code"], data["new_password"])
    except recovery.ResetRefused as exc:
        return _error("The code can't be used", exc.code, status.HTTP_400_BAD_REQUEST)
    limits.clear_failures(data["email"])
    return Response({"status": "password_changed"})


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


# =========================
# GOOGLE / APPLE (1.15)
# =========================

_SOCIAL_ERROR_HTTP = {
    "unknown_provider": status.HTTP_404_NOT_FOUND,
    "provider_not_configured": status.HTTP_503_SERVICE_UNAVAILABLE,
    "provider_unreachable": status.HTTP_503_SERVICE_UNAVAILABLE,
}


def _social_error(exc: social.SocialTokenError) -> Response:
    return _error(str(exc), exc.code, _SOCIAL_ERROR_HTTP.get(exc.code, status.HTTP_401_UNAUTHORIZED))


def _free_email(identity: social.Identity) -> str | None:
    """The provider's email, when it is verified and no account uses it yet."""
    if not (identity.email and identity.email_verified):
        return None
    if User.objects.filter(email__iexact=identity.email).exists():
        return None
    return identity.email


@api_view(["GET"])
@authentication_classes([])
@permission_classes([AllowAny])
def providers(request):
    """Which sign-in buttons the app may show (the provider is set up on this server)."""
    return Response(social.configured())


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
@throttle_classes([SocialLoginThrottle])
def social_login(request, provider):
    """
    Sign in with Google or Apple. The same Google/Apple user always gets the same
    account. A new one gets a new account, unless its email already belongs to an
    account: then they sign in with that and link Google/Apple there (we never
    join accounts by email on our own).
    """
    form = SocialLoginInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    try:
        identity = social.verify(provider, data["id_token"], nonce=data.get("nonce"))
    except social.SocialTokenError as exc:
        return _social_error(exc)

    now = timezone.now()
    created = False
    try:
        with transaction.atomic():
            link = (
                SocialAccount.objects.select_related("user")
                .filter(provider=identity.provider, subject=identity.subject)
                .first()
            )
            if link is not None:
                user = link.user
                SocialAccount.objects.filter(pk=link.pk).update(last_used_at=now)
            else:
                if (
                    identity.email
                    and identity.email_verified
                    and User.objects.filter(email__iexact=identity.email).exists()
                ):
                    return _error(
                        "That email already has an account: sign in with it, then link this",
                        "email_taken",
                        status.HTTP_409_CONFLICT,
                    )
                user = User.objects.create_social_user(email=_free_email(identity))
                SocialAccount.objects.create(
                    user=user,
                    provider=identity.provider,
                    subject=identity.subject,
                    email=identity.email,
                    last_used_at=now,
                )
                created = True
            if not user.is_active:
                return _error("This account is closed", "account_disabled", status.HTTP_403_FORBIDDEN)
            update_last_login(None, user)
            pair = tokens.start_session(user, device_id=data["device_id"], platform=data["platform"])
    except IntegrityError:  # the same sign-in a moment ago: try again
        return _error("Please try again", "try_again", status.HTTP_409_CONFLICT)
    return _tokens_response(pair, status.HTTP_201_CREATED if created else status.HTTP_200_OK)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@throttle_classes([SocialLoginThrottle])
def link_social(request, provider):
    """
    Attach Google or Apple to the signed-in account. A guest keeps everything
    (Player ID, level, gold, rooms) and is now saved: the next phone signs in
    with Google/Apple and finds the same account.
    """
    form = SocialTokenInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    try:
        identity = social.verify(provider, form.validated_data["id_token"], nonce=form.validated_data.get("nonce"))
    except social.SocialTokenError as exc:
        return _social_error(exc)

    user = request.user
    try:
        with transaction.atomic():
            taken = SocialAccount.objects.filter(provider=identity.provider, subject=identity.subject).first()
            if taken is not None:
                if taken.user_id == user.pk:
                    return Response(account_payload(user))  # already linked
                return _error(
                    "That account is linked to another player", "social_account_taken",
                    status.HTTP_409_CONFLICT,
                )
            if user.social_accounts.filter(provider=identity.provider).exists():
                return _error(
                    "Another account of this kind is linked already", "already_linked",
                    status.HTTP_409_CONFLICT,
                )
            SocialAccount.objects.create(
                user=user,
                provider=identity.provider,
                subject=identity.subject,
                email=identity.email,
                last_used_at=timezone.now(),
            )
            changed = []
            if user.is_guest:
                user.is_guest = False
                changed.append("is_guest")
            if user.email is None:
                email = _free_email(identity)
                if email:
                    user.email = email
                    changed.append("email")
            if changed:
                user.save(update_fields=changed)
    except IntegrityError:
        return _error("Please try again", "try_again", status.HTTP_409_CONFLICT)
    return Response(account_payload(user))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def unlink_social(request, provider):
    """Detach Google or Apple, if the account keeps another way to sign in."""
    user = request.user
    link = user.social_accounts.filter(provider=provider).first()
    if link is None:
        return _error("Not linked", "not_linked", status.HTTP_404_NOT_FOUND)
    if not user.has_usable_password() and not user.social_accounts.exclude(pk=link.pk).exists():
        return _error(
            "This is the only way to sign in to this account", "last_sign_in_method",
            status.HTTP_409_CONFLICT,
        )
    link.delete()
    return Response(account_payload(user))
