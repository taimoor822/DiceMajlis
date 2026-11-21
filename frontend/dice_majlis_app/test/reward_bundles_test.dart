// Reward bundles (step 2.5): rewards with XP and items, the daily cycle from the
// server, and the reward history.

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/features/rewards/domain/daily_reward.dart';
import 'package:dice_majlis_app/features/rewards/domain/reward_bundle.dart';
import 'package:dice_majlis_app/features/rewards/presentation/reward_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

const pearl = {
  'code': 'dice_pearl',
  'name': 'Pearl',
  'asset': 'dice_pearl',
  'slot': 'dice',
  'rarity': 'epic',
  'quantity': 1,
  'days': 7,
};

Future<ProviderContainer> open(
  WidgetTester tester,
  FakeRewardsRepository rewards, {
  String? route,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      rewards: rewards,
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
  test('a bundle with XP and an item, and the daily status', () {
    final bundle = RewardBundle.fromJson({
      'gold': 500,
      'diamond': 5,
      'xp': 20,
      'items': [pearl],
    });
    expect((bundle.gold, bundle.diamond, bundle.xp), (500, 5, 20));
    expect((bundle.items.single.name, bundle.items.single.days), ('Pearl', 7));
    expect(RewardBundle.fromJson(null).isEmpty, isTrue);

    final status = DailyRewardStatus.fromJson({
      'day': 7,
      'claimed_today': true,
      'next_day': 7,
      'available': true,
      'on_miss': 'continue',
      'days': [
        {
          'day': 7,
          'gold': 500,
          'diamond': 5,
          'xp': 20,
          'items': [pearl],
        },
      ],
      'seconds_until_reset': 60,
    });
    expect(status.nextDay, 7); // the server's choice, not worked out here
    expect(status.restartsOnMiss, isFalse);
    expect(status.today!.items.single.code, 'dice_pearl');
  });

  testWidgets('the reward history names each reward and what it gave', (
    tester,
  ) async {
    final rewards = FakeRewardsRepository()
      ..given = [
        RewardHistoryEntry.fromJson({
          'id': 'a',
          'kind': 'achievement',
          'achievement': 'Victories',
          'threshold': 10,
          'reward': {
            'gold': 300,
            'items': [
              {...pearl, 'name': 'Night Sky', 'days': null},
            ],
          },
          'created_at': '2026-11-21T12:00:00+00:00',
        }),
        RewardHistoryEntry.fromJson({
          'id': 'b',
          'kind': 'daily_login',
          'day': 7,
          'reward': {
            'gold': 500,
            'diamond': 5,
            'xp': 20,
            'items': [pearl],
          },
          'created_at': '2026-11-20T12:00:00+00:00',
        }),
      ];
    await open(tester, rewards, route: AppRoutes.wallet);
    await tester.tap(find.byKey(const Key('wallet-reward-history')));
    await tester.pumpAndSettle();
    expect(find.byType(RewardHistoryScreen), findsOneWidget);
    expect(find.text('Achievement: Victories (10)'), findsOneWidget);
    expect(find.text('Night Sky'), findsOneWidget);
    expect(find.text('Daily reward, day 7'), findsOneWidget);
    expect(find.text('+20 XP'), findsOneWidget);
    expect(find.text('Pearl (7 days)'), findsOneWidget);
  });

  testWidgets('no rewards yet says how to get some', (tester) async {
    await open(tester, FakeRewardsRepository(), route: AppRoutes.rewardHistory);
    expect(find.byKey(const Key('reward-history-empty')), findsOneWidget);
  });
}
