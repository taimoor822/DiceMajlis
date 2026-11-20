"""
Guest sign-in, tokens and sessions: every rule from ARCHITECTURE §8 that the app
relies on, through the real HTTP endpoints.
"""

from datetime import timedelta
from unittest import mock

import jwt
from django.conf import settings
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from accounts import models as account_models
from accounts import tokens
from accounts.models import DeviceSession, User

DEVICE = "device-abc-123"
# Rate limits are counted in the cache; tests never need Redis.
LOCAL_CACHE = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}


@override_settings(CACHES=LOCAL_CACHE)
class AuthTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.api = APIClient()

    def guest(self, device_id=DEVICE, platform="android"):
        r = self.api.post(
            "/api/auth/guest/", {"device_id": device_id, "platform": platform}, format="json"
        )
        self.assertEqual(r.status_code, 201, r.data)
        return r.data

    def get_me(self, access):
        return self.api.get("/api/me/", HTTP_AUTHORIZATION=f"Bearer {access}")

    def refresh(self, token):
        return self.api.post("/api/auth/refresh/", {"refresh": token}, format="json")


class GuestSignInTests(AuthTestCase):
    def test_guest_gets_tokens_and_a_permanent_player_id(self):
        data = self.guest()
        self.assertEqual(data["token_type"], "Bearer")
        self.assertEqual(data["access_expires_in"], 15 * 60)
        account = data["account"]
        self.assertTrue(100_000_000 <= account["player_id"] <= 999_999_999)
        self.assertTrue(account["is_guest"])
        self.assertIsNone(account["active_room"])
        user = User.objects.get(player_id=account["player_id"])
        self.assertEqual(account["display_name"], user.public_name)
        session = user.sessions.get()
        self.assertEqual((session.device_id, session.platform), (DEVICE, "android"))

    def test_each_guest_is_a_new_account(self):
        first, second = self.guest()["account"], self.guest()["account"]
        self.assertNotEqual(first["player_id"], second["player_id"])

    def test_only_a_hash_of_the_refresh_token_is_stored(self):
        refresh = self.guest()["refresh"]
        session = DeviceSession.objects.get()
        secret = refresh.split(".", 1)[1]
        self.assertEqual(refresh.split(".", 1)[0], str(session.id))
        self.assertEqual(len(session.refresh_hash), 64)
        self.assertNotIn(secret, session.refresh_hash)

    def test_bad_input_is_refused(self):
        for body in ({}, {"device_id": "short"}, {"device_id": DEVICE, "platform": "fridge"}):
            r = self.api.post("/api/auth/guest/", body, format="json")
            self.assertEqual((r.status_code, r.data["code"]), (400, "invalid_input"), body)

    def test_player_ids_stay_in_range_and_retry_on_a_clash(self):
        taken = User.objects.create_guest().player_id
        with mock.patch.object(
            account_models, "new_player_id", side_effect=[taken, taken, 123_456_789]
        ):
            user = User.objects.create_guest()
        self.assertEqual(user.player_id, 123_456_789)

    def test_gives_up_when_every_player_id_is_taken(self):
        taken = User.objects.create_guest().player_id
        with mock.patch.object(account_models, "new_player_id", return_value=taken):
            with self.assertRaises(RuntimeError):
                User.objects.create_guest()

    @override_settings(AUTH_RATE_LIMITS={"guest_signup": "2/hour", "auth_refresh": "240/hour"})
    def test_guest_sign_ups_are_rate_limited_per_ip(self):
        self.guest()
        self.guest()
        r = self.api.post("/api/auth/guest/", {"device_id": DEVICE}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (429, "rate_limited"))
        self.assertGreater(r.data["retry_after"], 0)


class AccessTokenTests(AuthTestCase):
    def test_me_needs_a_valid_access_token(self):
        data = self.guest()
        r = self.get_me(data["access"])
        self.assertEqual((r.status_code, r.data["player_id"]), (200, data["account"]["player_id"]))

        r = self.api.get("/api/me/")
        self.assertEqual((r.status_code, r.data["code"]), (401, "not_authenticated"))
        self.assertEqual(r["WWW-Authenticate"], "Bearer")
        r = self.get_me("not-a-token")
        self.assertEqual((r.status_code, r.data["code"]), (401, "invalid_token"))

    def test_expired_access_token_says_so(self):
        self.guest()
        session = DeviceSession.objects.get()
        old = tokens.issue_access(session, now=timezone.now() - timedelta(minutes=16))
        r = self.get_me(old)
        self.assertEqual((r.status_code, r.data["code"]), (401, "token_expired"))

    def test_tokens_signed_with_another_key_are_refused(self):
        data = self.guest()
        claims = jwt.decode(data["access"], options={"verify_signature": False})
        forged = jwt.encode(claims, "someone-elses-key-" + "x" * 32, algorithm="HS256")
        r = self.get_me(forged)
        self.assertEqual((r.status_code, r.data["code"]), (401, "invalid_token"))

    def test_a_refresh_token_is_not_an_access_token(self):
        data = self.guest()
        r = self.get_me(data["refresh"])
        self.assertEqual((r.status_code, r.data["code"]), (401, "invalid_token"))

    def test_disabled_account_is_signed_out_at_once(self):
        data = self.guest()
        User.objects.update(is_active=False)
        r = self.get_me(data["access"])
        self.assertEqual((r.status_code, r.data["code"]), (401, "session_revoked"))
        r = self.refresh(data["refresh"])
        self.assertEqual((r.status_code, r.data["code"]), (401, "session_revoked"))


