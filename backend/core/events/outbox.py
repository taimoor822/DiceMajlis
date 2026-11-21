"""The outbox: emit() inside a transaction, handlers run after the commit."""

from __future__ import annotations

import logging
from collections import defaultdict
from datetime import timedelta
from typing import Any, Callable

from django.db import transaction
from django.utils import timezone

from .models import DomainEvent

logger = logging.getLogger(__name__)

Handler = Callable[[dict[str, Any], DomainEvent], None]
_HANDLERS: dict[str, list[Handler]] = defaultdict(list)

# A failing event waits 2, 4, 8 ... minutes between tries, and stops after this many.
MAX_ATTEMPTS = 8


def on(kind: str, handler: Handler) -> None:
    """Run ``handler(payload, event)`` for every ``kind`` event (once registered)."""
    if handler not in _HANDLERS[kind]:
        _HANDLERS[kind].append(handler)


def off(kind: str, handler: Handler) -> None:
    if handler in _HANDLERS[kind]:
        _HANDLERS[kind].remove(handler)


def emit(kind: str, payload: dict[str, Any]) -> DomainEvent:
    """
    Record that ``kind`` happened. Call it inside the transaction that made the
    change: if that rolls back, the event never existed. After the commit the
    handlers run (best effort right away; the sweep retries what is left).
    """
    event = DomainEvent.objects.create(kind=kind, payload=payload)
    transaction.on_commit(lambda: _dispatch_quietly(event.pk))
    return event


def _dispatch_quietly(event_id: int) -> None:
    try:
        dispatch(event_id)
    except Exception:  # never break the request that emitted it
        logger.exception("domain event %s failed", event_id)


def dispatch(event_id: int) -> bool:
    """Run the handlers of one event. True when it is done (now or before)."""
    with transaction.atomic():
        event = DomainEvent.objects.select_for_update(skip_locked=True).filter(pk=event_id).first()
        if event is None or event.processed_at is not None:
            return event is not None
        try:
            # Each handler's changes and "processed" are saved together, or not at all.
            with transaction.atomic():
                for handler in list(_HANDLERS.get(event.kind, [])):
                    handler(event.payload, event)
                event.processed_at = timezone.now()
                event.last_error = ""
                event.save(update_fields=["processed_at", "last_error"])
            return True
        except Exception as exc:
            event.attempts += 1
            event.last_error = f"{type(exc).__name__}: {exc}"[:2000]
            event.next_attempt_at = timezone.now() + timedelta(minutes=2 ** event.attempts)
            event.save(update_fields=["attempts", "last_error", "next_attempt_at"])
            logger.warning("domain event %s (%s) failed: %s", event.pk, event.kind, exc)
            return False


def dispatch_pending(now=None, limit: int = 100, *, min_age_seconds: float = 2.0) -> int:
    """
    The sweep: events not yet done (missed after a crash, or failed earlier).
    Events younger than ``min_age_seconds`` are left to their own commit hook.
    Returns how many finished now.
    """
    now = now or timezone.now()
    pending = (
        DomainEvent.objects.filter(
            processed_at__isnull=True,
            attempts__lt=MAX_ATTEMPTS,
            created_at__lte=now - timedelta(seconds=min_age_seconds),
        )
        .exclude(next_attempt_at__gt=now)
        .values_list("pk", flat=True)[:limit]
    )
    return sum(1 for event_id in list(pending) if dispatch(event_id))
