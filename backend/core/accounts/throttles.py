from django.conf import settings
from rest_framework.throttling import SimpleRateThrottle


class _IpThrottle(SimpleRateThrottle):
    """Per-IP limit whose rate is read from settings.AUTH_RATE_LIMITS at request time."""

    def get_rate(self):
        return settings.AUTH_RATE_LIMITS[self.scope]

    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class GuestSignupThrottle(_IpThrottle):
    scope = "guest_signup"


class RefreshThrottle(_IpThrottle):
    scope = "auth_refresh"


class EmailSignupThrottle(_IpThrottle):
    scope = "email_signup"


class LoginThrottle(_IpThrottle):
    scope = "login"


class PasswordResetThrottle(_IpThrottle):
    scope = "password_reset"
