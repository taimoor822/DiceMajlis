"""Statistics from real online games (step 2.3)."""

from datetime import datetime, timedelta, timezone as dt_timezone
from unittest import mock

from django.test import TestCase
from rest_framework.test import APIClient

from accounts import tokens as account_tokens
from accounts.models import User
from events.models import DomainEvent
from events.outbox import dispatch_pending
from game.models import Player
from game.test_rooms import RoomTestCase
from stats import services
from stats.models import PlayerGameResult, PlayerStats

T0 = datetime(2026, 11, 21, 12, 0, tzinfo=dt_timezone.utc)


class RecordTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_guest()
        self.game = 0
        patcher = mock.patch("realtime.publish.publish")
        patcher.start()
        self.addCleanup(patcher.stop)

    def play(self, place, players=4, forfeited=False):
        self.game += 1
        return services.record_result(
            self.user, game_id=self.game, room_code="ABC123", game_type="ludo", variant="classic",
            place=place, player_count=players, forfeited=forfeited,
            finished_at=T0 + timedelta(minutes=self.game),
        )

    def test_wins_losses_and_streaks(self):
        for place in (1, 1, 3, 1, 1, 1, 2):
            self.play(place)
        row = services.stats_row(PlayerStats.objects.get(user=self.user))
        self.assertEqual(
            row,
            {"games_played": 7, "wins": 5, "losses": 2, "forfeits": 0, "win_rate": 71,
             "win_streak": 0, "best_win_streak": 3},
        )
        self.play(1)
        self.assertEqual(PlayerStats.objects.get().win_streak, 1)

    def test_leaving_is_a_loss_even_in_first_place(self):
        self.play(1)
        self.play(1, forfeited=True)  # engines place leavers last; never a win
        stats = PlayerStats.objects.get()
        self.assertEqual((stats.games_played, stats.wins, stats.forfeits, stats.win_streak), (2, 1, 1, 0))

    def test_a_game_counts_once(self):
        self.assertTrue(self.play(1))
        self.assertFalse(
            services.record_result(
                self.user, game_id=1, room_code="ABC123", game_type="ludo", variant="classic",
                place=1, player_count=4, forfeited=False, finished_at=T0,
            )
        )
        self.assertEqual(PlayerStats.objects.get().games_played, 1)

    def test_every_change_is_an_event_for_achievements(self):
        self.play(1)
        event = DomainEvent.objects.get(kind="player_stats_changed")
        self.assertEqual(event.payload["user_id"], str(self.user.pk))
        self.assertEqual(event.payload["stats"]["wins"], 1)
        self.assertEqual(event.payload["total"]["games_played"], 1)

    def test_totals_across_game_types(self):
        self.play(1)
        services.record_result(
            self.user, game_id=99, room_code="XYZ789", game_type="domino", variant="classic",
            place=2, player_count=2, forfeited=False, finished_at=T0,
        )
        payload = services.stats_payload(self.user)
        self.assertEqual(payload["total"]["games_played"], 2)
        self.assertEqual(payload["total"]["win_rate"], 50)
        self.assertEqual(sorted(payload["game_types"]), ["domino", "ludo"])
        self.assertEqual([r["game_type"] for r in payload["recent"]], ["ludo", "domino"])

    def test_a_new_player_has_zeros(self):
        payload = services.stats_payload(self.user)
        self.assertEqual(payload["total"]["games_played"], 0)
        self.assertEqual((payload["game_types"], payload["recent"]), ({}, []))


class GameStatsTests(RoomTestCase):
    def setUp(self):
        super().setUp()
        patcher = mock.patch("realtime.publish.publish")
        patcher.start()
        self.addCleanup(patcher.stop)

    def stats_of(self, seat):
        return PlayerStats.objects.filter(user=Player.objects.get(id=seat).user).first()

    def test_a_real_game_updates_everyone(self):
        code, host = self.create_room()
        guest = self.join(code)
        self.start(code, host)
        self.finish_game(code, host)
        dispatch_pending(min_age_seconds=0)
        host_stats, guest_stats = self.stats_of(host), self.stats_of(guest)
        self.assertEqual((host_stats.games_played, host_stats.wins), (1, 1))
        self.assertEqual((guest_stats.games_played, guest_stats.wins), (1, 0))
        result = PlayerGameResult.objects.get(user=Player.objects.get(id=guest).user)
        self.assertEqual((result.place, result.player_count, result.won), (2, 2, False))

    def test_games_with_the_ai_do_not_count(self):
        code, host = self.create_room()
        self.start(code, host)
        self.finish_game(code, host)
        dispatch_pending(min_age_seconds=0)
        self.assertIsNone(self.stats_of(host))
        self.assertFalse(PlayerGameResult.objects.exists())


class StatsApiTests(TestCase):
    def test_my_stats(self):
        user = User.objects.create_guest()
        api = APIClient()
        api.credentials(
            HTTP_AUTHORIZATION=f"Bearer {account_tokens.start_session(user, device_id='d', platform='other').access}"
        )
        with mock.patch("realtime.publish.publish"):
            services.record_result(
                user, game_id=5, room_code="ABC123", game_type="ludo", variant="classic",
                place=1, player_count=3, forfeited=False, finished_at=T0,
            )
        r = api.get("/api/me/stats/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data["game_types"]["ludo"]["wins"], 1)
        self.assertEqual(
            r.data["recent"][0],
            {"game_type": "ludo", "variant": "classic", "place": 1, "player_count": 3, "won": True,
             "forfeited": False, "finished_at": T0.isoformat()},
        )
        self.assertEqual(APIClient().get("/api/me/stats/").status_code, 401)
