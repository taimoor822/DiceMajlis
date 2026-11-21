"""The item system (step 2.2): owning, granting, expiring and wearing cosmetics."""

from datetime import timedelta
from unittest import mock

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts import tokens as account_tokens
from accounts.models import User
from items import services
from items.models import EquippedCosmetic, InventoryItem, ItemIsAppendOnly, ItemTransaction


class ItemTestCase(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()
        patcher = mock.patch("realtime.publish.publish")
        self.publish = patcher.start()
        self.addCleanup(patcher.stop)

    def codes(self, user=None):
        return [e["item"].code for e in services.owned_items(user or self.user)]

    def grant(self, code, key=None, **kwargs):
        return services.grant(self.user, code, idempotency_key=key or f"test:{code}", **kwargs)


class OwningTests(ItemTestCase):
    def test_every_account_owns_the_starter_set(self):
        self.assertEqual(
            self.codes(),
            ["board_majlis", "board_oasis", "dice_ivory", "dice_desert_gold", "frame_brass"],
        )
        self.assertFalse(InventoryItem.objects.exists())  # nothing stored for that

    def test_a_grant_happens_once_per_key(self):
        first = self.grant("dice_pearl", key="achievement:x")
        again = self.grant("dice_pearl", key="achievement:x")
        self.assertTrue(first.created)
        self.assertFalse(again.created)
        self.assertIn("dice_pearl", self.codes())
        entry = ItemTransaction.objects.get()
        self.assertEqual((entry.quantity, entry.quantity_before, entry.quantity_after), (1, 0, 1))

    def test_a_cosmetic_is_owned_once(self):
        self.grant("dice_pearl", key="a")
        self.assertFalse(self.grant("dice_pearl", key="b").created)  # already theirs
        self.assertFalse(self.grant("dice_ivory", key="c").created)  # a starter
        self.assertEqual(InventoryItem.objects.get().quantity, 1)
        self.assertEqual(ItemTransaction.objects.count(), 1)

    def test_entries_cannot_be_changed_or_deleted(self):
        entry = self.grant("dice_pearl").entry
        with self.assertRaises(ItemIsAppendOnly):
            entry.save()
        with self.assertRaises(ItemIsAppendOnly):
            entry.delete()

    def test_taking_back_never_goes_below_zero(self):
        item = services.get_item("dice_pearl")
        with self.assertRaises(services.ItemError) as caught:
            services.change(self.user, item, -1, type="admin_revoke", idempotency_key="x")
        self.assertEqual(caught.exception.code, "not_enough")
        self.grant("dice_pearl")
        services.change(self.user, item, -1, type="admin_revoke", idempotency_key="y")
        self.assertNotIn("dice_pearl", self.codes())

    def test_unknown_items_are_refused(self):
        with self.assertRaises(services.ItemError) as caught:
            self.grant("dice_made_up")
        self.assertEqual(caught.exception.code, "unknown_item")


class ExpiryTests(ItemTestCase):
    def test_time_limited_items_expire_in_the_sweep_and_come_off(self):
        now = timezone.now()
        self.grant("frame_lantern", days=7, now=now)
        services.equip(self.user, "frame", "frame_lantern", now=now)
        later = now + timedelta(days=7, seconds=1)
        # Before the sweep, it already stops showing.
        self.assertIsNone(services.cosmetics_payload(self.user, later)["frame"])
        self.assertEqual(services.expire_due(later), 1)
        self.assertEqual(services.expire_due(later), 0)
        self.assertNotIn("frame_lantern", [e["item"].code for e in services.owned_items(self.user, later)])
        self.assertFalse(EquippedCosmetic.objects.exists())
        expired = ItemTransaction.objects.get(type="expired")
        self.assertEqual((expired.quantity, expired.quantity_after), (-1, 0))

    def test_a_permanent_copy_outlives_a_timed_one(self):
        now = timezone.now()
        self.grant("frame_palm", key="timed", days=1, now=now)
        self.grant("frame_palm", key="forever")
        services.equip(self.user, "frame", "frame_palm", now=now)
        later = now + timedelta(days=2)
        services.expire_due(later)
        self.assertEqual(services.cosmetics_payload(self.user, later)["frame"], "frame_palm")


class WearingTests(ItemTestCase):
    def test_slots_start_with_the_first_starter_and_no_frame(self):
        self.assertEqual(
            services.cosmetics_payload(self.user),
            {"dice": "dice_ivory", "board": "board_majlis", "frame": None},
        )

    def test_equip_checks_slot_and_ownership(self):
        def refused(slot, code):
            with self.assertRaises(services.ItemError) as caught:
                services.equip(self.user, slot, code)
            return caught.exception.code

        self.assertEqual(refused("dice", "dice_pearl"), "not_owned")
        self.assertEqual(refused("frame", "dice_ivory"), "wrong_slot")
        self.assertEqual(refused("hat", "dice_ivory"), "unknown_slot")
        self.grant("dice_pearl")
        view = services.equip(self.user, "dice", "dice_pearl")
        self.assertEqual(view["equipped"]["dice"], "dice_pearl")
        self.assertEqual(view["cosmetics"]["dice"], "dice_pearl")
        services.equip(self.user, "frame", "frame_brass")
        self.assertEqual(services.equip(self.user, "frame", None)["cosmetics"]["frame"], None)

    def test_the_account_hears_about_changes(self):
        with self.captureOnCommitCallbacks(execute=True):
            services.equip(self.user, "board", "board_oasis")
        channel, kind, data = self.publish.call_args.args
        self.assertEqual((channel, kind), (f"user/{self.user.player_id}", "cosmetics_changed"))
        self.assertEqual(data["cosmetics"]["board"], "board_oasis")
        with self.captureOnCommitCallbacks(execute=True):
            self.grant("dice_ruby")
        self.assertEqual(self.publish.call_args.args[1], "inventory_changed")

    def test_cosmetics_for_many_accounts(self):
        other = User.objects.create_guest()
        services.equip(other, "dice", "dice_desert_gold")
        worn = services.cosmetics_for_users([self.user.pk, other.pk])
        self.assertEqual(worn[self.user.pk]["dice"], "dice_ivory")
        self.assertEqual(worn[other.pk]["dice"], "dice_desert_gold")


class ItemsApiTests(ItemTestCase):
    def setUp(self):
        super().setUp()
        self.api = APIClient()
        access = account_tokens.start_session(self.user, device_id="d", platform="other").access
        self.api.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    def test_my_items_and_equip(self):
        r = self.api.get("/api/me/items/")
        self.assertEqual(r.status_code, 200)
        dice = [i for i in r.data["items"] if i["slot"] == "dice"]
        self.assertEqual([d["code"] for d in dice], ["dice_ivory", "dice_desert_gold"])
        self.assertEqual(
            {k: dice[1][k] for k in ("name", "rarity", "asset", "quantity", "expires_at", "starter")},
            {"name": "Desert Gold", "rarity": "rare", "asset": "dice_desert_gold",
             "quantity": 1, "expires_at": None, "starter": True},
        )
        r = self.api.post("/api/me/items/equip/", {"slot": "dice", "item": "dice_desert_gold"}, format="json")
        self.assertEqual((r.status_code, r.data["equipped"]["dice"]), (200, "dice_desert_gold"))
        # The account shows it too (and so does everyone's room).
        self.assertEqual(self.api.get("/api/me/").data["cosmetics"]["dice"], "dice_desert_gold")

    def test_refusals_have_codes(self):
        r = self.api.post("/api/me/items/equip/", {"slot": "dice", "item": "dice_pearl"}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (409, "not_owned"))
        r = self.api.post("/api/me/items/equip/", {"slot": "dice", "item": "nope"}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (404, "unknown_item"))
        r = self.api.post("/api/me/items/equip/", {"slot": "hat", "item": "dice_ivory"}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (400, "invalid_input"))
        self.assertEqual(APIClient().get("/api/me/items/").status_code, 401)


from game.models import Player  # noqa: E402
from game.services import players_payload  # noqa: E402
from game.tests import GameApiTestCase  # noqa: E402


class RoomCosmeticsTests(GameApiTestCase):
    def test_everyone_at_the_table_sees_your_dice(self):
        code, host = self.create_room()
        guest = self.join(code)
        services.equip(Player.objects.get(id=guest).user, "dice", "dice_desert_gold")
        self.start(code, host)
        players = {p["id"]: p for p in players_payload(Player.objects.get(id=host).room)}
        self.assertEqual(players[guest]["cosmetics"]["dice"], "dice_desert_gold")
        self.assertEqual(players[host]["cosmetics"]["dice"], "dice_ivory")
