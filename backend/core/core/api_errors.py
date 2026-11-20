"""
One error shape for the whole API: ``{"error": "<message>", "code": "<stable_code>"}``.
The app switches on ``code`` and shows its own translated text; ``error`` is for logs.
Views that build their own error responses already use this shape; this handler
covers what DRF raises itself (sign-in, permissions, rate limits, bad JSON).
"""

from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import exception_handler


def error_codes(detail):
    """DRF validation details -> the same shape with stable codes instead of English."""
    if isinstance(detail, dict):
        return {key: error_codes(value) for key, value in detail.items()}
    if isinstance(detail, list):
        return [error_codes(item) for item in detail]
    return getattr(detail, "code", None) or "invalid"


def invalid_input_response(serializer) -> Response:
    """400 for a request that failed its checks: ``fields`` lists a code per field."""
    return Response(
        {"error": "Invalid request", "code": "invalid_input", "fields": error_codes(serializer.errors)},
        status=status.HTTP_400_BAD_REQUEST,
    )


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
        data["fields"] = error_codes(exc.detail)
    if isinstance(exc, exceptions.Throttled) and exc.wait is not None:
        data["retry_after"] = int(exc.wait) + 1
    response.data = data
    return response