class RefreshTests(AuthTestCase):
    def test_refresh_rotates_the_refresh_token(self):
        data = self.guest()
        r = self.refresh(data["refresh"])
        self.assertEqual(r.status_code, 200, r.data)
        self.assertNotEqual(r.data["refresh"], data["refresh"])
        self.assertEqual(r.data["account"]["player_id"], data["account"]["player_id"])
        self.assertEqual(self.get_me(r.data["access"]).status_code, 200)
        # The new one works again.
        self.assertEqual(self.refresh(r.data["refresh"]).status_code, 200)

    def test_a_racing_second_refresh_is_refused_without_signing_out(self):
        data = self.guest()
        fresh = self.refresh(data["refresh"]).data
        r = self.refresh(data["refresh"])  # same old token, seconds later
        self.assertEqual((r.status_code, r.data["code"]), (401, "refresh_superseded"))
        self.assertEqual(self.refresh(fresh["refresh"]).status_code, 200)

    def test_reusing_an_old_refresh_token_ends_the_session(self):
        data = self.guest()
        fresh = self.refresh(data["refresh"]).data
        DeviceSession.objects.update(rotated_at=timezone.now() - timedelta(minutes=5))
        r = self.refresh(data["refresh"])  # a copied token comes back
        self.assertEqual((r.status_code, r.data["code"]), (401, "session_revoked"))
        self.assertEqual(DeviceSession.objects.get().revoked_reason, "refresh_reused")
        # The thief and the owner are both signed out.
        r = self.refresh(fresh["refresh"])
        self.assertEqual((r.status_code, r.data["code"]), (401, "session_revoked"))
        r = self.get_me(fresh["access"])
        self.assertEqual((r.status_code, r.data["code"]), (401, "session_revoked"))

    def test_expired_refresh_token_signs_out(self):
        data = self.guest()
        DeviceSession.objects.update(refresh_expires_at=timezone.now() - timedelta(seconds=1))
        r = self.refresh(data["refresh"])
        self.assertEqual((r.status_code, r.data["code"]), (401, "refresh_expired"))
        self.assertFalse(DeviceSession.objects.get().is_active)

    def test_unknown_or_malformed_refresh_tokens(self):
        data = self.guest()
        session_id = data["refresh"].split(".", 1)[0]
        for token in ("nonsense", f"{session_id}.wrong", f"{session_id}.", "a.b.c"):
            r = self.refresh(token)
            self.assertEqual((r.status_code, r.data["code"]), (401, "invalid_refresh"), token)
        r = self.api.post("/api/auth/refresh/", {}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (400, "invalid_input"))

    def test_refresh_does_not_need_an_access_token(self):
        data = self.guest()
        r = self.api.post(
            "/api/auth/refresh/",
            {"refresh": data["refresh"]},
            format="json",
            HTTP_AUTHORIZATION="Bearer expired-or-garbage",
        )
        self.assertEqual(r.status_code, 200)


class SignOutTests(AuthTestCase):
    def test_logout_signs_this_device_out(self):
        data = self.guest()
        auth = {"HTTP_AUTHORIZATION": f"Bearer {data['access']}"}
        self.assertEqual(self.api.post("/api/auth/logout/", **auth).status_code, 204)
        r = self.get_me(data["access"])
        self.assertEqual((r.status_code, r.data["code"]), (401, "session_revoked"))
        r = self.refresh(data["refresh"])
        self.assertEqual((r.status_code, r.data["code"]), (401, "session_revoked"))

    def test_logout_others_keeps_this_device(self):
        data = self.guest()
        user = User.objects.get(player_id=data["account"]["player_id"])
        other = tokens.start_session(user, device_id="other-phone", platform="ios")
        r = self.api.post(
            "/api/auth/logout-others/", HTTP_AUTHORIZATION=f"Bearer {data['access']}"
        )
        self.assertEqual((r.status_code, r.data), (200, {"signed_out": 1}))
        self.assertEqual(self.get_me(data["access"]).status_code, 200)
        self.assertEqual(self.get_me(other.access).status_code, 401)

    def test_logout_needs_a_sign_in(self):
        r = self.api.post("/api/auth/logout/")
        self.assertEqual((r.status_code, r.data["code"]), (401, "not_authenticated"))


class SettingsTests(TestCase):
    def test_lifetimes_match_the_design(self):
        self.assertEqual(settings.AUTH_ACCESS_TOKEN_LIFETIME, timedelta(minutes=15))
        self.assertEqual(settings.AUTH_REFRESH_TOKEN_LIFETIME, timedelta(days=30))
