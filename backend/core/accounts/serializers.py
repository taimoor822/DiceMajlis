from rest_framework import serializers

from .models import DeviceSession


class GuestLoginInput(serializers.Serializer):
    # Random id the app makes once per install (not a secret, just names the device).
    device_id = serializers.CharField(min_length=8, max_length=64)
    platform = serializers.ChoiceField(
        choices=DeviceSession.Platform.choices, default=DeviceSession.Platform.OTHER
    )


class RefreshInput(serializers.Serializer):
    refresh = serializers.CharField(max_length=200)
