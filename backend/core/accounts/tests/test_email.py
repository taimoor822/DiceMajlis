"""
Email accounts: sign up, sign in, a guest saving their account, and a forgotten
password reset with an emailed code.
"""

import re
from datetime import timedelta
from unittest import mock

from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from accounts import recovery
from accounts.models import DeviceSession, PasswordResetCode, User

LOCAL_CACHE = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
DEVICE = {"device_id": "device-abc-123", "platform": "ios"}
PASSWORD = "Majlis-night-2026"


@override_settings(CACHES=LOCAL_CACHE)
class EmailTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.api = APIClient()

    def post(self, path, access=None, **data):
        headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"} if access else {}
        return self.api.post(f"/api/{path}", data, format="json", **headers)

    def register(self, email="sara@example.com", password=PASSWORD):
        return self.post("auth/register/", email=email, password=password, **DEVICE)

    def login(self, email="sara@example.com", password=PASSWORD):
        return self.post("auth/login/", email=email, password=password, **DEVICE)


class RegisterTests(EmailTestCase):
    def test_sign_up_gives_tokens_and_a_player_id(self):
        r = self.register(email=" Sara@Example.COM ")
        self.assertEqual(r.status_code, 201, r.data)
        account = r.data["account"]
        self.assertFalse(account["is_guest"])
        self.assertEqual(account["email"], "sara@example.com")
        self.assertTrue(100_000_000 <= account["player_id"] <= 999_999_999)
        user = User.objects.get(email="sara@example.com")
        self.assertTrue(user.check_password(PASSWORD))
        self.assertEqual(user.sessions.get().platform, "ios")

    def test_an_email_has_one_account_whatever_the_case(self):
        self.register()
        r = self.register(email="SARA@example.com")
        self.assertEqual((r.status_code, r.data["code"]), (409, "email_taken"))

    def test_weak_passwords_say_why(self):
        r = self.register(password="123")
        self.assertEqual((r.status_code, r.data["code"]), (400, "invalid_input"))
        self.assertIn("password_too_short", r.data["fields"]["password"])
        self.assertIn("password_entirely_numeric", r.data["fields"]["password"])
        r = self.register(password="password")
        self.assertIn("password_too_common", r.data["fields"]["password"])
        r = self.register(email="saraexample@example.com", password="saraexample")
        self.assertIn("password_too_similar", r.data["fields"]["password"])

    def test_bad_email_is_refused(self):
        r = self.register(email="not-an-email")
        self.assertEqual(r.data["fields"]["email"], ["invalid"])


