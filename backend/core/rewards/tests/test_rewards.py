"""grant() and the daily login reward."""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from accounts import tokens
from accounts.models import User
from rewards import daily, days
from rewards.engine import grant
from rewards.models import RewardClaim
from wallet import services as wallet
from wallet.models import WalletTransaction

LOCAL_CACHE = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
BAHRAIN = ZoneInfo("Asia/Bahrain")


def bahrain(*args) -> datetime:
    return datetime(*args, tzinfo=BAHRAIN)


class GrantTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()

    def test_one_claim_and_its_ledger_entries_together(self):
        result = grant(self.user, {"gold": 500, "diamond": 5}, kind="daily_login", idempotency_key="g1")
        self.assertTrue(result.created)
        self.assertEqual(wallet.balances(self.user), {"gold": 500, "diamond": 5})
        entries = WalletTransaction.objects.filter(reference_id=str(result.claim.id))
        self.assertEqual(sorted(e.account.currency for e in entries), ["diamond", "gold"])
        self.assertTrue(all(e.type == "reward_daily" for e in entries))

    def test_the_same_key_gives_once(self):
        grant(self.user, {"gold": 100}, kind="daily_login", idempotency_key="g1")
        again = grant(self.user, {"gold": 100}, kind="daily_login", idempotency_key="g1")
        self.assertFalse(again.created)
        self.assertEqual(wallet.balances(self.user)["gold"], 100)
        self.assertEqual(RewardClaim.objects.count(), 1)

    def test_bad_bundles_are_refused(self):
        for bundle in ({}, {"gold": 0}, {"coins": 5}, {"gold": -5}, {"gold": 2.5}):
            with self.assertRaises(ValueError, msg=bundle):
                grant(self.user, bundle, kind="daily_login", idempotency_key=f"bad{bundle}")
        self.assertEqual(RewardClaim.objects.count(), 0)


@override_settings(REWARD_DAY_TIMEZONE="Asia/Bahrain", REWARD_DAY_START_HOUR=0)
class RewardDayTests(TestCase):
    def test_days_change_at_midnight_bahrain_time(self):
        self.assertEqual(str(days.reward_day(bahrain(2026, 11, 20, 23, 59))), "2026-11-20")
        self.assertEqual(str(days.reward_day(bahrain(2026, 11, 21, 0, 0))), "2026-11-21")
        # 21:00 UTC is already the next day in Bahrain.
        utc = datetime(2026, 11, 20, 21, 0, tzinfo=ZoneInfo("UTC"))
        self.assertEqual(str(days.reward_day(utc)), "2026-11-21")
        self.assertEqual(days.next_reset(bahrain(2026, 11, 20, 18, 0)), bahrain(2026, 11, 21, 0, 0))

    @override_settings(REWARD_DAY_START_HOUR=4)
    def test_the_start_hour_can_move(self):
        self.assertEqual(str(days.reward_day(bahrain(2026, 11, 21, 3, 59))), "2026-11-20")
        self.assertEqual(days.next_reset(bahrain(2026, 11, 21, 3, 0)), bahrain(2026, 11, 21, 4, 0))


