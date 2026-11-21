"""
Google and Apple sign-in (step 1.15): the server checks the ID token's
signature, audience, issuer, expiry (and Apple's nonce) before trusting it,
and a guest can attach Google/Apple later without losing anything.

The providers' keys are made here (an RSA key pair) and served by a fake JWKS
fetch, so no test touches the network.
"""

import hashlib
import time
from unittest import mock

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from django.core.cache import cache
from django.test import override_settings

from accounts import social
from accounts.models import SocialAccount, User
from wallet.services import balances

from .test_auth import DEVICE, AuthTestCase

GOOGLE_APP = "1234-android.apps.googleusercontent.com"
APPLE_APP = "com.dicemajlis.app"


def _key_pair():
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return private, private.public_key()


PROVIDER_KEY, PROVIDER_PUBLIC = _key_pair()
OTHER_KEY, _ = _key_pair()


def jwks(kid="key-1", public=PROVIDER_PUBLIC):
    jwk = jwt.algorithms.RSAAlgorithm.to_jwk(public, as_dict=True)
    return {"keys": [{**jwk, "kid": kid, "alg": "RS256", "use": "sig"}]}


def id_token(
    *,
    provider="google",
    sub="google-user-1",
    aud=GOOGLE_APP,
    iss=None,
    email="sara@example.com",
    verified=True,
    expires_in=600,
    key=PROVIDER_KEY,
    kid="key-1",
    **extra,
):
    now = int(time.time())
    claims = {
        "iss": iss or ("https://accounts.google.com" if provider == "google" else "https://appleid.apple.com"),
        "aud": aud,
        "sub": sub,
        "iat": now,
        "exp": now + expires_in,
        **({"email": email} if email else {}),
        "email_verified": verified if provider == "google" else ("true" if verified else "false"),
        **extra,
    }
    return jwt.encode(claims, key, algorithm="RS256", headers={"kid": kid})


@override_settings(GOOGLE_CLIENT_IDS=f"{GOOGLE_APP}, 1234-ios.apps.googleusercontent.com", APPLE_CLIENT_IDS=APPLE_APP)
class SocialTestCase(AuthTestCase):
    def setUp(self):
        super().setUp()
        self.keys = {"google": jwks(), "apple": jwks()}
        patcher = mock.patch.object(social, "_fetch_jwks", side_effect=self._fetch)
        self.fetch = patcher.start()
        self.addCleanup(patcher.stop)

    def _fetch(self, url):
        return self.keys["apple" if "apple" in url else "google"]

    def sign_in(self, token, provider="google", device_id=DEVICE, **extra):
        return self.api.post(
            f"/api/auth/social/{provider}/",
            {"id_token": token, "device_id": device_id, "platform": "android", **extra},
            format="json",
        )

    def link(self, access, token, provider="google", **extra):
        return self.api.post(
            f"/api/me/link/{provider}/",
            {"id_token": token, **extra},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {access}",
        )


class SignInTests(SocialTestCase):
    def test_a_new_google_user_gets_an_account_then_the_same_one_again(self):
        r = self.sign_in(id_token())
        self.assertEqual(r.status_code, 201, r.data)
        account = r.data["account"]
        self.assertFalse(account["is_guest"])
        self.assertEqual(account["linked"], ["google"])
        self.assertEqual(account["email"], "sara@example.com")
        user = User.objects.get(player_id=account["player_id"])
        self.assertFalse(user.has_usable_password())

        again = self.sign_in(id_token(), device_id="another-phone-1")
        self.assertEqual(again.status_code, 200)
        self.assertEqual(again.data["account"]["player_id"], account["player_id"])
        self.assertEqual(user.sessions.count(), 2)

    def test_the_account_is_found_by_the_provider_user_not_the_email(self):
        first = self.sign_in(id_token(email="old@example.com")).data["account"]
        changed = self.sign_in(id_token(email="new@example.com")).data["account"]
        self.assertEqual(first["player_id"], changed["player_id"])

    def test_apple_with_its_nonce(self):
        nonce = "random-value-from-the-app"
        hashed = hashlib.sha256(nonce.encode()).hexdigest()
        token = id_token(provider="apple", sub="apple-1", aud=APPLE_APP, nonce=hashed)
        r = self.sign_in(token, provider="apple", nonce=nonce)
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(r.data["account"]["linked"], ["apple"])
        refused = self.sign_in(token, provider="apple", nonce="another-value")
        self.assertEqual((refused.status_code, refused.data["code"]), (401, "invalid_nonce"))
        refused = self.sign_in(token, provider="apple")
        self.assertEqual(refused.data["code"], "invalid_nonce")

    def test_an_email_that_already_has_an_account(self):
        User.objects.create_email_user("sara@example.com", "a-long-password-1")
        r = self.sign_in(id_token())
        self.assertEqual((r.status_code, r.data["code"]), (409, "email_taken"))
        self.assertFalse(SocialAccount.objects.exists())
        # An unverified email is not claimed (and doesn't block either).
        r = self.sign_in(id_token(sub="google-user-2", verified=False))
        self.assertEqual(r.status_code, 201)
        self.assertIsNone(r.data["account"]["email"])


