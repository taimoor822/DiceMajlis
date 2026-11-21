// Entitlements (step 2.6): what the account may do, from the server; privileges
// listed on the Profile; items that need one are locked in Customise.

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/core/entitlements/entitlements.dart';
import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/features/cosmetics/domain/inventory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

final someEntitlements = Entitlements.fromJson({
  'entitlements': {'game_exp_bonus': 10, 'voice_messaging': true},
  'privileges': [
    {
      'code': 'game_exp_bonus',
      'name': 'Game XP bonus',
      'description': 'Extra account XP from online games, in percent.',
      'icon': 'bolt',
      'value_type': 'number',
      'value': 10,
      'built': true,
    },
    {
      'code': 'voice_messaging',
      'name': 'Voice messages',
      'description': 'Send voice messages in private chat.',
      'icon': 'mic',
      'value_type': 'flag',
      'value': true,
      'built': false,
    },
  ],
});

Future<ProviderContainer> open(
  WidgetTester tester, {
  FakeEntitlementsRepository? entitlements,
  FakeItemsRepository? items,
  FakeRealtimeServer? realtime,
  required String route,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      entitlements: entitlements,
      items: items,
      realtime: realtime,
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DiceMajlisApp)),
  );
  container.read(appRouterProvider).go(route);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('has and value read what the server decided', () {
    expect(someEntitlements.has('voice_messaging'), isTrue);
    expect(someEntitlements.value('game_exp_bonus'), 10);
    expect(someEntitlements.has('royal_items'), isFalse);
    expect(someEntitlements.value('royal_items'), 0);
  });

  testWidgets('the profile lists privileges; unbuilt ones say Soon', (
    tester,
  ) async {
    await open(
      tester,
      entitlements: FakeEntitlementsRepository(entitlements: someEntitlements),
      route: AppRoutes.profile,
    );
    expect(find.byKey(const Key('privileges-card')), findsOneWidget);
    expect(find.text('Game XP bonus: 10'), findsOneWidget);
    expect(find.text('Voice messages'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('privileges-card')),
        matching: find.text('Soon'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no privileges: no card', (tester) async {
    await open(tester, route: AppRoutes.profile);
    expect(find.byKey(const Key('privileges-card')), findsNothing);
  });

  testWidgets('a change from the server arrives live', (tester) async {
    final server = FakeRealtimeServer();
    final container = await open(
      tester,
      realtime: server,
      route: AppRoutes.profile,
    );
    expect(find.byKey(const Key('privileges-card')), findsNothing);
    server.push(
      'user/${container.read(accountProvider)!.playerId}',
      'entitlements_updated',
      {
        'entitlements': {'royal_items': true},
        'privileges': [
          {
            'code': 'royal_items',
            'name': 'Royal items',
            'description': 'May wear Royal-only items.',
            'icon': 'diamond',
            'value_type': 'flag',
            'value': true,
            'built': true,
          },
        ],
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Royal items'), findsOneWidget);
    expect(
      container.read(entitlementsProvider).value!.has('royal_items'),
      true,
    );
  });

  testWidgets('an item that needs a privilege is shown locked', (tester) async {
    final items = FakeItemsRepository()
      ..items = [
        ...FakeItemsRepository.starterItems,
        OwnedItem.fromJson({
          'code': 'frame_falcon',
          'type': 'cosmetic',
          'slot': 'frame',
          'name': 'Falcon Crest',
          'rarity': 'legendary',
          'asset': 'frame_falcon',
          'locked': true,
          'requires_privilege': 'royal_items',
          'requires_privilege_name': 'Royal items',
        }),
      ];
    await open(tester, items: items, route: AppRoutes.customise);
    expect(find.text('Needs: Royal items'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choice-frame_falcon')));
    await tester.pumpAndSettle();
    expect(items.calls.where((c) => c.startsWith('equip')), isEmpty);
  });
}
