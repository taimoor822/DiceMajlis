// Statistics (step 2.3): from real online games, shown on the Profile.

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/features/stats/domain/player_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

final someStats = StatsOverview.fromJson({
  'total': {
    'games_played': 7,
    'wins': 5,
    'losses': 2,
    'forfeits': 1,
    'win_rate': 71,
    'win_streak': 2,
    'best_win_streak': 3,
  },
  'game_types': {
    'ludo': {'games_played': 7, 'wins': 5},
  },
  'recent': [
    {
      'game_type': 'ludo',
      'variant': 'classic',
      'place': 1,
      'player_count': 4,
      'won': true,
      'forfeited': false,
      'finished_at': '2026-11-21T12:00:00+00:00',
    },
    {
      'game_type': 'ludo',
      'variant': 'classic',
      'place': 4,
      'player_count': 4,
      'won': false,
      'forfeited': true,
      'finished_at': '2026-11-21T11:00:00+00:00',
    },
  ],
});

Future<ProviderContainer> openProfile(
  WidgetTester tester,
  FakeStatsRepository stats, {
  FakeRealtimeServer? realtime,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      stats: stats,
      realtime: realtime,
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DiceMajlisApp)),
  );
  container.read(appRouterProvider).go(AppRoutes.profile);
  await tester.pumpAndSettle();
  return container;
}

String numberIn(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .first
    .data!;

void main() {
  testWidgets('the profile shows games, wins, win rate, streaks, results', (
    tester,
  ) async {
    await openProfile(tester, FakeStatsRepository(stats: someStats));
    expect(find.text('Statistics'), findsOneWidget);
    expect(numberIn(tester, 'stats-games'), '7');
    expect(numberIn(tester, 'stats-wins'), '5');
    expect(numberIn(tester, 'stats-win-rate'), '71%');
    expect(numberIn(tester, 'stats-best-streak'), '3');
    expect(find.text('Wins in a row now: 2'), findsOneWidget);
    expect(find.text('1 of 4'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
  });

  testWidgets('a new player is told how statistics start', (tester) async {
    await openProfile(tester, FakeStatsRepository());
    expect(find.byKey(const Key('stats-empty')), findsOneWidget);
    expect(find.textContaining('Only online games'), findsOneWidget);
  });

  testWidgets('a finished game updates the numbers live', (tester) async {
    final server = FakeRealtimeServer();
    final stats = FakeStatsRepository();
    final container = await openProfile(tester, stats, realtime: server);
    expect(find.byKey(const Key('stats-empty')), findsOneWidget);
    stats.stats = someStats;
    server.push(
      'user/${container.read(accountProvider)!.playerId}',
      'stats_changed',
      {'game_type': 'ludo'},
    );
    await tester.pumpAndSettle();
    expect(numberIn(tester, 'stats-games'), '7');
    expect(stats.loads, 2);
  });

  testWidgets('a failed load can be tried again', (tester) async {
    final stats = FakeStatsRepository()..failWith = 'network_error';
    await openProfile(tester, stats);
    expect(find.text('Try again'), findsWidgets);
    stats.failWith = null;
    await tester.tap(find.text('Try again').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stats-empty')), findsOneWidget);
  });
}