@override_settings(REWARD_DAY_TIMEZONE="Asia/Bahrain", REWARD_DAY_START_HOUR=0)
class DailyLoginTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()
        self.morning = bahrain(2026, 11, 20, 9, 0)

    def claim(self, when):
        return daily.claim(self.user, now=when)

    def test_first_claim_is_day_one(self):
        status = daily.status(self.user, now=self.morning)
        self.assertEqual((status["day"], status["claimed_today"]), (1, False))
        self.assertEqual(len(status["days"]), 7)
        self.assertEqual(status["seconds_until_reset"], 15 * 3600)
        self.claim(self.morning)
        self.assertEqual(wallet.balances(self.user)["gold"], 100)
        status = daily.status(self.user, now=self.morning)
        self.assertEqual((status["day"], status["claimed_today"]), (1, True))

    def test_once_per_day(self):
        self.claim(self.morning)
        with self.assertRaises(daily.AlreadyClaimed):
            self.claim(self.morning + timedelta(hours=14, minutes=59))  # 23:59 the same day
        self.assertEqual(wallet.balances(self.user)["gold"], 100)

    def test_days_in_a_row_climb_the_cycle_and_wrap(self):
        for offset in range(9):
            self.claim(self.morning + timedelta(days=offset))
        claims = list(RewardClaim.objects.order_by("reward_day").values_list("streak_day", flat=True))
        self.assertEqual(claims, [1, 2, 3, 4, 5, 6, 7, 1, 2])
        # Day 7 also gives diamonds.
        self.assertEqual(wallet.balances(self.user)["diamond"], 5)
        self.assertEqual(
            wallet.balances(self.user)["gold"],
            sum(d.bundle.contents.get("gold", 0) for d in daily.cycle()) + 100 + 150,
        )

    def test_missing_a_day_starts_again(self):
        self.claim(self.morning)
        self.claim(self.morning + timedelta(days=1))
        self.assertEqual(daily.status(self.user, now=self.morning + timedelta(days=3))["day"], 1)
        self.claim(self.morning + timedelta(days=3))
        self.assertEqual(RewardClaim.objects.order_by("-reward_day").first().streak_day, 1)

    def test_just_after_midnight_is_a_new_day(self):
        self.claim(bahrain(2026, 11, 20, 23, 59))
        self.claim(bahrain(2026, 11, 21, 0, 1))
        self.assertEqual(RewardClaim.objects.count(), 2)


@override_settings(CACHES=LOCAL_CACHE)
class DailyApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_guest()
        access = tokens.start_session(self.user, device_id="device-0001", platform="web").access
        self.auth = {"HTTP_AUTHORIZATION": f"Bearer {access}"}
        self.api = APIClient()

    def test_status_then_claim_then_already_claimed(self):
        status = self.api.get("/api/rewards/daily/", **self.auth).data
        self.assertEqual((status["day"], status["claimed_today"]), (1, False))
        day7 = status["days"][6]
        self.assertEqual((day7["day"], day7["gold"], day7["diamond"], day7["xp"]), (7, 500, 5, 20))
        self.assertEqual(
            day7["items"],
            [{"code": "dice_pearl", "name": "Pearl", "asset": "dice_pearl", "slot": "dice",
              "rarity": "epic", "quantity": 1, "days": 7}],
        )
        self.assertGreater(status["seconds_until_reset"], 0)

        r = self.api.post("/api/rewards/daily/claim/", **self.auth)
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["claimed"], {"day": 1, "gold": 100, "diamond": 0, "xp": 0, "items": []})
        self.assertEqual(r.data["balances"], {"gold": 100, "diamond": 0})
        self.assertTrue(r.data["daily"]["claimed_today"])

        r = self.api.post("/api/rewards/daily/claim/", **self.auth)
        self.assertEqual((r.status_code, r.data["code"]), (409, "already_claimed"))
        self.assertEqual(wallet.balances(self.user)["gold"], 100)

    def test_the_app_cannot_choose_the_reward(self):
        r = self.api.post("/api/rewards/daily/claim/", {"gold": 999999, "day": 7}, format="json", **self.auth)
        self.assertEqual(r.data["claimed"]["gold"], 100)

    def test_needs_a_sign_in(self):
        r = self.api.post("/api/rewards/daily/claim/")
        self.assertEqual((r.status_code, r.data["code"]), (401, "not_authenticated"))

    def test_everything_adds_up_in_the_audit(self):
        self.api.post("/api/rewards/daily/claim/", **self.auth)
        self.assertEqual(wallet.audit(), [])

    def test_uses_the_real_clock(self):
        before = timezone.now()
        self.api.post("/api/rewards/daily/claim/", **self.auth)
        self.assertEqual(RewardClaim.objects.get().reward_day, days.reward_day(before))