class TokenCheckTests(SocialTestCase):
    def code_for(self, token, provider="google", **extra):
        r = self.sign_in(token, provider=provider, **extra)
        self.assertNotIn(r.status_code, (200, 201))
        return r.status_code, r.data["code"]

    def test_tokens_that_are_refused(self):
        self.assertEqual(self.code_for(id_token(aud="someone-elses-app")), (401, "wrong_audience"))
        self.assertEqual(self.code_for(id_token(iss="https://evil.example")), (401, "wrong_issuer"))
        self.assertEqual(self.code_for(id_token(expires_in=-120)), (401, "token_expired"))
        self.assertEqual(self.code_for(id_token(key=OTHER_KEY)), (401, "invalid_token"))
        self.assertEqual(self.code_for(id_token(kid="unknown")), (401, "invalid_token"))
        self.assertEqual(self.code_for("not-a-token"), (401, "invalid_token"))
        # An Apple token is not a Google one.
        apple = id_token(provider="apple", aud=APPLE_APP)
        self.assertEqual(self.code_for(apple), (401, "wrong_issuer"))
        self.assertFalse(User.objects.exists())

    def test_unsigned_and_hs256_tokens_are_refused(self):
        claims = {"iss": "https://accounts.google.com", "aud": GOOGLE_APP, "sub": "x",
                  "iat": int(time.time()), "exp": int(time.time()) + 600}
        unsigned = jwt.encode(claims, None, algorithm="none", headers={"kid": "key-1"})
        self.assertEqual(self.code_for(unsigned), (401, "invalid_token"))
        # "Key confusion": signed with HMAC using the public key as the secret.
        public_pem = PROVIDER_PUBLIC.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        confused = jwt.encode(claims, public_pem.decode()[:32], algorithm="HS256", headers={"kid": "key-1"})
        self.assertEqual(self.code_for(confused), (401, "invalid_token"))

    def test_keys_are_cached_and_fetched_again_after_a_rotation(self):
        self.sign_in(id_token())
        self.sign_in(id_token())
        self.assertEqual(self.fetch.call_count, 1)
        new_key, new_public = _key_pair()
        self.keys["google"] = jwks(kid="key-2", public=new_public)
        r = self.sign_in(id_token(key=new_key, kid="key-2"))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self.fetch.call_count, 2)

    def test_the_provider_cannot_be_reached(self):
        cache.clear()
        self.fetch.side_effect = OSError("no network")
        self.assertEqual(self.code_for(id_token()), (503, "provider_unreachable"))

    @override_settings(GOOGLE_CLIENT_IDS="", APPLE_CLIENT_IDS="")
    def test_not_configured_and_unknown_providers(self):
        self.assertEqual(self.code_for(id_token()), (503, "provider_not_configured"))
        self.assertEqual(self.code_for(id_token(), provider="facebook"), (404, "unknown_provider"))
        r = self.api.get("/api/auth/providers/")
        self.assertEqual(r.data, {"google": False, "apple": False})

    def test_which_providers_are_set_up(self):
        r = self.api.get("/api/auth/providers/")
        self.assertEqual(r.data, {"google": True, "apple": True})


class LinkTests(SocialTestCase):
    def test_a_guest_links_google_and_keeps_everything(self):
        guest = self.guest()
        access = guest["access"]
        player_id = guest["account"]["player_id"]
        claim = self.api.post("/api/rewards/daily/claim/", HTTP_AUTHORIZATION=f"Bearer {access}")
        self.assertIn(claim.status_code, (200, 201))
        gold = balances(User.objects.get(player_id=player_id))["gold"]
        self.assertGreater(gold, 0)

        r = self.link(access, id_token())
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual((r.data["player_id"], r.data["is_guest"]), (player_id, False))
        self.assertEqual(r.data["linked"], ["google"])
        self.assertEqual(r.data["email"], "sara@example.com")

        # A new phone signs in with Google: the same account, gold and all.
        other = self.sign_in(id_token(), device_id="new-phone-123")
        self.assertEqual(other.status_code, 200)
        self.assertEqual(other.data["account"]["player_id"], player_id)
        self.assertEqual(balances(User.objects.get(player_id=player_id))["gold"], gold)
        # Linking again is fine; and Apple can be added too.
        self.assertEqual(self.link(access, id_token()).status_code, 200)
        r = self.link(access, id_token(provider="apple", sub="apple-9", aud=APPLE_APP), provider="apple")
        self.assertEqual(r.data["linked"], ["apple", "google"])

    def test_one_google_user_belongs_to_one_account(self):
        self.sign_in(id_token())  # someone already plays with this Google user
        access = self.guest()["access"]
        r = self.link(access, id_token())
        self.assertEqual((r.status_code, r.data["code"]), (409, "social_account_taken"))
        self.link(access, id_token(sub="google-user-2"))
        r = self.link(access, id_token(sub="google-user-3"))
        self.assertEqual((r.status_code, r.data["code"]), (409, "already_linked"))

    def test_linking_needs_a_good_token_and_a_signed_in_player(self):
        access = self.guest()["access"]
        r = self.link(access, id_token(aud="another-app"))
        self.assertEqual((r.status_code, r.data["code"]), (401, "wrong_audience"))
        r = self.api.post("/api/me/link/google/", {"id_token": id_token()}, format="json")
        self.assertEqual(r.status_code, 401)

    def test_unlink_only_when_another_way_to_sign_in_is_left(self):
        r = self.sign_in(id_token())
        access = r.data["access"]
        refused = self.api.post("/api/me/unlink/google/", HTTP_AUTHORIZATION=f"Bearer {access}")
        self.assertEqual((refused.status_code, refused.data["code"]), (409, "last_sign_in_method"))
        self.link(access, id_token(provider="apple", sub="apple-1", aud=APPLE_APP), provider="apple")
        done = self.api.post("/api/me/unlink/google/", HTTP_AUTHORIZATION=f"Bearer {access}")
        self.assertEqual((done.status_code, done.data["linked"]), (200, ["apple"]))
        gone = self.api.post("/api/me/unlink/google/", HTTP_AUTHORIZATION=f"Bearer {access}")
        self.assertEqual((gone.status_code, gone.data["code"]), (404, "not_linked"))
