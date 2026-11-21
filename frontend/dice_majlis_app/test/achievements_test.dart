// Achievements (step 2.4): progress and tiers on their screen, a note when one
// unlocks, and the game's unlocks in its result.

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/features/achievements/domain/achievements.dart';
import 'package:dice_majlis_app/features/achievements/presentation/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

final overview = AchievementsOverview.fromJson({
  'achievements': [
    {
      'code': 'wins',
      'name': 'Victories',
      'description': 'Win online games against other people.',
      'icon': 'trophy',
      'rarity': 'common',
      'metric': 'wins',
      'value': 2,
      'tiers': [
        {
          'threshold': 1,
          'reward': {'gold': 100},
          'unlocked_at': '2026-11-21T12:00:00+00:00',
        },
        {
          'threshold': 10,
          'reward': {'gold': 300},
          'unlocked_at': null,
        },
      ],
      'unlocked_tiers': 1,
      'next_threshold': 10,
      'completed': false,
    },
    {
      'code': 'level',
      'name': 'Rising Star',
      'description': 'Reach a higher account level.',
      'icon': 'star',
      'rarity': 'common',
      'metric': 'level',
      'value': 30,
      'tiers': [
        {
          'threshold': 20,
          'reward': {'diamond': 5},
          'unlocked_at': '2026-11-21T12:00:00+00:00',
        },
      ],
      'unlocked_tiers': 1,
      'next_threshold': null,
      'completed': true,
    },
  ],
  'unlocked_tiers': 2,
  'total_tiers': 3,
  'hidden_left': 1,
});

Future<ProviderContainer> open(
  WidgetTester tester, {
  FakeAchievementsRepository? achievements,
  FakeRealtimeServer? realtime,
  String? route,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      achievements: achievements,
      realtime: realtime,
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DiceMajlisApp)),
  );
  if (route != null) {
    container.read(appRouterProvider).go(route);
    await tester.pumpAndSettle();
  }
  return container;
}

void main() {
  test('an unlock message is read, or ignored when broken', () {
    final unlocked = AchievementUnlocked.fromJson({
      'code': 'wins',
      'name': 'Victories',
      'tier': 1,
      'reward': {'gold': 100},
      'room_code': 'QX7P2M',
    })!;
    expect(unlocked.name, 'Victories');
    expect(unlocked.reward.gold, 100);
    expect(unlocked.roomCode, 'QX7P2M');
    expect(AchievementUnlocked.fromJson({'name': 'x'}), isNull);
    expect(overview.achievements.first.progress, 0.2);
  });

  testWidgets('progress, tiers, rewards and hidden ones', (tester) async {
    await open(
      tester,
      achievements: FakeAchievementsRepository(overview: overview),
      route: AppRoutes.profile,
    );
    await tester.tap(find.byKey(const Key('profile-achievements')));
    await tester.pumpAndSettle();
    expect(find.byType(AchievementsScreen), findsOneWidget);
    expect(find.text('2 of 3 unlocked'), findsOneWidget);
    expect(find.text('Victories'), findsOneWidget);
    expect(find.text('2 / 10'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('+300'), findsOneWidget); // the next tier's reward
    expect(find.text('1 hidden achievement still to find'), findsOneWidget);
  });

  testWidgets('an unlock shows a note and reloads the list', (tester) async {
    final server = FakeRealtimeServer();
    final achievements = FakeAchievementsRepository();
    final container = await open(
      tester,
      achievements: achievements,
      realtime: server,
      route: AppRoutes.achievements,
    );
    expect(find.text('0 of 0 unlocked'), findsOneWidget);
    achievements.overview = overview;
    server.push(
      'user/${container.read(accountProvider)!.playerId}',
      'achievement_unlocked',
      {
        'code': 'wins',
        'name': 'Victories',
        'icon': 'trophy',
        'rarity': 'common',
        'tier': 1,
        'threshold': 1,
        'reward': {'gold': 100},
        'room_code': null,
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Achievement unlocked: Victories · +100 Gold'),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('2 of 3 unlocked'), findsOneWidget);
  });
}
