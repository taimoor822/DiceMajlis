"""
Forgotten password: a 6-digit code by email, typed into the app.

- Only a keyed hash of the code is stored. A newer code replaces older ones.
- The code works for AUTH_RESET_CODE_LIFETIME and AUTH_RESET_CODE_ATTEMPTS tries.
- Asking for a code never reveals whether an email has an account.
- A new password signs the account out everywhere.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import secrets

from django.conf import settings
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone

from .models import PasswordResetCode, User

logger = logging.getLogger(__name__)


class ResetRefused(Exception):
    """Codes: invalid_code, code_expired, too_many_attempts."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _hash(user: User, code: str) -> str:
    key = settings.SECRET_KEY.encode()
    return hmac.new(key, f"reset:{user.pk}:{code}".encode(), hashlib.sha256).hexdigest()


def _account_for(email: str) -> User | None:
    user = User.objects.filter(email__iexact=email, is_active=True).first()
    if user is None or not user.has_usable_password():
        return None
    return user


def send_reset_code(email: str, *, now=None) -> None:
    """Email a new code if ``email`` has an account (and it hasn't asked too often)."""
    now = now or timezone.now()
    user = _account_for(email)
    if user is None:
        return
    hour_ago = now - timezone.timedelta(hours=1)
    if user.password_reset_codes.filter(created_at__gte=hour_ago).count() >= settings.AUTH_RESET_CODES_PER_HOUR:
        return  # quietly: nobody can flood someone's inbox

    code = f"{secrets.randbelow(1_000_000):06d}"
    with transaction.atomic():
        user.password_reset_codes.filter(used_at__isnull=True).update(used_at=now)
        PasswordResetCode.objects.create(
            user=user,
            code_hash=_hash(user, code),
            created_at=now,
            expires_at=now + settings.AUTH_RESET_CODE_LIFETIME,
        )

    minutes = int(settings.AUTH_RESET_CODE_LIFETIME.total_seconds() // 60)
    try:
        send_mail(
            subject="Your Dice Majlis password code",
            message=(
                f"Your code is {code}\n\n"
                f"Type it in the Dice Majlis app to choose a new password. "
                f"It works for {minutes} minutes.\n\n"
                "If you didn't ask for this, you can ignore this email: "
                "your password stays the same."
            ),
            from_email=None,
            recipient_list=[user.email],
        )
    except Exception:  # the request still answers "sent"; the player can ask again
        logger.exception("Could not send the password reset email")


def reset_password(email: str, code: str, new_password: str, *, now=None) -> User:
    """Check the code and set the new password. Raises ResetRefused."""
    now = now or timezone.now()
    refusal: ResetRefused | None = None
    with transaction.atomic():
        user = _account_for(email)
        entry = (
            PasswordResetCode.objects.select_for_update()
            .filter(user=user, used_at__isnull=True)
            .order_by("-created_at")
            .first()
            if user is not None
            else None
        )
        if entry is None:
            refusal = ResetRefused("invalid_code")
        elif entry.expires_at <= now:
            refusal = ResetRefused("code_expired")
        elif entry.attempts >= settings.AUTH_RESET_CODE_ATTEMPTS:
            refusal = ResetRefused("too_many_attempts")
        elif not hmac.compare_digest(entry.code_hash, _hash(user, code)):
            entry.attempts += 1
            entry.save(update_fields=["attempts"])
            out_of_tries = entry.attempts >= settings.AUTH_RESET_CODE_ATTEMPTS
            refusal = ResetRefused("too_many_attempts" if out_of_tries else "invalid_code")
        else:
            entry.used_at = now
            entry.save(update_fields=["used_at"])
            user.set_password(new_password)
            user.save(update_fields=["password"])
            user.sessions.filter(revoked_at__isnull=True).update(
                revoked_at=now, revoked_reason="password_reset"
            )
            return user
    raise refusal  # after the transaction, so a counted attempt is saved
