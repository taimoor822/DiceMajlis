from django.db import models


class DomainEvent(models.Model):
    """
    Something that happened, written in the same transaction as the change
    (the outbox). ``processed_at`` is set once every handler has run.
    """

    kind = models.CharField(max_length=64, db_index=True)
    payload = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True, db_index=True)
    # Failed runs (a handler raised); retried with a growing wait.
    attempts = models.PositiveIntegerField(default=0)
    next_attempt_at = models.DateTimeField(null=True, blank=True)
    last_error = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["id"]
        indexes = [models.Index(fields=["processed_at", "next_attempt_at"], name="event_pending_idx")]

    def __str__(self) -> str:
        return f"{self.kind} #{self.pk}"
