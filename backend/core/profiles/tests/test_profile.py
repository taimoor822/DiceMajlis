"""Profiles: created with every account, edited by their owner, shown in /api/me."""

from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts import tokens
from accounts.models import User
from profiles import choices
from profiles.levels import level_for_xp, level_progress, xp_for_level
from profiles.models import Profile

LOCAL_CACHE = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}


@override_settings(CACHES=LOCAL_CACHE)
class ProfileApiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.api = APIClient()
        self.user = User.objects.create_guest()
        access = tokens.start_session(self.user, device_id="device-0001", platform="web").access
        self.auth = {"HTTP_AUTHORIZATION": f"Bearer {access}"}

    def patch(self, **changes):
        return self.api.patch("/api/me/profile/", changes, format="json", **self.auth)

    def me(self):
        return self.api.get("/api/me/", **self.auth).data

    def test_every_account_gets_a_profile_with_defaults(self):
        profile = Profile.objects.get(user=self.user)
        last4 = f"{self.user.player_id % 10000:04d}"
        self.assertEqual(profile.display_name, f"Player {last4}")
        self.assertIn(profile.avatar, choices.AVATARS)
        me = self.me()
        self.assertEqual(me["display_name"], f"Player {last4}")
        self.assertEqual((me["country"], me["languages"]), (None, []))
        self.assertEqual(
            (me["level"], me["xp"], me["level_xp"], me["next_level_xp"]), (1, 0, 0, 100)
        )

    def test_change_name_avatar_country_and_languages(self):
        r = self.patch(display_name="  Sara   Al  Majlis ", avatar="dhow", country="bh", languages=["ar", "en", "ar"])
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["display_name"], "Sara Al Majlis")
        self.assertEqual(r.data["avatar"], "dhow")
        self.assertEqual(r.data["country"], "BH")
        self.assertEqual(r.data["languages"], ["ar", "en"])
        self.assertEqual(User.objects.get(pk=self.user.pk).public_name, "Sara Al Majlis")

    def test_only_what_is_sent_changes(self):
        self.patch(country="PK")
        r = self.patch(avatar="moon")
        self.assertEqual((r.data["country"], r.data["avatar"]), ("PK", "moon"))
        r = self.patch(country="")
        self.assertIsNone(r.data["country"])

    def test_names_in_any_script(self):
        for name in ("سارة", "علی رضا", "ਸਤਿ", "O'Neil-2", "Ali_99"):
            r = self.patch(display_name=name)
            self.assertEqual((r.status_code, r.data["display_name"]), (200, name), name)

    def test_bad_names_say_why(self):
        cases = {
            "A": "name_length",
            "x" * 21: "name_length",
            "   ": "name_length",
            "Sara 🎲": "name_characters",
            "Sa​ra": "name_characters",
            "12345": "name_characters",
            "Dice Majlis": "name_not_allowed",
            "The ADMIN": "name_not_allowed",
        }
        for name, code in cases.items():
            r = self.patch(display_name=name)
            self.assertEqual(r.status_code, 400, name)
            self.assertEqual(r.data["fields"]["display_name"], [code], name)

    def test_only_known_choices(self):
        self.assertEqual(self.patch(avatar="dragon").data["fields"]["avatar"], ["invalid_choice"])
        self.assertEqual(self.patch(country="ZZ").data["fields"]["country"], ["invalid_choice"])
        r = self.patch(languages=["en", "xx"])
        self.assertIn("languages", r.data["fields"])
        r = self.patch(languages=["en", "ar", "ur", "pa", "en"])
        self.assertEqual(r.data["fields"]["languages"], ["max_length"])

    def test_xp_and_level_come_from_the_server(self):
        Profile.objects.filter(user=self.user).update(xp=350)
        me = self.me()
        self.assertEqual(
            (me["level"], me["xp"], me["level_xp"], me["next_level_xp"]), (3, 350, 300, 600)
        )
        r = self.patch(xp=99999, level=50)  # not changeable from the app
        self.assertEqual(r.data["xp"], 350)

    def test_needs_a_sign_in(self):
        r = self.api.patch("/api/me/profile/", {"avatar": "moon"}, format="json")
        self.assertEqual((r.status_code, r.data["code"]), (401, "not_authenticated"))

    def test_options_list_the_choices(self):
        r = self.api.get("/api/profile/options/")
        self.assertEqual(r.data["avatars"], list(choices.AVATARS))
        self.assertEqual(r.data["languages"], ["en", "ar", "ur", "pa"])
        self.assertEqual((r.data["name_min_length"], r.data["name_max_length"]), (2, 20))

    def test_new_names_are_used_in_new_rooms(self):
        self.patch(display_name="Sara")
        r = self.api.post("/api/game/create-room/", {"max_players": 2}, format="json", **self.auth)
        self.assertEqual(r.data["player"]["name"], "Sara")


class LevelTests(TestCase):
    def test_each_level_needs_100_more_xp(self):
        self.assertEqual([xp_for_level(n) for n in range(1, 6)], [0, 100, 300, 600, 1000])
        for xp, level in ((0, 1), (99, 1), (100, 2), (299, 2), (300, 3), (999, 4), (1000, 5)):
            self.assertEqual(level_for_xp(xp), level, xp)
        self.assertEqual(level_for_xp(-5), 1)
        for xp in range(0, 20000, 37):
            progress = level_progress(xp)
            self.assertLessEqual(progress["level_xp"], xp)
            self.assertLess(xp, progress["next_level_xp"])
