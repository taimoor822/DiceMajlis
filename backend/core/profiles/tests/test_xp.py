"""Account XP (step 2.1): the XP ledger, and XP from real online games."""

from datetime import datetime, timedelta, timezone as dt_timezone
from unittest import mock

from django.test import TestCase

from accounts.models import User
from events.models import DomainEvent
from game.models import Player
from game.test_rooms import RoomTestCase
from profiles import xp
from profiles.models import Profile, XpEntry, XpIsAppendOnly
from profiles.services import profile_payload

NOON = datetime(2026, 11, 21, 9, 0, tzinfo=dt_timezone.utc)  # 12:00 in Bahrain


class AddXpTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()

    def add(self, amount, key, **kwargs):
        return xp.add_xp(self.user, amount, reason="game", idempotency_key=key, now=NOON, **kwargs)

    def xp(self):
        return Profile.objects.get(pk=self.user.pk).xp

    def test_xp_is_added_once_per_key(self):
        first = self.add(30, "game:1")
        again = self.add(30, "game:1")
        self.assertTrue(first.created)
        self.assertFalse(again.created)
        self.assertEqual(self.xp(), 30)
        entry = XpEntry.objects.get()
        self.assertEqual((entry.xp_before, entry.xp_after, entry.reward_day.isoformat()), (0, 30, "2026-11-21"))

    def test_the_level_comes_from_the_ledger(self):
        result = self.add(120, "game:1")
        self.assertEqual((result.level_before, result.level_after, result.level_up), (1, 2, True))
        self.assertEqual(profile_payload(self.user)["level"], 2)
        self.assertFalse(self.add(10, "game:2").level_up)
        self.assertEqual(sum(XpEntry.objects.values_list("amount", flat=True)), self.xp())

    def test_the_daily_cap_counts_one_reward_day(self):
        self.add(450, "game:1", daily_cap=500)
        capped = self.add(100, "game:2", daily_cap=500)
        self.assertEqual(capped.entry.amount, 50)
        self.assertFalse(self.add(100, "game:3", daily_cap=500).created)
        # The next reward-day starts at 00:00 Bahrain (21:00 UTC).
        tomorrow = xp.add_xp(
            self.user, 100, reason="game", idempotency_key="game:4", daily_cap=500,
            now=NOON + timedelta(hours=12),
        )
        self.assertEqual(tomorrow.entry.amount, 100)
        self.assertEqual(self.xp(), 600)

    def test_entries_cannot_be_changed_or_deleted(self):
        entry = self.add(10, "game:1").entry
        with self.assertRaises(XpIsAppendOnly):
            entry.save()
        with self.assertRaises(XpIsAppendOnly):
            entry.delete()

    def test_bad_amounts_and_reasons_are_refused(self):
        for amount in (0, -5, 1.5, True):
            with self.assertRaises(ValueError):
                self.add(amount, f"bad:{amount}")
        with self.assertRaises(ValueError):
            xp.add_xp(self.user, 5, reason="cheat", idempotency_key="x")

    def test_the_account_hears_about_it(self):
        with mock.patch("realtime.publish.publish") as publish, \
                self.captureOnCommitCallbacks(execute=True):
            self.add(120, "game:7", reference_type="game", reference_id="7")
        channel, kind, data = publish.call_args.args
        self.assertEqual((channel, kind), (f"user/{self.user.player_id}", "xp_gained"))
        self.assertEqual(
            data,
            {"amount": 120, "reason": "game", "reference_type": "game", "reference_id": "7",
             "level_up": True, "level": 2, "xp": 120, "level_xp": 100, "next_level_xp": 300},
        )

    def test_game_xp_rules(self):
        self.assertEqual(xp.game_xp(1, "finished", 2), 50)
        self.assertEqual(xp.game_xp(2, "active", 2), 20)  # 2nd of 2 is last
        self.assertEqual(xp.game_xp(2, "finished", 4), 30)
        self.assertEqual(xp.game_xp(4, "active", 4), 20)
        self.assertEqual(xp.game_xp(3, "forfeited", 4), 0)


class GameXpTests(RoomTestCase):
    """XP from finished online games, through the ``game_finished`` event."""

    def setUp(self):
        super().setUp()
        self.addCleanup(mock.patch.stopall)
        mock.patch("realtime.publish.publish").start()

    def user(self, seat):
        return Player.objects.get(id=seat).user

    def xp_of(self, seat):
        return Profile.objects.get(pk=self.user(seat).pk).xp

    def play_two_people(self):
        code, host = self.create_room()
        guest = self.join(code)
        self.start(code, host)
        return code, host, guest

    def test_a_real_game_gives_xp_to_both_players(self):
        from realtime import publish

        code, host, guest = self.play_two_people()
        with self.captureOnCommitCallbacks(execute=True):
            self.finish_game(code, host)
        self.assertEqual((self.xp_of(host), self.xp_of(guest)), (50, 20))
        pushes = [c.args for c in publish.publish.call_args_list if c.args[1] == "xp_gained"]
        self.assertEqual(
            {(channel, data["amount"], data["room_code"]) for channel, _, data in pushes},
            {(f"user/{self.user(host).player_id}", 50, code), (f"user/{self.user(guest).player_id}", 20, code)},
        )
        event = DomainEvent.objects.get(kind="game_finished")
        self.assertIsNotNone(event.processed_at)
        payload = event.payload
        self.assertEqual((payload["counts"], payload["human_count"], payload["bot_count"]), (True, 2, 0))
        winner = payload["players"][0]
        self.assertEqual(
            (winner["seat_id"], winner["user_id"], winner["place"], winner["is_bot"]),
            (host, str(self.user(host).pk), 1, False),
        )
        entry = XpEntry.objects.get(profile__user=self.user(host))
        self.assertEqual((entry.reference_type, entry.reference_id), ("game", str(payload["game_id"])))

    def test_the_event_is_saved_with_the_game_and_handled_even_after_a_crash(self):
        code, host, guest = self.play_two_people()
        self.finish_game(code, host)  # the commit hook never ran (as in a crash)
        self.assertEqual(self.xp_of(host), 0)
        from events.outbox import dispatch_pending

        self.assertGreaterEqual(dispatch_pending(min_age_seconds=0), 1)
        dispatch_pending(min_age_seconds=0)  # nothing is given twice
        self.assertEqual((self.xp_of(host), self.xp_of(guest)), (50, 20))
        self.assertEqual(XpEntry.objects.count(), 2)
        self.assertFalse(DomainEvent.objects.filter(processed_at__isnull=True).exists())

    def test_games_with_the_ai_give_no_xp(self):
        code, host = self.create_room()
        self.start(code, host)  # the AI fills the table
        self.assertTrue(Player.objects.filter(room__code=code, is_bot=True).exists())
        with self.captureOnCommitCallbacks(execute=True):
            self.finish_game(code, host)
        self.assertFalse(DomainEvent.objects.get(kind="game_finished").payload["counts"])
        self.assertEqual(self.xp_of(host), 0)
        self.assertFalse(XpEntry.objects.exists())

    def test_a_player_who_forfeits_gets_nothing(self):
        code, host = self.create_room()
        guest = self.join(code)
        third = self.join(code, color="green")
        self.start(code, host)
        with self.captureOnCommitCallbacks(execute=True):
            self.post("leave-room", code=code, player_id=third)  # forfeit
            self.finish_game(code, host)
        self.assertEqual(self.xp_of(third), 0)
        self.assertEqual(self.xp_of(host), 50)
        # Guest is 2nd of 3 players: the bonus counts.
        self.assertEqual(self.xp_of(guest), 30)
