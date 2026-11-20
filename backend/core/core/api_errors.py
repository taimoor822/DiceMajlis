"""
One error shape for the whole API: ``{"error": "<message>", "code": "<stable_code>"}``.
The app switches on ``code`` and shows its own translated text; ``error`` is for logs.
Views that build their own error responses already use this shape; this handler
covers what DRF raises itself (sign-in, permissions, rate limits, bad JSON).
"""

from rest_framework import exceptions
from rest_framework.views import exception_handler


def _code_for(exc: exceptions.APIException) -> str:
    if isinstance(exc, exceptions.Throttled):
        return "rate_limited"
    if isinstance(exc, exceptions.NotAuthenticated):
        return "not_authenticated"
    if isinstance(exc, (exceptions.ValidationError, exceptions.ParseError)):
        return "invalid_input"
    codes = exc.get_codes()
    return codes if isinstance(codes, str) else exc.default_code


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is None or not isinstance(exc, exceptions.APIException):
        return response
    data = {"error": str(exc.detail) if isinstance(exc.detail, str) else "Invalid request",
            "code": _code_for(exc)}
    if isinstance(exc, exceptions.ValidationError):
        data["fields"] = exc.detail
    if isinstance(exc, exceptions.Throttled) and exc.wait is not None:
        data["retry_after"] = int(exc.wait) + 1
    response.data = data
    return response
