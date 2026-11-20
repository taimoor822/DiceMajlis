from django.contrib.auth import password_validation
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers
from rest_framework.exceptions import ErrorDetail

from .models import DeviceSession, User

PASSWORD_MAX_LENGTH = 128


class DeviceInput(serializers.Serializer):
    # Random id the app makes once per install (not a secret, just names the device).
    device_id = serializers.CharField(min_length=8, max_length=64)
    platform = serializers.ChoiceField(
        choices=DeviceSession.Platform.choices, default=DeviceSession.Platform.OTHER
    )


class GuestLoginInput(DeviceInput):
    pass


class RefreshInput(serializers.Serializer):
    refresh = serializers.CharField(max_length=200)


def normalize_email(value: str) -> str:
    """Emails are matched without caring about upper/lower case."""
    return value.strip().lower()


class EmailField(serializers.EmailField):
    def to_internal_value(self, data):
        return normalize_email(super().to_internal_value(data))


def check_new_password(password: str, user: User, field: str) -> None:
    """
    Django's password rules (settings.AUTH_PASSWORD_VALIDATORS). Every failure is
    reported under ``field`` with its own code (password_too_short, ...).
    """
    try:
        password_validation.validate_password(password, user)
    except DjangoValidationError as exc:
        raise serializers.ValidationError(
            {field: [ErrorDetail(str(error.message), code=error.code) for error in exc.error_list]}
        ) from exc


class NewPasswordField(serializers.CharField):
    def __init__(self, **kwargs):
        kwargs.setdefault("max_length", PASSWORD_MAX_LENGTH)
        kwargs.setdefault("trim_whitespace", False)
        super().__init__(**kwargs)


class RegisterInput(DeviceInput):
    email = EmailField()
    password = NewPasswordField()

    def validate(self, data):
        # Checked here so "too similar to the email" can see the email.
        check_new_password(data["password"], User(email=data["email"]), "password")
        return data


class EmailLoginInput(DeviceInput):
    email = EmailField()
    password = serializers.CharField(max_length=PASSWORD_MAX_LENGTH, trim_whitespace=False)


class SaveAccountInput(serializers.Serializer):
    """A guest adds email + password (keeps the same account and Player ID)."""

    email = EmailField()
    password = NewPasswordField()

    def validate(self, data):
        check_new_password(data["password"], User(email=data["email"]), "password")
        return data


class PasswordResetRequestInput(serializers.Serializer):
    email = EmailField()


class PasswordResetConfirmInput(serializers.Serializer):
    email = EmailField()
    code = serializers.RegexField(r"^\d{6}$", max_length=6)
    new_password = NewPasswordField()

    def validate(self, data):
        check_new_password(data["new_password"], User(email=data["email"]), "new_password")
        return data
