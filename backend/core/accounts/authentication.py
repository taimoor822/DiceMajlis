from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.exceptions import AuthenticationFailed

from . import tokens
from .models import DeviceSession


class AccessTokenAuthentication(BaseAuthentication):
    """
    ``Authorization: Bearer <access token>``. Sets ``request.user`` to the account
    and ``request.auth`` to its DeviceSession. No header = anonymous (views decide
    whether that's allowed); a bad or expired token = 401 with a stable code.
    """

    keyword = b"bearer"

    def authenticate(self, request):
        parts = get_authorization_header(request).split()
        if not parts or parts[0].lower() != self.keyword:
            return None
        if len(parts) != 2:
            raise AuthenticationFailed("Malformed Authorization header", code="invalid_token")
        try:
            claims = tokens.decode_access(parts[1].decode("latin-1"))
        except tokens.TokenError as exc:
            raise AuthenticationFailed(str(exc), code=exc.code) from exc

        session = (
            DeviceSession.objects.select_related("user")
            .filter(id=claims["sid"], user_id=claims["sub"])
            .first()
        )
        if session is None or not session.is_active or not session.user.is_active:
            raise AuthenticationFailed("Signed out", code="session_revoked")
        return session.user, session

    def authenticate_header(self, request):
        return "Bearer"
