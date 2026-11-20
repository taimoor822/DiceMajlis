"""
Accounts: one permanent user per player, signed in from one or more devices.

- ``User.player_id`` is the public 9-digit Player ID. Random (not sequential) so it
  doesn't reveal how many players exist; it never changes and is never reused.
- A ``DeviceSession`` is one signed-in device. It holds the hash of that device's
  current refresh token (see accounts.tokens); revoking it signs the device out.
"""

from __future__ import annotations

import secrets
import uuid

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.db import IntegrityError, models, transaction
from django.db.models.functions import Lower
from django.utils import timezone

PLAYER_ID_MIN = 100_000_000
PLAYER_ID_MAX = 999_999_999
# 900 million ids: a clash is rare, several in a row means something is wrong.
PLAYER_ID_ATTEMPTS = 8


def new_player_id() -> int:
    return PLAYER_ID_MIN + secrets.randbelow(PLAYER_ID_MAX - PLAYER_ID_MIN + 1)


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create(self, *, username=None, email=None, password=None, **fields):
        email = self.normalize_email(email) if email else None
        for _ in range(PLAYER_ID_ATTEMPTS):
            user = self.model(
                username=username or None, email=email, player_id=new_player_id(), **fields
            )
            if password:
                user.set_password(password)
            else:
                user.set_unusable_password()
            try:
                with transaction.atomic(using=self._db):
                    user.save(using=self._db)
                return user
            except IntegrityError:
                # Retry only when the Player ID was taken; anything else is a real error.
                if not self.model.objects.filter(player_id=user.player_id).exists():
                    raise
        raise RuntimeError("Could not find a free Player ID")

    def create_guest(self) -> "User":
        """A player who pressed "Play as guest": no name, email or password yet."""
        return self._create(is_guest=True)

    def create_email_user(self, email: str, password: str) -> "User":
        """A player who signed up with email + password."""
        return self._create(email=email, password=password, is_guest=False)

    def create_user(self, username, password=None, **fields) -> "User":
        return self._create(username=username, password=password, **fields)

    def create_superuser(self, username, password=None, **fields) -> "User":
        fields.setdefault("is_staff", True)
        fields.setdefault("is_superuser", True)
        return self._create(username=username, password=password, **fields)


class User(AbstractBaseUser, PermissionsMixin):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    player_id = models.PositiveIntegerField(
        unique=True,
        editable=False,
        default=new_player_id,  # UserManager retries on the rare clash
        help_text="Public 9-digit Player ID. Never changes.",
    )
    # Staff sign in to /admin with a username; players get usernames in step 1.7.
    username = models.CharField(max_length=30, unique=True, null=True, blank=True)
    email = models.EmailField(unique=True, null=True, blank=True)
    is_guest = models.BooleanField(
        default=False, help_text="Signed up with 'Play as guest' and has no other sign-in yet."
    )
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    created_at = models.DateTimeField(default=timezone.now)

    USERNAME_FIELD = "username"
    EMAIL_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    objects = UserManager()

    class Meta:
        constraints = [
            models.UniqueConstraint(Lower("username"), name="accounts_user_username_ci_unique"),
            models.UniqueConstraint(Lower("email"), name="accounts_user_email_ci_unique"),
        ]

    def __str__(self) -> str:
        return self.username or f"Player {self.player_id}"

    @property
    def public_name(self) -> str:
        """The name other players see (from the profile)."""
        from profiles.services import profile_of  # profiles depends on accounts

        return profile_of(self).display_name

    @property
    def has_email_sign_in(self) -> bool:
        return bool(self.email) and self.has_usable_password()


class DeviceSession(models.Model):
    """One signed-in device. Revoked = that device is signed out."""

    class Platform(models.TextChoices):
        ANDROID = "android"
        IOS = "ios"
        WEB = "web"
        DESKTOP = "desktop"
        OTHER = "other"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, related_name="sessions", on_delete=models.CASCADE)
    # Random id the app creates once per install. For listing devices; not a secret.
    device_id = models.CharField(max_length=64)
    platform = models.CharField(max_length=16, choices=Platform.choices, default=Platform.OTHER)
    created_at = models.DateTimeField(default=timezone.now)
    last_seen_at = models.DateTimeField(default=timezone.now)
    # SHA-256 of the current refresh token's secret, and of the one before it
    # (a reused old token means it was copied: the session is ended).
    refresh_hash = models.CharField(max_length=64)
    previous_refresh_hash = models.CharField(max_length=64, blank=True, default="")
    rotated_at = models.DateTimeField(default=timezone.now)
    refresh_expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)
    revoked_reason = models.CharField(max_length=32, blank=True, default="")

    class Meta:
        indexes = [models.Index(fields=["user", "revoked_at"])]

    def __str__(self) -> str:
        return f"{self.user} on {self.platform}"

    @property
    def is_active(self) -> bool:
        return self.revoked_at is None

    def revoke(self, reason: str, *, now=None) -> None:
        if self.revoked_at is None:
            self.revoked_at = now or timezone.now()
            self.revoked_reason = reason
            self.save(update_fields=["revoked_at", "revoked_reason"])


class PasswordResetCode(models.Model):
    """
    A 6-digit code emailed to reset a forgotten password. Only a keyed hash is
    stored. Valid for a short time and a few tries; a newer code replaces it.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, related_name="password_reset_codes", on_delete=models.CASCADE)
    code_hash = models.CharField(max_length=64)
    created_at = models.DateTimeField(default=timezone.now)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["user", "created_at"])]

    def __str__(self) -> str:
        return f"Reset code for {self.user}"
