"""
Google and Apple sign-in (step 1.15): checking the ID token the app got from
Google or Apple.

The app signs in with the provider on the phone and sends us the provider's
**ID token** (a JWT). We trust it only after checking, here, that:

1. it is signed (RS256) by one of the provider's published keys (JWKS, kept in
   the cache for an hour and fetched again when a new key id appears);
2. it was made for **our** app: ``aud`` is one of our client IDs
   (``GOOGLE_CLIENT_IDS`` / ``APPLE_CLIENT_IDS``, comma-separated, from the
   environment), and ``iss`` is the provider;
3. it hasn't expired (``exp``, one minute of leeway for phone clocks);
4. for Apple, when the app sent a nonce, the token carries its SHA-256 (it
   can't be replayed from another sign-in).

The account is then found by the provider's stable user id (``sub``), never by
email. A provider with no client IDs configured is "not configured": the app
hides its button (``GET /api/auth/providers/``).
"""

from __future__ import annotations

import hashlib
import hmac
import json
import urllib.request
from dataclasses import dataclass
from typing import Any

import jwt
from django.conf import settings
from django.core.cache import cache

GOOGLE = "google"
APPLE = "apple"

JWKS_CACHE_SECONDS = 60 * 60
FETCH_TIMEOUT_SECONDS = 5
LEEWAY_SECONDS = 60


class SocialTokenError(Exception):
    """The ID token can't be used. ``code`` goes to the app."""

    def __init__(self, code: str, message: str = ""):
        super().__init__(message or code)
        self.code = code


@dataclass(frozen=True)
class Provider:
    name: str
    jwks_url: str
    issuers: tuple[str, ...]
    audiences_setting: str
    # Apple puts SHA-256(nonce) in the token; Google the nonce itself.
    hashed_nonce: bool

    def audiences(self) -> list[str]:
        raw = getattr(settings, self.audiences_setting, "") or ""
        if isinstance(raw, (list, tuple)):
            return [str(a).strip() for a in raw if str(a).strip()]
        return [a.strip() for a in str(raw).split(",") if a.strip()]

    @property
    def configured(self) -> bool:
        return bool(self.audiences())


PROVIDERS: dict[str, Provider] = {
    GOOGLE: Provider(
        name=GOOGLE,
        jwks_url="https://www.googleapis.com/oauth2/v3/certs",
        issuers=("accounts.google.com", "https://accounts.google.com"),
        audiences_setting="GOOGLE_CLIENT_IDS",
        hashed_nonce=False,
    ),
    APPLE: Provider(
        name=APPLE,
        jwks_url="https://appleid.apple.com/auth/keys",
        issuers=("https://appleid.apple.com",),
        audiences_setting="APPLE_CLIENT_IDS",
        hashed_nonce=True,
    ),
}


@dataclass(frozen=True)
class Identity:
    """Who the provider says signed in."""

    provider: str
    subject: str  # the provider's stable user id
    email: str | None
    email_verified: bool


def configured() -> dict[str, bool]:
    return {name: provider.configured for name, provider in PROVIDERS.items()}


def provider(name: Any) -> Provider:
    found = PROVIDERS.get(name) if isinstance(name, str) else None
    if found is None:
        raise SocialTokenError("unknown_provider", "Unknown sign-in provider")
    if not found.configured:
        raise SocialTokenError("provider_not_configured", f"{found.name} sign-in is not set up")
    return found


# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------


def _fetch_jwks(url: str) -> dict[str, Any]:
    """The provider's public keys (tests replace this)."""
    with urllib.request.urlopen(url, timeout=FETCH_TIMEOUT_SECONDS) as response:  # noqa: S310 (fixed https URL)
        return json.loads(response.read())


def _jwks(found: Provider, *, refresh: bool = False) -> dict[str, Any]:
    key = f"social:jwks:{found.name}"
    jwks = None if refresh else cache.get(key)
    if jwks is None:
        try:
            jwks = _fetch_jwks(found.jwks_url)
        except Exception as exc:
            raise SocialTokenError("provider_unreachable", f"Can't reach {found.name}") from exc
        cache.set(key, jwks, JWKS_CACHE_SECONDS)
    return jwks


def _signing_key(found: Provider, kid: str):
    for refresh in (False, True):  # a key id we don't know yet: they rotated keys
        for jwk in _jwks(found, refresh=refresh).get("keys", []):
            if jwk.get("kid") == kid:
                try:
                    return jwt.PyJWK(jwk).key
                except jwt.PyJWTError as exc:
                    raise SocialTokenError("invalid_token", "Unusable provider key") from exc
    raise SocialTokenError("invalid_token", "Signed with an unknown key")


# ---------------------------------------------------------------------------
# Checking a token
# ---------------------------------------------------------------------------


def verify(name: str, id_token: Any, *, nonce: str | None = None) -> Identity:
    """The identity in ``id_token`` from provider ``name``, or SocialTokenError."""
    found = provider(name)
    if not isinstance(id_token, str) or not id_token or len(id_token) > 8192:
        raise SocialTokenError("invalid_token", "Missing ID token")
    try:
        header = jwt.get_unverified_header(id_token)
    except jwt.PyJWTError as exc:
        raise SocialTokenError("invalid_token", "Not a token") from exc
    if header.get("alg") != "RS256" or not header.get("kid"):
        raise SocialTokenError("invalid_token", "Unexpected token signature")

    key = _signing_key(found, header["kid"])
    try:
        claims = jwt.decode(
            id_token,
            key,
            algorithms=["RS256"],
            audience=found.audiences(),
            issuer=list(found.issuers),
            leeway=LEEWAY_SECONDS,
            options={"require": ["exp", "iat", "iss", "aud", "sub"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise SocialTokenError("token_expired", "The sign-in expired, try again") from exc
    except jwt.InvalidAudienceError as exc:
        raise SocialTokenError("wrong_audience", "This token is for another app") from exc
    except jwt.InvalidIssuerError as exc:
        raise SocialTokenError("wrong_issuer", "This token is from someone else") from exc
    except jwt.PyJWTError as exc:
        raise SocialTokenError("invalid_token", "The token can't be checked") from exc

    _check_nonce(found, claims, nonce)
    subject = str(claims["sub"])
    if not subject or len(subject) > 255:
        raise SocialTokenError("invalid_token", "No user in the token")
    email = claims.get("email")
    verified = claims.get("email_verified") in (True, "true")
    return Identity(
        provider=found.name,
        subject=subject,
        email=email.strip().lower() if isinstance(email, str) and email.strip() else None,
        email_verified=verified,
    )


def _check_nonce(found: Provider, claims: dict[str, Any], nonce: str | None) -> None:
    in_token = claims.get("nonce")
    if nonce is None and in_token is None:
        return
    if nonce is None or in_token is None:
        raise SocialTokenError("invalid_nonce", "The sign-in doesn't match")
    expected = hashlib.sha256(nonce.encode()).hexdigest() if found.hashed_nonce else nonce
    if not hmac.compare_digest(str(in_token), expected):
        raise SocialTokenError("invalid_nonce", "The sign-in doesn't match")
