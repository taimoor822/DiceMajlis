"""
Sign-in tokens.

- **Access token:** a short-lived JWT (15 minutes) sent as ``Authorization: Bearer``.
  It names the user (``sub``) and the device session (``sid``); every request also
  checks that the session is still active, so signing a device out works at once.
- **Refresh token:** ``<session id>.<random secret>``, valid 30 days, kept in the
  app's secure storage. Only its SHA-256 is stored. Each use returns a NEW refresh
  token (rotation). If an OLD one is used again, someone copied it, so the whole
  session is ended.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass

import jwt
from django.conf import settings
from django.db import transaction
from django.utils import timezone

from .models import DeviceSession, User

ALGORITHM = "HS256"


class TokenError(Exception):
    """A sign-in token was refused. ``code`` is stable; the app switches on it."""

    code = "invalid_token"

    def __init__(self, message: str = "", code: str | None = None):
        super().__init__(message or self.__class__.__doc__ or "")
        if code:
            self.code = code


class TokenExpired(TokenError):
    """The access token has expired: refresh it."""

    code = "token_expired"


class RefreshRefused(TokenError):
    """The refresh token can't be used. Codes: invalid_refresh, refresh_expired,
    session_revoked, refresh_superseded."""

    code = "invalid_refresh"


@dataclass(frozen=True)
class TokenPair:
    access: str
    refresh: str
    access_expires_in: int  # seconds
    session: DeviceSession


def _signing_key() -> str:
    return settings.AUTH_JWT_SIGNING_KEY


def _hash(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def _access_seconds() -> int:
    return int(settings.AUTH_ACCESS_TOKEN_LIFETIME.total_seconds())


def issue_access(session: DeviceSession, *, now=None) -> str:
    now = now or timezone.now()
    payload = {
        "sub": str(session.user_id),
        "sid": str(session.id),
        "typ": "access",
        "iat": int(now.timestamp()),
        "exp": int((now + settings.AUTH_ACCESS_TOKEN_LIFETIME).timestamp()),
        "jti": secrets.token_hex(8),
    }
    return jwt.encode(payload, _signing_key(), algorithm=ALGORITHM)


def decode_access(token: str) -> dict:
    try:
        claims = jwt.decode(
            token,
            _signing_key(),
            algorithms=[ALGORITHM],
            options={"require": ["exp", "iat", "sub", "sid", "typ"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise TokenExpired("Access token expired") from exc
    except jwt.InvalidTokenError as exc:
        raise TokenError("Invalid access token") from exc
    if claims.get("typ") != "access":
        raise TokenError("Not an access token")
    return claims


def _rotate_refresh(session: DeviceSession, now) -> str:
    """Give ``session`` a new refresh secret; returns the token to hand out once."""
    secret = secrets.token_urlsafe(32)
    session.previous_refresh_hash = session.refresh_hash
    session.refresh_hash = _hash(secret)
    session.rotated_at = now
    session.refresh_expires_at = now + settings.AUTH_REFRESH_TOKEN_LIFETIME
    return f"{session.id}.{secret}"


def start_session(user: User, *, device_id: str, platform: str, now=None) -> TokenPair:
    """Sign ``user`` in on a device: a new session and its first tokens."""
    now = now or timezone.now()
    session = DeviceSession(
        user=user,
        device_id=device_id,
        platform=platform,
        created_at=now,
        last_seen_at=now,
        refresh_hash="",
        refresh_expires_at=now,
    )
    refresh = _rotate_refresh(session, now)
    session.previous_refresh_hash = ""
    session.save()
    return TokenPair(issue_access(session, now=now), refresh, _access_seconds(), session)


def refresh_session(refresh_token: str, *, now=None) -> TokenPair:
    """Swap a refresh token for new tokens (rotation). Raises RefreshRefused."""
    now = now or timezone.now()
    session_id, _, secret = (refresh_token or "").partition(".")
    try:
        session_uuid = uuid.UUID(session_id)
    except ValueError:
        raise RefreshRefused("Unknown refresh token") from None
    if not secret:
        raise RefreshRefused("Unknown refresh token")

    refusal: RefreshRefused | None = None
    with transaction.atomic():
        session = (
            DeviceSession.objects.select_for_update()
            .select_related("user")
            .filter(id=session_uuid)
            .first()
        )
        presented = _hash(secret)
        if session is None:
            refusal = RefreshRefused("Unknown refresh token")
        elif not session.is_active:
            refusal = RefreshRefused("Signed out", code="session_revoked")
        elif hmac.compare_digest(presented, session.refresh_hash):
            if session.refresh_expires_at <= now:
                session.revoke("expired", now=now)
                refusal = RefreshRefused("Refresh token expired", code="refresh_expired")
            elif not session.user.is_active:
                session.revoke("user_inactive", now=now)
                refusal = RefreshRefused("Account disabled", code="session_revoked")
            else:
                refresh = _rotate_refresh(session, now)
                session.last_seen_at = now
                session.save()
                return TokenPair(issue_access(session, now=now), refresh, _access_seconds(), session)
        elif session.previous_refresh_hash and hmac.compare_digest(
            presented, session.previous_refresh_hash
        ):
            if now - session.rotated_at <= settings.AUTH_REFRESH_REUSE_GRACE:
                # Two refreshes raced on the same device: refuse, but don't sign out.
                refusal = RefreshRefused("Already refreshed", code="refresh_superseded")
            else:
                # An old token came back: it was copied. End the session everywhere.
                session.revoke("refresh_reused", now=now)
                refusal = RefreshRefused("Refresh token reused", code="session_revoked")
        else:
            refusal = RefreshRefused("Unknown refresh token")
    raise refusal  # after the transaction, so a revocation above is saved
