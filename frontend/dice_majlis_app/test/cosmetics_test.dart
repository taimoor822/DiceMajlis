// Items and cosmetics (step 2.2): choose dice, board and frame; the server
// decides what you own, and everyone sees what you wear.

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/features/cosmetics/domain/inventory.dart';
import 'package:dice_majlis_app/features/cosmetics/presentation/customise_screen.dart';
import 'package:dice_majlis_app/features/ludo/presentation/widgets/dice_widget.dart';
import 'package:dice_majlis_app/shared/widgets/player_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

Future<ProviderContainer> openCustomise(
  WidgetTester tester,
  FakeItemsRepository items, {
  FakeRealtimeServer? realtime,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      items: items,
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
  await tester.tap(find.byKey(const Key('profile-customise')));
  await tester.pumpAndSettle();
  expect(find.byType(CustomiseScreen), findsOneWidget);
  return container;
}

void main() {
  test('inventory from the server JSON', () {
    final inventory = Inventory.fromJson({
      'items': [
        {
          'code': 'frame_lantern',
          'type': 'cosmetic',
          'slot': 'frame',
          'name': 'Lantern Glow',
          'rarity': 'rare',
          'asset': 'frame_lantern',
          'quantity': 1,
          'expires_at': '2026-12-01T00:00:00+00:00',
          'starter': false,
        },
      ],
      'equipped': {'dice': 'dice_ivory', 'frame': null},
      'cosmetics': {'dice': 'dice_ivory', 'frame': null},
    });
    final lantern = inventory.forSlot('frame').single;
    expect(lantern.expiresAt, DateTime.utc(2026, 12, 1));
    expect(inventory.equipped, {'dice': 'dice_ivory', 'frame': null});
    expect(inventory.forSlot('dice'), isEmpty);
  });

  testWidgets('choose a die: the server saves it, the account wears it', (
    tester,
  ) async {
    final items = FakeItemsRepository();
    final container = await openCustomise(tester, items);
    expect(find.text('Dice'), findsOneWidget);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Profile frame'), findsOneWidget);
    expect(find.text('Desert Gold'), findsOneWidget);
    expect(find.text('Rare'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('choice-dice_desert_gold')));
    await tester.pumpAndSettle();
    expect(items.calls, contains('equip:dice:dice_desert_gold'));
    expect(container.read(accountProvider)!.diceSkin, 'dice_desert_gold');
    // The previews draw each die the way the game does.
    expect(
      tester
          .widgetList<DiceWidget>(find.byType(DiceWidget))
          .map((dice) => dice.skin),
      ['dice_ivory', 'dice_desert_gold'],
    );
  });

  testWidgets('a frame shows around your avatar, and can come off', (
    tester,
  ) async {
    final items = FakeItemsRepository();
    final container = await openCustomise(tester, items);
    await tester.tap(find.byKey(const ValueKey('choice-frame_brass')));
    await tester.pumpAndSettle();
    expect(container.read(accountProvider)!.frame, 'frame_brass');

    await tester.tap(find.byKey(const ValueKey('choice-frame-none')));
    await tester.pumpAndSettle();
    expect(items.calls.last, 'equip:frame:null');
    expect(container.read(accountProvider)!.frame, isNull);

    await tester.tap(find.byKey(const ValueKey('choice-frame_brass')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Profile header: the avatar wears the frame.
    final avatar = tester.widget<PlayerAvatar>(find.byType(PlayerAvatar).first);
    expect(avatar.frame, 'frame_brass');
    expect(find.byKey(const Key('avatar-frame')), findsWidgets);
  });

  testWidgets('a refused choice says why and changes nothing', (tester) async {
    final items = FakeItemsRepository();
    final container = await openCustomise(tester, items);
    items.failWith = 'not_owned';
    await tester.tap(find.byKey(const ValueKey('choice-board_oasis')));
    await tester.pumpAndSettle();
    expect(find.text("You don't own that item."), findsOneWidget);
    expect(container.read(accountProvider)!.boardSkin, isNull);
  });

  testWidgets('cosmetics chosen on another phone arrive live', (tester) async {
    final server = FakeRealtimeServer();
    final items = FakeItemsRepository();
    final container = await openCustomise(tester, items, realtime: server);
    final channel = 'user/${container.read(accountProvider)!.playerId}';
    server.push(channel, 'cosmetics_changed', {
      'cosmetics': {
        'dice': 'dice_desert_gold',
        'board': 'board_oasis',
        'frame': null,
      },
    });
    await tester.pumpAndSettle();
    final account = container.read(accountProvider)!;
    expect(
      (account.diceSkin, account.boardSkin),
      ('dice_desert_gold', 'board_oasis'),
    );

    // A new item from a reward: the list reloads.
    items.items = [
      ...items.items,
      const OwnedItem(
        code: 'dice_ruby',
        type: 'cosmetic',
        slot: 'dice',
        name: 'Ruby',
        rarity: 'epic',
        asset: 'dice_ruby',
      ),
    ];
    server.push(channel, 'inventory_changed', {});
    await tester.pumpAndSettle();
    expect(find.text('Ruby'), findsOneWidget);
    expect(find.text('Epic'), findsOneWidget);
  });
}