class LoginTests(EmailTestCase):
    def setUp(self):
        super().setUp()
        self.register()

    def test_sign_in_on_another_device(self):
        r = self.login(email="SARA@example.com")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(DeviceSession.objects.filter(revoked_at__isnull=True).count(), 2)
        me = self.api.get("/api/me/", HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
        self.assertEqual(me.data["email"], "sara@example.com")

    def test_wrong_password_or_unknown_email_look_the_same(self):
        for email, password in (("sara@example.com", "nope-nope-1"), ("who@example.com", PASSWORD)):
            r = self.login(email=email, password=password)
            self.assertEqual((r.status_code, r.data["code"]), (401, "invalid_credentials"))

    def test_guests_and_disabled_accounts_cant_sign_in_with_a_password(self):
        User.objects.filter(email="sara@example.com").update(is_active=False)
        r = self.login()
        self.assertEqual(r.data["code"], "invalid_credentials")

    def test_too_many_wrong_passwords_lock_the_email_for_a_while(self):
        for _ in range(10):
            self.login(password="wrong-password-1")
        r = self.login()  # even the right password waits now
        self.assertEqual((r.status_code, r.data["code"]), (429, "rate_limited"))
        self.assertGreater(r.data["retry_after"], 0)
        r = self.login(email="other@example.com")  # other emails aren't affected
        self.assertEqual(r.data["code"], "invalid_credentials")

    def test_a_right_password_clears_earlier_mistakes(self):
        for _ in range(9):
            self.login(password="wrong-password-1")
        self.assertEqual(self.login().status_code, 200)
        for _ in range(9):
            self.login(password="wrong-password-1")
        self.assertEqual(self.login().status_code, 200)

    @override_settings(
        AUTH_RATE_LIMITS={
            "guest_signup": "20/hour",
            "auth_refresh": "240/hour",
            "email_signup": "10/hour",
            "login": "3/hour",
            "password_reset": "20/hour",
        }
    )
    def test_sign_ins_are_rate_limited_per_ip(self):
        for _ in range(3):
            self.login()
        self.assertEqual(self.login().data["code"], "rate_limited")


class SaveAccountTests(EmailTestCase):
    def guest(self):
        r = self.post("auth/guest/", **DEVICE)
        return r.data["access"], r.data["account"]["player_id"]

    def test_a_guest_keeps_their_player_id_and_can_sign_in_later(self):
        access, player_id = self.guest()
        r = self.post("auth/save-account/", access, email="Guest@Example.com", password=PASSWORD)
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual((r.data["player_id"], r.data["is_guest"]), (player_id, False))
        self.assertEqual(r.data["email"], "guest@example.com")

        r = self.login(email="guest@example.com")
        self.assertEqual(r.data["account"]["player_id"], player_id)

    def test_the_email_must_be_free(self):
        self.register()
        access, _ = self.guest()
        r = self.post("auth/save-account/", access, email="sara@example.com", password=PASSWORD)
        self.assertEqual((r.status_code, r.data["code"]), (409, "email_taken"))
        self.assertTrue(User.objects.get(email__isnull=True).is_guest)

    def test_only_once_and_only_signed_in(self):
        access = self.register().data["access"]
        r = self.post("auth/save-account/", access, email="x@example.com", password=PASSWORD)
        self.assertEqual((r.status_code, r.data["code"]), (409, "already_saved"))
        r = self.post("auth/save-account/", email="x@example.com", password=PASSWORD)
        self.assertEqual((r.status_code, r.data["code"]), (401, "not_authenticated"))

    def test_weak_password_is_refused(self):
        access, _ = self.guest()
        r = self.post("auth/save-account/", access, email="g@example.com", password="short")
        self.assertIn("password_too_short", r.data["fields"]["password"])


class PasswordResetTests(EmailTestCase):
    def setUp(self):
        super().setUp()
        self.register()

    def ask(self, email="sara@example.com"):
        return self.post("auth/password-reset/", email=email)

    def emailed_code(self):
        return re.search(r"Your code is (\d{6})", mail.outbox[-1].body).group(1)

    def confirm(self, code, password="Desert-rose-2027", email="sara@example.com"):
        return self.post(
            "auth/password-reset/confirm/", email=email, code=code, new_password=password
        )

    def test_the_emailed_code_sets_a_new_password_and_signs_out_everywhere(self):
        old = self.login().data
        self.assertEqual(self.ask().data, {"status": "sent"})
        self.assertEqual(mail.outbox[-1].to, ["sara@example.com"])
        code = self.emailed_code()
        self.assertNotIn(code, PasswordResetCode.objects.get().code_hash)

        r = self.confirm(code)
        self.assertEqual((r.status_code, r.data), (200, {"status": "password_changed"}))
        self.assertEqual(self.login().data["code"], "invalid_credentials")
        self.assertEqual(self.login(password="Desert-rose-2027").status_code, 200)
        me = self.api.get("/api/me/", HTTP_AUTHORIZATION=f"Bearer {old['access']}")
        self.assertEqual(me.data["code"], "session_revoked")
        # Used once only.
        self.assertEqual(self.confirm(code).data["code"], "invalid_code")

    def test_unknown_emails_get_the_same_answer_and_no_email(self):
        self.assertEqual(self.ask("nobody@example.com").data, {"status": "sent"})
        self.assertEqual(mail.outbox, [])
        self.assertEqual(self.confirm("123456", email="nobody@example.com").data["code"], "invalid_code")

    def test_wrong_codes_run_out(self):
        self.ask()
        code = self.emailed_code()
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(4):
            self.assertEqual(self.confirm(wrong).data["code"], "invalid_code")
        self.assertEqual(self.confirm(wrong).data["code"], "too_many_attempts")
        self.assertEqual(self.confirm(code).data["code"], "too_many_attempts")

    def test_codes_expire(self):
        self.ask()
        code = self.emailed_code()
        PasswordResetCode.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.confirm(code).data["code"], "code_expired")

    def test_a_new_code_replaces_the_old_one(self):
        self.ask()
        first = self.emailed_code()
        self.ask()
        second = self.emailed_code()
        if first != second:
            self.assertEqual(self.confirm(first).data["code"], "invalid_code")
        self.assertEqual(self.confirm(second).status_code, 200)

    def test_only_a_few_emails_per_hour(self):
        for _ in range(7):
            self.ask()
        self.assertEqual(len(mail.outbox), 5)

    def test_the_new_password_must_be_strong(self):
        self.ask()
        r = self.confirm(self.emailed_code(), password="12345678")
        self.assertIn("password_entirely_numeric", r.data["fields"]["new_password"])

    def test_a_failing_email_server_still_answers(self):
        with mock.patch.object(recovery, "send_mail", side_effect=OSError("down")):
            with self.assertLogs("accounts.recovery", level="ERROR"):
                r = self.ask()
        self.assertEqual(r.status_code, 200)

    def test_code_must_be_six_digits(self):
        r = self.confirm("12ab56")
        self.assertEqual(r.data["code"], "invalid_input")
