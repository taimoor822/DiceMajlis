// Gold and diamonds: balances on Home, the daily reward, the wallet history.

import 'package:dice_majlis_app/features/rewards/domain/daily_reward.dart';
import 'package:dice_majlis_app/features/rewards/presentation/daily_reward_card.dart';
import 'package:dice_majlis_app/features/wallet/domain/wallet_models.dart';
import 'package:dice_majlis_app/features/wallet/presentation/balance_chips.dart';
import 'package:dice_majlis_app/features/wallet/presentation/wallet_screen.dart';
import 'package:dice_majlis_app/shared/widgets/majlis_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

Future<void> openHome(
  WidgetTester tester, {
  FakeWalletRepository? wallet,
  FakeRewardsRepository? rewards,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      wallet: wallet,
      rewards: rewards,
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

Finder inChips(String text) =>
    find.descendant(of: find.byType(BalanceChips), matching: find.text(text));

WalletEntry entry(int n, {int amount = 100, String type = 'reward_daily'}) =>
    WalletEntry(
      id: 'e$n',
      reference: 'TXN-$n',
      currency: Currencies.gold,
      amount: amount,
      balanceAfter: 0,
      type: type,
      createdAt: DateTime.utc(2026, 11, 20, 10),
    );

void main() {
  testWidgets('Home shows gold and diamonds from the server', (tester) async {
    await openHome(
      tester,
      wallet: FakeWalletRepository(
        balance: const Balances(gold: 1250, diamond: 5),
      ),
    );
    expect(inChips('1,250'), findsOneWidget);
    expect(inChips('5'), findsOneWidget);
  });

  testWidgets('claim the daily reward: balance and card update', (
    tester,
  ) async {
    final wallet = FakeWalletRepository(balance: const Balances(gold: 1250));
    final rewards = FakeRewardsRepository(day: 2, wallet: wallet);
    await openHome(tester, rewards: rewards);

    expect(find.text('Day 2'), findsOneWidget);
    await tester.tap(find.widgetWithText(MajlisButton, 'CLAIM'));
    await tester.pumpAndSettle();

    expect(rewards.calls, ['status', 'claim']);
    expect(find.text('You got +150 Gold'), findsOneWidget);
    expect(inChips('1,400'), findsOneWidget);
    expect(find.text('Claimed! Come back tomorrow for day 3.'), findsOneWidget);
    expect(find.text('Next reward in 5 hours'), findsOneWidget);
    expect(find.widgetWithText(MajlisButton, 'CLAIM'), findsNothing);
  });

  testWidgets('day 7 gives diamonds too and the next day is 1', (tester) async {
    final rewards = FakeRewardsRepository(day: 7);
    await openHome(tester, rewards: rewards);
    await tester.tap(find.widgetWithText(MajlisButton, 'CLAIM'));
    await tester.pumpAndSettle();
    expect(find.text('You got +500 Gold, +5 Diamonds'), findsOneWidget);
    expect(find.text('Claimed! Come back tomorrow for day 1.'), findsOneWidget);
  });

  testWidgets('already claimed today: no button', (tester) async {
    await openHome(
      tester,
      rewards: FakeRewardsRepository(day: 3, claimedToday: true),
    );
    expect(find.byType(DailyRewardCard), findsOneWidget);
    expect(find.widgetWithText(MajlisButton, 'CLAIM'), findsNothing);
    expect(find.text('Claimed! Come back tomorrow for day 4.'), findsOneWidget);
  });

  testWidgets('a refused claim says why and reloads the card', (tester) async {
    final rewards = FakeRewardsRepository()..failWith = 'already_claimed';
    await openHome(tester, rewards: rewards);
    await tester.tap(find.widgetWithText(MajlisButton, 'CLAIM'));
    await tester.pumpAndSettle();
    expect(find.text("Today's reward is already claimed."), findsOneWidget);
    expect(rewards.calls, ['status', 'claim', 'status']);
  });

  testWidgets('wallet: balances and history, a page at a time', (tester) async {
    final wallet = FakeWalletRepository(
      balance: const Balances(gold: 2_500_000, diamond: 12),
      entries: [
        entry(1, amount: -50, type: 'admin_revoke'),
        entry(2, type: 'admin_grant'),
        for (var n = 3; n <= 5; n++) entry(n),
      ],
      pageSize: 3,
    );
    await openHome(tester, wallet: wallet);
    await tester.tap(find.byType(BalanceChips));
    await tester.pumpAndSettle();

    expect(find.byType(WalletScreen), findsOneWidget);
    expect(find.text('2.5M'), findsWidgets);
    expect(find.text('Taken back by the team'), findsOneWidget);
    expect(find.text('-50'), findsOneWidget);
    expect(find.text('From the Dice Majlis team'), findsOneWidget);
    expect(find.text('Daily reward'), findsOneWidget);

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    expect(wallet.calls.where((c) => c.startsWith('history')), [
      'history:first',
      'history:e3',
    ]);
    expect(find.text('Daily reward'), findsNWidgets(3));
    expect(find.text('Show more'), findsNothing);
  });

  testWidgets('an empty wallet says how to start', (tester) async {
    final wallet = FakeWalletRepository();
    await openHome(tester, wallet: wallet);
    await tester.tap(find.byType(BalanceChips));
    await tester.pumpAndSettle();
    // Opening the wallet reloads the balances (they may have changed).
    expect(wallet.calls.where((call) => call == 'balances'), hasLength(2));
    expect(
      find.text('Nothing yet. Claim your daily reward to get started.'),
      findsOneWidget,
    );
  });

  group('from the server JSON', () {
    test('balances', () {
      expect(
        Balances.fromJson({'gold': 10, 'diamond': 2}),
        const Balances(gold: 10, diamond: 2),
      );
      expect(Balances.fromJson({}), const Balances());
    });

    test('daily status', () {
      final status = DailyRewardStatus.fromJson({
        'reward_day': '2026-11-20',
        'day': 7,
        'claimed_today': false,
        'days': [
          {'day': 7, 'gold': 500, 'diamond': 5},
        ],
        'seconds_until_reset': 3600,
      });
      expect((status.day, status.claimedToday), (7, false));
      expect(status.today?.diamond, 5);
      expect(status.secondsUntilReset, 3600);
    });

    test('a history page', () {
      final page = WalletPage.fromJson({
        'transactions': [
          {
            'id': 'a',
            'reference': 'TXN-A',
            'currency': 'diamond',
            'amount': 5,
            'balance_after': 5,
            'type': 'reward_daily',
            'created_at': '2026-11-20T09:00:00+03:00',
          },
        ],
        'next': null,
      });
      expect(page.entries.single.currency, 'diamond');
      expect(page.entries.single.createdAt, DateTime.utc(2026, 11, 20, 6));
      expect(page.next, isNull);
    });
  });
}
