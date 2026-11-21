"""Achievements (step 2.4): unlocked from real progress, once, with their reward."""

from datetime import datetime, timedelta, timezone as dt_timezone
from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.test import TestCase
from rest_framework.test import APIClient

from accounts import tokens as account_tokens
from accounts.models import User
from events.models import DomainEvent
from events.outbox import dispatch_pending
from game.models import Player
from game.test_rooms import RoomTestCase
from profiles.xp import add_xp
from progress import services
from progress.models import Achievement, AchievementTier, AchievementUnlock
from stats.services import record_result
from wallet.services import balances

T0 = datetime(2026, 11, 21, 12, 0, tzinfo=dt_timezone.utc)


class AchievementTestCase(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()
        self.games = 0
        patcher = mock.patch("realtime.publish.publish")
        self.publish = patcher.start()
        self.addCleanup(patcher.stop)

    def play(self, place, room="ABC123"):
        self.games += 1
        record_result(
            self.user, game_id=self.games, room_code=room, game_type="ludo", variant="classic",
            place=place, player_count=2, forfeited=False, finished_at=T0 + timedelta(minutes=self.games),
        )
        dispatch_pending(min_age_seconds=0, now=T0 + timedelta(days=1))

    def unlocked(self):
        return sorted(
            f"{u.tier.achievement.code}:{u.tier.threshold}"
            for u in AchievementUnlock.objects.filter(user=self.user).select_related("tier__achievement")
        )


class UnlockTests(AchievementTestCase):
    def test_the_first_win_unlocks_two_tiers_and_pays_once(self):
        self.play(1)
        self.assertEqual(self.unlocked(), ["games_played:1", "wins:1"])
        self.assertEqual(balances(self.user)["gold"], 150)  # 50 + 100
        # Checking again (another event, the command) changes nothing.
        self.assertEqual(services.check(self.user), [])
        self.assertEqual(balances(self.user)["gold"], 150)

    def test_streak_tiers_follow_the_best_streak(self):
        for place in (1, 1, 2, 1, 1, 1):
            self.play(place)
        self.assertIn("win_streak:3", self.unlocked())
        self.assertNotIn("win_streak:5", self.unlocked())

    def test_the_level_comes_from_xp(self):
        add_xp(self.user, 1000, reason="game", idempotency_key="k", now=T0)  # level 5
        dispatch_pending(min_age_seconds=0, now=T0 + timedelta(days=1))
        self.assertEqual(self.unlocked(), ["level:5"])

    def test_the_account_hears_and_an_event_is_kept_for_later(self):
        with self.captureOnCommitCallbacks(execute=True):
            services.check(self.user)  # nothing yet
            record_result(
                self.user, game_id=1, room_code="QX7P2M", game_type="ludo", variant="classic",
                place=1, player_count=2, forfeited=False, finished_at=T0,
            )
        pushes = [c.args[2] for c in self.publish.call_args_list if c.args[1] == "achievement_unlocked"]
        self.assertEqual(
            {(p["code"], p["tier"], p["threshold"], p["room_code"]) for p in pushes},
            {("games_played", 1, 1, "QX7P2M"), ("wins", 1, 1, "QX7P2M")},
        )
        gold = {p["code"]: p["reward"]["gold"] for p in pushes}
        self.assertEqual(gold, {"games_played": 50, "wins": 100})
        self.assertEqual(DomainEvent.objects.filter(kind="achievement_unlocked").count(), 2)

    def test_inactive_achievements_never_unlock(self):
        Achievement.objects.filter(code="wins").update(active=False)
        self.play(1)
        self.assertEqual(self.unlocked(), ["games_played:1"])

    def test_the_command_unlocks_what_players_already_qualify_for(self):
        self.play(1)
        new = Achievement.objects.create(code="early", name="Early", description="d", metric="games_played")
        AchievementTier.objects.create(achievement=new, threshold=1, reward={"gold": 5})
        out = StringIO()
        call_command("check_achievements", stdout=out)
        self.assertIn("Unlocked 1", out.getvalue())
        self.assertIn("early:1", self.unlocked())


class PayloadTests(AchievementTestCase):
    def test_progress_and_hidden_achievements(self):
        for place in (1, 2, 1):
            self.play(place)
        payload = services.achievements_payload(self.user)
        codes = [a["code"] for a in payload["achievements"]]
        self.assertEqual(codes, ["games_played", "wins", "win_streak", "level"])
        self.assertEqual(payload["hidden_left"], 1)  # Majlis Legend
        wins = payload["achievements"][1]
        self.assertEqual(
            {k: wins[k] for k in ("value", "unlocked_tiers", "next_threshold", "completed")},
            {"value": 2, "unlocked_tiers": 1, "next_threshold": 10, "completed": False},
        )
        self.assertIsNotNone(wins["tiers"][0]["unlocked_at"])
        self.assertIsNone(wins["tiers"][1]["unlocked_at"])
        self.assertEqual(wins["tiers"][1]["reward"]["gold"], 300)
        self.assertEqual([i["name"] for i in wins["tiers"][1]["reward"]["items"]], ["Night Sky"])
        self.assertEqual(payload["unlocked_tiers"], 2)
        self.assertEqual(payload["total_tiers"], 13)

    def test_the_api(self):
        api = APIClient()
        api.credentials(
            HTTP_AUTHORIZATION=f"Bearer {account_tokens.start_session(self.user, device_id='d', platform='other').access}"
        )
        r = api.get("/api/me/achievements/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["unlocked_tiers"], 0)
        self.assertEqual(APIClient().get("/api/me/achievements/").status_code, 401)


class GameAchievementTests(RoomTestCase):
    def setUp(self):
        super().setUp()
        patcher = mock.patch("realtime.publish.publish")
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_a_real_win_unlocks_and_pays(self):
        code, host = self.create_room()
        guest = self.join(code)
        self.start(code, host)
        self.finish_game(code, host)
        for _ in range(4):  # game_finished -> stats -> achievements
            dispatch_pending(min_age_seconds=0)
        winner = Player.objects.get(id=host).user
        loser = Player.objects.get(id=guest).user
        self.assertEqual(AchievementUnlock.objects.filter(user=winner).count(), 2)
        self.assertEqual(AchievementUnlock.objects.filter(user=loser).count(), 1)  # first game
        self.assertEqual((balances(winner)["gold"], balances(loser)["gold"]), (150, 50))

    def test_games_with_the_ai_unlock_nothing(self):
        code, host = self.create_room()
        self.start(code, host)
        self.finish_game(code, host)
        for _ in range(4):
            dispatch_pending(min_age_seconds=0)
        self.assertFalse(AchievementUnlock.objects.exists())
