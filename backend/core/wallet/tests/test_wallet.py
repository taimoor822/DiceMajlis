"""The wallet ledger: balances change only through post(), append-only, idempotent."""

from io import StringIO

from django.contrib.admin.sites import AdminSite
from django.core.cache import cache
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import IntegrityError, transaction
from django.test import RequestFactory, TestCase, override_settings
from rest_framework.test import APIClient

from accounts import tokens
from accounts.models import User
from wallet import services
from wallet.admin import WalletAdjustmentAdmin, WalletAdjustmentForm
from wallet.models import (
    LedgerIsAppendOnly,
    TransactionType,
    WalletAccount,
    WalletAdjustment,
    WalletTransaction,
)

LOCAL_CACHE = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
GRANT = TransactionType.ADMIN_GRANT


class PostTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()

    def test_new_players_have_zero_of_everything(self):
        self.assertEqual(services.balances(self.user), {"gold": 0, "diamond": 0})

    def test_post_adds_one_entry_and_updates_the_balance(self):
        entry = services.post(self.user, "gold", 500, GRANT, "k1", source="test")
        self.assertEqual((entry.amount, entry.balance_before, entry.balance_after), (500, 0, 500))
        self.assertEqual(entry.sequence, 1)
        self.assertTrue(entry.reference.startswith("TXN-"))
        services.post(self.user, "gold", -200, TransactionType.ADMIN_REVOKE, "k2")
        services.post(self.user, "diamond", 5, GRANT, "k3")
        self.assertEqual(services.balances(self.user), {"gold": 300, "diamond": 5})
        self.assertEqual(WalletTransaction.objects.count(), 3)

    def test_the_same_key_twice_is_one_entry(self):
        first = services.post(self.user, "gold", 100, GRANT, "same")
        again = services.post(self.user, "gold", 100, GRANT, "same")
        self.assertEqual(first.id, again.id)
        self.assertEqual(services.balances(self.user)["gold"], 100)
        with self.assertRaises(services.IdempotencyConflict):
            services.post(self.user, "gold", 999, GRANT, "same")

    def test_keys_are_per_account(self):
        services.post(self.user, "gold", 100, GRANT, "same")
        services.post(self.user, "diamond", 1, GRANT, "same")
        other = User.objects.create_guest()
        services.post(other, "gold", 100, GRANT, "same")
        self.assertEqual(WalletTransaction.objects.count(), 3)

    def test_balances_never_go_below_zero(self):
        services.post(self.user, "gold", 50, GRANT, "k1")
        with self.assertRaises(services.InsufficientFunds):
            services.post(self.user, "gold", -51, TransactionType.ADMIN_REVOKE, "k2")
        self.assertEqual(services.balances(self.user)["gold"], 50)
        self.assertEqual(WalletTransaction.objects.count(), 1)

    def test_the_database_refuses_negative_balances_too(self):
        account = WalletAccount.objects.create(user=self.user, currency="gold")
        with self.assertRaises(IntegrityError), transaction.atomic():
            WalletAccount.objects.filter(pk=account.pk).update(balance=-1)

    def test_bad_requests_are_refused(self):
        for currency, amount, kind, key in (
            ("coins", 1, GRANT, "a"),
            ("gold", 0, GRANT, "a"),
            ("gold", 1.5, GRANT, "a"),
            ("gold", True, GRANT, "a"),
            ("gold", 1, "made_up", "a"),
            ("gold", 1, GRANT, ""),
        ):
            with self.assertRaises(ValueError):
                services.post(self.user, currency, amount, kind, key)

    def test_entries_cant_be_changed_or_deleted(self):
        entry = services.post(self.user, "gold", 10, GRANT, "k1")
        entry.amount = 1_000_000
        with self.assertRaises(LedgerIsAppendOnly):
            entry.save()
        with self.assertRaises(LedgerIsAppendOnly):
            entry.delete()

    def test_a_reversal_undoes_an_entry_with_a_new_one(self):
        entry = services.post(self.user, "gold", 300, GRANT, "k1")
        reversal = services.reverse(entry, "granted by mistake", "undo-k1")
        self.assertEqual((reversal.amount, reversal.type), (-300, "reversal"))
        self.assertEqual(reversal.reference_id, str(entry.id))
        self.assertEqual(services.balances(self.user)["gold"], 0)
        self.assertEqual(WalletTransaction.objects.count(), 2)


class AuditTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()
        services.post(self.user, "gold", 100, GRANT, "k1")
        services.post(self.user, "gold", 50, GRANT, "k2")

    def test_a_clean_ledger_passes(self):
        self.assertEqual(services.audit(), [])
        out = StringIO()
        call_command("audit_wallets", stdout=out)
        self.assertIn("match", out.getvalue())

    def test_a_tampered_balance_is_found(self):
        WalletAccount.objects.update(balance=999)
        problems = services.audit()
        self.assertEqual(len(problems), 1)
        self.assertIn("ledger says 150", problems[0])
        with self.assertRaises(CommandError):
            call_command("audit_wallets", stdout=StringIO(), stderr=StringIO())

    def test_a_missing_entry_is_found(self):
        WalletTransaction.objects.filter(sequence=1).update(sequence=7)  # simulate a gap
        self.assertTrue(any("missing" in p for p in services.audit()))


class AdminAdjustmentTests(TestCase):
    def setUp(self):
        self.player = User.objects.create_guest()
        self.staff = User.objects.create_superuser("staff", "Very-long-pass-123")
        self.admin = WalletAdjustmentAdmin(WalletAdjustment, AdminSite())

    def adjust(self, amount, currency="gold"):
        form = WalletAdjustmentForm(
            data={"user": self.player.pk, "currency": currency, "amount": amount, "reason": "event prize"}
        )
        if not form.is_valid():
            return form
        request = RequestFactory().post("/")
        request.user = self.staff
        obj = form.save(commit=False)
        self.admin.save_model(request, obj, form, change=False)
        return obj

    def test_a_grant_posts_one_entry_with_who_and_why(self):
        adjustment = self.adjust(1000)
        entry = adjustment.transaction
        self.assertEqual((entry.amount, entry.type), (1000, "admin_grant"))
        self.assertEqual(entry.metadata, {"reason": "event prize", "by": "staff"})
        self.assertEqual(adjustment.created_by, self.staff)
        self.assertEqual(services.balances(self.player)["gold"], 1000)

    def test_taking_back_more_than_the_player_has_is_refused(self):
        self.adjust(100)
        form = self.adjust(-101)
        self.assertIn("amount", form.errors)
        revoke = self.adjust(-100)
        self.assertEqual(revoke.transaction.type, "admin_revoke")
        self.assertEqual(services.balances(self.player)["gold"], 0)

    def test_zero_is_refused(self):
        self.assertIn("amount", self.adjust(0).errors)


@override_settings(CACHES=LOCAL_CACHE)
class WalletApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_guest()
        access = tokens.start_session(self.user, device_id="device-0001", platform="web").access
        self.auth = {"HTTP_AUTHORIZATION": f"Bearer {access}"}
        self.api = APIClient()

    def test_balances(self):
        services.post(self.user, "diamond", 7, GRANT, "k1")
        r = self.api.get("/api/wallet/", **self.auth)
        self.assertEqual(r.data, {"balances": {"gold": 0, "diamond": 7}})

    def test_history_newest_first_a_page_at_a_time(self):
        for n in range(35):
            services.post(self.user, "gold", n + 1, GRANT, f"k{n}")
        other = User.objects.create_guest()
        services.post(other, "gold", 1, GRANT, "x")  # someone else's: never shown

        first = self.api.get("/api/wallet/transactions/", **self.auth).data
        self.assertEqual(len(first["transactions"]), 30)
        self.assertEqual(first["transactions"][0]["amount"], 35)
        entry = first["transactions"][0]
        self.assertEqual(
            set(entry), {"id", "reference", "currency", "amount", "balance_after", "type", "created_at"}
        )
        second = self.api.get(
            f"/api/wallet/transactions/?before={first['next']}", **self.auth
        ).data
        self.assertEqual([e["amount"] for e in second["transactions"]], [5, 4, 3, 2, 1])
        self.assertIsNone(second["next"])

    def test_bad_page_and_no_sign_in(self):
        r = self.api.get("/api/wallet/transactions/?before=nope", **self.auth)
        self.assertEqual(r.data["code"], "invalid_input")
        r = self.api.get("/api/wallet/")
        self.assertEqual((r.status_code, r.data["code"]), (401, "not_authenticated"))

    def test_the_app_cannot_change_balances(self):
        for method in ("post", "put", "patch", "delete"):
            r = getattr(self.api, method)("/api/wallet/", {"gold": 1000}, format="json", **self.auth)
            self.assertEqual(r.status_code, 405, method)
