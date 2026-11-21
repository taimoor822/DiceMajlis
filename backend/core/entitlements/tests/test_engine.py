"""The entitlement engine (step 2.6): sources, inheritance, merging, overrides."""

from datetime import timedelta
from unittest import mock

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts import tokens as account_tokens
from accounts.models import User
from entitlements import engine
from entitlements.models import Privilege, PrivilegeGrant, UserPrivilegeOverride
from items import services as items
from items.models import ItemDefinition


class EngineTestCase(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()
        patcher = mock.patch("realtime.publish.publish")
        self.publish = patcher.start()
        self.addCleanup(patcher.stop)
        self.bonus = Privilege.objects.get(code="game_exp_bonus")  # number, max
        self.royal = Privilege.objects.get(code="royal_items")  # flag
        self.tickets = Privilege.objects.get(code="recharge_ticket")  # number, sum

    def grant(self, privilege, source_type="base", source_key="base", value=1, rank=0, mode="grant", **kw):
        return PrivilegeGrant.objects.create(
            privilege=privilege, source_type=source_type, source_key=source_key, value=value, rank=rank, mode=mode, **kw
        )

    def now(self):
        return engine.compute(self.user)


class MergeTests(EngineTestCase):
    def test_nothing_by_default(self):
        self.assertEqual(self.now(), {})
        self.assertFalse(engine.has(self.user, "royal_items"))
        self.assertEqual(engine.value(self.user, "game_exp_bonus"), 0)

    def test_base_grants_apply_to_everyone(self):
        self.grant(self.royal)
        self.grant(self.bonus, value=5)
        self.assertEqual(self.now(), {"royal_items": True, "game_exp_bonus": 5})

    def test_items_give_privileges_while_owned(self):
        self.grant(self.bonus, "item", "item:frame_falcon", value=10)
        self.grant(self.bonus, value=5)
        self.assertEqual(self.now()["game_exp_bonus"], 5)
        items.grant(self.user, "frame_falcon", idempotency_key="k", days=1)
        self.assertEqual(self.now()["game_exp_bonus"], 10)  # the highest wins
        later = timezone.now() + timedelta(days=2)
        self.assertEqual(engine.compute(self.user, later)["game_exp_bonus"], 5)

    def test_sum_privileges_add_up(self):
        self.grant(self.tickets, value=2)
        self.grant(self.tickets, "item", "item:dice_ivory", value=3)  # a starter: everyone owns it
        self.assertEqual(self.now()["recharge_ticket"], 5)

    def test_higher_ranks_inherit_and_can_revoke(self):
        # As Royal levels will: level 3 gets levels 0..3 unless one takes back.
        Matcher = engine.SourceMatch
        with mock.patch.dict(engine._RESOLVERS, {"royal_level": lambda u, n: [Matcher("royal_level", max_rank=3)]}):
            self.grant(self.royal, "royal_level", "royal:1", rank=1)
            self.grant(self.bonus, "royal_level", "royal:2", rank=2, value=10)
            self.assertEqual(self.now(), {"royal_items": True, "game_exp_bonus": 10})
            self.grant(self.royal, "royal_level", "royal:3", rank=3, mode="revoke")
            self.grant(self.bonus, "royal_level", "royal:5", rank=5, value=50)  # not reached
            self.assertEqual(self.now(), {"game_exp_bonus": 10})

    def test_grants_with_dates(self):
        now = timezone.now()
        self.grant(self.royal, starts_at=now + timedelta(days=1))
        self.grant(self.bonus, value=7, ends_at=now - timedelta(seconds=1))
        self.assertEqual(self.now(), {})

    def test_inactive_privileges_count_for_nothing(self):
        self.grant(self.royal)
        Privilege.objects.filter(pk=self.royal.pk).update(active=False)
        self.assertEqual(self.now(), {})


class OverrideTests(EngineTestCase):
    def override(self, privilege, mode, value=1, **kw):
        return UserPrivilegeOverride.objects.create(
            user=self.user, privilege=privilege, mode=mode, value=value, reason="test", **kw
        )

    def test_allow_adds_and_deny_wins(self):
        self.override(self.bonus, "allow", value=20)
        self.grant(self.bonus, value=5)
        self.assertEqual(self.now()["game_exp_bonus"], 20)
        self.grant(self.royal)
        self.override(self.royal, "deny")
        self.assertNotIn("royal_items", self.now())

    def test_overrides_end(self):
        self.override(self.royal, "allow", ends_at=timezone.now() - timedelta(minutes=1))
        self.assertEqual(self.now(), {})


class CacheTests(EngineTestCase):
    def test_cached_and_forgotten_when_things_change(self):
        self.assertFalse(engine.has(self.user, "royal_items"))
        with self.captureOnCommitCallbacks(execute=True):
            UserPrivilegeOverride.objects.create(user=self.user, privilege=self.royal, mode="allow", reason="r")
        self.assertTrue(engine.has(self.user, "royal_items"))
        channel, kind, data = self.publish.call_args.args
        self.assertEqual((channel, kind), (f"user/{self.user.player_id}", "entitlements_updated"))
        self.assertEqual(data["entitlements"], {"royal_items": True})
        self.assertEqual(data["privileges"][0]["name"], "Royal items")

    def test_rule_changes_reach_everyone(self):
        self.assertFalse(engine.has(self.user, "royal_items"))
        self.grant(self.royal)  # a new base grant (admin): every cached answer is old
        self.assertTrue(engine.has(self.user, "royal_items"))

    def test_no_message_when_nothing_changed(self):
        engine.snapshot(self.user)
        with self.captureOnCommitCallbacks(execute=True):
            items.grant(self.user, "dice_pearl", idempotency_key="k")  # gives no privilege
        kinds = [c.args[1] for c in self.publish.call_args_list]
        self.assertNotIn("entitlements_updated", kinds)


class ItemLockTests(EngineTestCase):
    def setUp(self):
        super().setUp()
        ItemDefinition.objects.filter(code="frame_falcon").update(requires_privilege="royal_items")
        items.grant(self.user, "frame_falcon", idempotency_key="k")

    def test_a_royal_item_needs_its_privilege(self):
        with self.assertRaises(items.ItemError) as caught:
            items.equip(self.user, "frame", "frame_falcon")
        self.assertEqual(caught.exception.code, "needs_privilege")
        falcon = next(i for i in items.inventory_payload(self.user)["items"] if i["code"] == "frame_falcon")
        self.assertEqual((falcon["locked"], falcon["requires_privilege_name"]), (True, "Royal items"))

        override = UserPrivilegeOverride.objects.create(
            user=self.user, privilege=self.royal, mode="allow", reason="r"
        )
        items.equip(self.user, "frame", "frame_falcon")
        self.assertEqual(items.cosmetics_payload(self.user)["frame"], "frame_falcon")
        # Losing the privilege takes it off (back to the default look).
        override.delete()
        self.assertIsNone(items.cosmetics_payload(self.user)["frame"])


class XpBonusTests(EngineTestCase):
    def test_bonus_and_higher_limit_apply_to_game_xp(self):
        from profiles import xp

        self.grant(self.bonus, value=50)
        self.grant(Privilege.objects.get(code="higher_exp_limit"), value=100)
        payload = {
            "counts": True, "game_id": 1, "room_code": "ABC123", "player_count": 2,
            "finished_at": "2026-11-21T09:00:00+00:00",
            "players": [{"user_id": str(self.user.pk), "is_bot": False, "place": 1, "status": "finished"}],
        }
        with mock.patch.object(xp, "add_xp") as add_xp:
            xp.on_game_finished(payload)
        args, kwargs = add_xp.call_args
        self.assertEqual(args[1], 75)  # 50 XP + 50 %
        self.assertEqual(kwargs["daily_cap"], xp.GAME_XP_DAILY_CAP + 100)


class ApiTests(EngineTestCase):
    def test_my_entitlements(self):
        api = APIClient()
        api.credentials(
            HTTP_AUTHORIZATION=f"Bearer {account_tokens.start_session(self.user, device_id='d', platform='other').access}"
        )
        self.grant(self.bonus, value=5)
        self.grant(Privilege.objects.get(code="voice_messaging"))
        r = api.get("/api/me/entitlements/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["entitlements"], {"game_exp_bonus": 5, "voice_messaging": True})
        built = {p["code"]: p["built"] for p in r.data["privileges"]}
        self.assertEqual(built, {"game_exp_bonus": True, "voice_messaging": False})
        self.assertEqual(APIClient().get("/api/me/entitlements/").status_code, 401)
