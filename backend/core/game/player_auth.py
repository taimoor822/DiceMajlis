"""
Proves that a request comes from the device that owns a seat.

Each player gets a random secret when they create or join a room. Only that
device receives it; the server keeps a SHA-256 hash. Starting, rolling and
moving need the secret, so knowing someone's player id (it is shared with the
whole room) is not enough to play for them.

Interim: accounts (plan step 1.6) replace this with signed-in users.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets

from .models import Player

SECRET_BYTES = 32


def _hash(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def issue_secret(player: Player) -> str:
    """Give ``player`` a new secret; returns it (shown once, never stored in clear)."""
    secret = secrets.token_urlsafe(SECRET_BYTES)
    player.secret_hash = _hash(secret)
    player.save(update_fields=["secret_hash"])
    return secret


def owns_seat(player: Player, secret: object) -> bool:
    if not player.secret_hash or not isinstance(secret, str) or not secret:
        return False
    return hmac.compare_digest(player.secret_hash, _hash(secret))
