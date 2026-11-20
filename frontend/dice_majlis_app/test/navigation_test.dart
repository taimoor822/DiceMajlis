// Main navigation: Events · Game Hub · Battle · Chat · Social, where Battle
// (centre) is the Home lobby the app opens on.

import 'package:dice_majlis_app/core/storage/preferences.dart';
import 'package:dice_majlis_app/core/theme/theme_mode_controller.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/hub/presentation/game_hub_screen.dart';
import 'package:dice_majlis_app/features/multiplayer/presentation/create_room_screen.dart';
import 'package:dice_majlis_app/features/navigation/presentation/tab_placeholders.dart';
import 'package:dice_majlis_app/features/settings/presentation/settings_screen.dart';
import 'package:dice_majlis_app/shared/widgets/coming_soon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

const tabs = ['Events', 'Game Hub', 'Battle', 'Chat', 'Social'];

Future<void> openApp(
  WidgetTester tester, {
  List<Override> extra = const [],
}) async {
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      overrides: extra,
    ),
  );
  await tester.pump(const Duration(seconds: 2)); // splash
  await tester.pumpAndSettle();
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// The Android back button / back gesture.
Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bar shows the five tabs; the app opens on Battle', (
    tester,
  ) async {
    await openApp(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, tabs.indexOf('Battle'));
    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(labels, tabs);
  });

  testWidgets('each tab opens its page; unbuilt ones say coming soon', (
    tester,
  ) async {
    await openApp(tester);
    final pages = <String, Type>{
      'Events': EventsScreen,
      'Game Hub': GameHubScreen,
      'Chat': ChatScreen,
      'Social': SocialScreen,
      'Battle': HomeScreen,
    };
    for (final MapEntry(key: tab, value: page) in pages.entries) {
      await tapTab(tester, tab);
      expect(find.byType(page), findsOneWidget, reason: tab);
      final soon = ['Events', 'Chat', 'Social'].contains(tab);
      expect(
        find.byType(ComingSoonPage),
        soon ? findsOneWidget : findsNothing,
        reason: tab,
      );
    }
  });

  testWidgets('a tab remembers where you were', (tester) async {
    await openApp(tester);
    await tapTab(tester, 'Game Hub');
    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateRoomScreen), findsOneWidget);

    await tapTab(tester, 'Chat');
    await tapTab(tester, 'Game Hub');
    expect(find.byType(CreateRoomScreen), findsOneWidget);

    // Tapping the tab you're on goes back to its first page.
    await tapTab(tester, 'Game Hub');
    expect(find.byType(CreateRoomScreen), findsNothing);
    expect(find.byType(GameHubScreen), findsOneWidget);
  });

  testWidgets('back closes the inner page first, then goes to the lobby', (
    tester,
  ) async {
    await openApp(tester);
    await tapTab(tester, 'Game Hub');
    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();

    await pressBack(tester);
    expect(find.byType(GameHubScreen), findsOneWidget);

    await pressBack(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Home shortcuts: Settings opens, the rest say coming soon', (
    tester,
  ) async {
    await openApp(tester);
    await tester.ensureVisible(find.text('Shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop'));
    await tester.pump();
    expect(find.text('Shop is coming soon.'), findsOneWidget);

    await tester.tap(find.text('Settings')); // the shortcut tile
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the theme choice applies at once and is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await openApp(
      tester,
      extra: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
      Brightness.light,
    );
    expect(preferences.getString(ThemeModeController.storageKey), 'light');
  });

  testWidgets('a saved theme is used when the app starts', (tester) async {
    SharedPreferences.setMockInitialValues({
      ThemeModeController.storageKey: 'light',
    });
    final preferences = await SharedPreferences.getInstance();
    await openApp(
      tester,
      extra: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).brightness,
      Brightness.light,
    );
  });
}
