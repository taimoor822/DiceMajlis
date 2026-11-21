"""The domain-event outbox (events.outbox)."""

from datetime import timedelta
from unittest import mock

from django.db import transaction
from django.test import TestCase
from django.utils import timezone

from events import outbox
from events.models import DomainEvent


class OutboxTests(TestCase):
    def setUp(self):
        self.seen = []
        self.handler = lambda payload, event: self.seen.append((event.pk, payload))
        outbox.on("test_happened", self.handler)
        self.addCleanup(outbox.off, "test_happened", self.handler)

    def test_handlers_run_after_the_commit(self):
        with self.captureOnCommitCallbacks(execute=True):
            event = outbox.emit("test_happened", {"n": 1})
            self.assertEqual(self.seen, [])  # not before the commit
        self.assertEqual(self.seen, [(event.pk, {"n": 1})])
        event.refresh_from_db()
        self.assertIsNotNone(event.processed_at)

    def test_a_rolled_back_change_has_no_event(self):
        with self.captureOnCommitCallbacks(execute=True):
            try:
                with transaction.atomic():
                    outbox.emit("test_happened", {"n": 1})
                    raise RuntimeError("the change failed")
            except RuntimeError:
                pass
        self.assertEqual(self.seen, [])
        self.assertFalse(DomainEvent.objects.exists())

    def test_an_event_is_handled_once(self):
        event = outbox.emit("test_happened", {})
        self.assertTrue(outbox.dispatch(event.pk))
        self.assertTrue(outbox.dispatch(event.pk))  # already done: nothing runs
        self.assertEqual(len(self.seen), 1)

    def test_a_failing_handler_is_retried_later_and_its_changes_undone(self):
        calls = []

        def flaky(payload, event):
            calls.append(1)
            DomainEvent.objects.create(kind="side_effect", payload={})
            if len(calls) == 1:
                raise ValueError("database hiccup")

        outbox.on("flaky", flaky)
        self.addCleanup(outbox.off, "flaky", flaky)
        event = outbox.emit("flaky", {})
        self.assertFalse(outbox.dispatch(event.pk))
        event.refresh_from_db()
        self.assertEqual((event.attempts, event.processed_at), (1, None))
        self.assertIn("database hiccup", event.last_error)
        self.assertFalse(DomainEvent.objects.filter(kind="side_effect").exists())

        # Not before its wait is over ...
        now = timezone.now()
        self.assertEqual(outbox.dispatch_pending(now=now, min_age_seconds=0), 0)
        # ... then the sweep runs it again.
        self.assertEqual(outbox.dispatch_pending(now=now + timedelta(minutes=3), min_age_seconds=0), 1)
        event.refresh_from_db()
        self.assertIsNotNone(event.processed_at)
        self.assertEqual(DomainEvent.objects.filter(kind="side_effect").count(), 1)

    def test_the_sweep_picks_up_events_that_were_never_handled(self):
        # As after a crash between the commit and the handlers.
        event = DomainEvent.objects.create(kind="test_happened", payload={"n": 2})
        later = timezone.now() + timedelta(seconds=5)
        self.assertEqual(outbox.dispatch_pending(now=later), 1)
        self.assertEqual(self.seen, [(event.pk, {"n": 2})])

    def test_a_crash_in_the_commit_hook_does_not_break_the_caller(self):
        with mock.patch.object(outbox, "dispatch", side_effect=RuntimeError("boom")):
            with self.captureOnCommitCallbacks(execute=True):
                outbox.emit("test_happened", {})
        self.assertTrue(DomainEvent.objects.filter(processed_at__isnull=True).exists())
