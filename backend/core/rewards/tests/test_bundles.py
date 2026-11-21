"""Reward bundles (step 2.5): currencies, XP and items in one grant(); the admin-made
daily cycle with its streak options; reward history."""

from datetime import datetime, timedelta
from unittest import mock
from zoneinfo import ZoneInfo

from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts import tokens as account_tokens
from accounts.models import User
from items.models import InventoryItem, ItemTransaction
from items.services import owned_items
from profiles.models import Profile, XpEntry
from rewards import daily
from rewards.engine import check_bundle, grant
from rewards.models import DailyRewardDay, DailyRewardSettings, RewardBundle, RewardClaim
from wallet import services as wallet


def bahrain(*args):
    return datetime(*args, tzinfo=ZoneInfo("Asia/Bahrain"))


class BundleTestCase(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()
        patcher = mock.patch("realtime.publish.publish")
        patcher.start()
        self.addCleanup(patcher.stop)


class GrantTests(BundleTestCase):
    def test_everything_in_one_go_and_once(self):
        bundle = {"gold": 10, "diamond": 2, "xp": 30, "items": [{"code": "frame_palm"}, {"code": "dice_ruby", "days": 3}]}
        first = grant(self.user, bundle, kind="achievement", idempotency_key="k1", source="achievement:x:1")
        again = grant(self.user, bundle, kind="achievement", idempotency_key="k1")
        self.assertTrue(first.created)
        self.assertFalse(again.created)
        self.assertEqual(wallet.balances(self.user), {"gold": 10, "diamond": 2})
        self.assertEqual(Profile.objects.get(pk=self.user.pk).xp, 30)
        self.assertEqual(XpEntry.objects.get().reason, "reward")
        codes = {e["item"].code: e["expires_at"] for e in owned_items(self.user)}
        self.assertIsNone(codes["frame_palm"])
        self.assertIsNotNone(codes["dice_ruby"])
        self.assertEqual(set(ItemTransaction.objects.values_list("type", flat=True)), {"achievement"})
        self.assertEqual(first.claim.source, "achievement:x:1")

    def test_a_failing_part_gives_nothing(self):
        with mock.patch("items.services.grant", side_effect=RuntimeError("down")):
            with self.assertRaises(RuntimeError):
                grant(self.user, {"gold": 10, "items": [{"code": "frame_palm"}]}, kind="daily_login", idempotency_key="k")
        self.assertEqual(wallet.balances(self.user)["gold"], 0)
        self.assertFalse(RewardClaim.objects.exists())

    def test_bundles_are_checked(self):
        for bad in (
            {},
            {"gold": 0},
            {"gold": -1},
            {"xp": 1.5},
            {"silver": 5},
            {"items": [{"code": "made_up"}]},
            {"items": [{"code": "dice_pearl", "quantity": 0}]},
            {"items": [{"code": "dice_pearl", "days": 0}]},
            {"items": [{"code": "dice_pearl", "colour": "red"}]},
            {"items": "dice_pearl"},
        ):
            with self.assertRaises(ValueError, msg=bad):
                check_bundle(bad)
        self.assertEqual(
            check_bundle({"gold": 5, "diamond": 0, "items": [{"code": "dice_pearl"}]}),
            {"gold": 5, "items": [{"code": "dice_pearl", "quantity": 1}]},
        )


@override_settings(REWARD_DAY_TIMEZONE="Asia/Bahrain", REWARD_DAY_START_HOUR=0)
class DailyCycleTests(BundleTestCase):
    morning = bahrain(2026, 11, 20, 9, 0)

    def claim(self, offset):
        return daily.claim(self.user, now=self.morning + timedelta(days=offset))

    def days_claimed(self):
        return list(RewardClaim.objects.order_by("reward_day").values_list("streak_day", flat=True))

    def test_day_seven_lends_the_pearl_dice_for_a_week(self):
        for offset in range(7):
            self.claim(offset)
        pearl = InventoryItem.objects.get(item__code="dice_pearl")
        claimed_at = RewardClaim.objects.get(streak_day=7).created_at
        self.assertAlmostEqual(
            (pearl.expires_at - claimed_at).total_seconds(), timedelta(days=7).total_seconds(), delta=60
        )
        self.assertEqual(Profile.objects.get(pk=self.user.pk).xp, 20)

    def test_the_admin_can_change_the_cycle(self):
        DailyRewardDay.objects.filter(day__gt=3).delete()
        bonus = RewardBundle.objects.create(code="big", name="Big", contents={"diamond": 1})
        DailyRewardDay.objects.filter(day=3).update(bundle=bonus)
        for offset in range(4):
            self.claim(offset)
        self.assertEqual(self.days_claimed(), [1, 2, 3, 1])
        self.assertEqual(wallet.balances(self.user)["diamond"], 1)

    def test_a_missed_day_can_carry_on(self):
        DailyRewardSettings.objects.filter(pk=1).update(on_miss="continue")
        self.claim(0)
        self.claim(1)
        self.claim(4)  # two days missed
        self.assertEqual(self.days_claimed(), [1, 2, 3])

    def test_after_the_last_day_it_can_stay(self):
        DailyRewardSettings.objects.filter(pk=1).update(after_last_day="stay")
        for offset in range(9):
            self.claim(offset)
        self.assertEqual(self.days_claimed(), [1, 2, 3, 4, 5, 6, 7, 7, 7])
        self.assertEqual(daily.status(self.user, now=self.morning + timedelta(days=8))["next_day"], 7)

    def test_no_days_means_no_daily_reward(self):
        DailyRewardDay.objects.all().delete()
        status = daily.status(self.user, now=self.morning)
        self.assertEqual((status["available"], status["days"]), (False, []))
        with self.assertRaises(daily.NotAvailable):
            self.claim(0)


class HistoryApiTests(BundleTestCase):
    def setUp(self):
        super().setUp()
        self.api = APIClient()
        access = account_tokens.start_session(self.user, device_id="d", platform="other").access
        self.api.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    def test_history_newest_first_with_names(self):
        self.api.post("/api/rewards/daily/claim/")
        from progress.models import AchievementTier

        tier = AchievementTier.objects.get(achievement__code="wins", threshold=10)
        grant(self.user, tier.reward, kind="achievement", idempotency_key="a", source="achievement:wins:10")
        r = self.api.get("/api/rewards/history/")
        self.assertEqual(r.status_code, 200)
        first, second = r.data["claims"]
        self.assertEqual((first["kind"], first["achievement"], first["threshold"]), ("achievement", "Victories", 10))
        self.assertEqual(first["reward"]["items"][0]["name"], "Night Sky")
        self.assertEqual((second["kind"], second["day"], second["reward"]["gold"]), ("daily_login", 1, 100))
        self.assertIsNone(r.data["next"])

    def test_pages(self):
        for n in range(35):
            grant(self.user, {"gold": 1}, kind="daily_login", idempotency_key=f"k{n}")
        r = self.api.get("/api/rewards/history/")
        self.assertEqual((len(r.data["claims"]), r.data["next"] is not None), (30, True))
        r = self.api.get(f"/api/rewards/history/?before={r.data['next']}")
        self.assertEqual((len(r.data["claims"]), r.data["next"]), (5, None))
        self.assertEqual(self.api.get("/api/rewards/history/?before=nope").status_code, 400)
