// Your profile: open it from Home, change avatar, name and languages; the
// level comes from the server.

import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/core/theme/app_theme.dart';
import 'package:dice_majlis_app/features/profile/domain/profile_options.dart';
import 'package:dice_majlis_app/features/profile/presentation/profile_screen.dart';
import 'package:dice_majlis_app/shared/widgets/player_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

Future<FakeAccountRepository> openProfile(
  WidgetTester tester, {
  Account account = testAccount,
}) async {
  final accounts = FakeAccountRepository(account: account);
  // Tall enough that the whole profile page is on screen.
  await tester.binding.setSurfaceSize(const Size(480, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      auth: FakeAuthApi(account: account),
      accounts: accounts,
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tap to edit your profile'));
  await tester.pumpAndSettle();
  expect(find.byType(ProfileScreen), findsOneWidget);
  return accounts;
}

void main() {
  testWidgets('Home shows avatar and level; the profile shows XP', (
    tester,
  ) async {
    const account = Account(
      playerId: 123456789,
      displayName: 'Sara',
      avatar: 'moon',
      level: 3,
      xp: 350,
      levelXp: 300,
      nextLevelXp: 600,
    );
    await tester.pumpWidget(
      testApp(
        repository: FakeRoomRepository(),
        sockets: FakeSockets(),
        auth: FakeAuthApi(account: account),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Level 3'), findsOneWidget);
    final avatar = tester.widget<PlayerAvatar>(find.byType(PlayerAvatar));
    expect(avatar.avatar, 'moon');

    await tester.tap(find.text('Sara'));
    await tester.pumpAndSettle();
    expect(find.text('350 / 600 XP'), findsOneWidget);
    expect(find.text('Earning XP from games is coming soon.'), findsOneWidget);
    expect(account.levelProgress, closeTo(50 / 300, 1e-9));
  });

  testWidgets('pick an avatar: saved at once', (tester) async {
    final accounts = await openProfile(tester);
    // dhow is current; the server offers dice, dhow and moon.
    final moon = find.byWidgetPredicate(
      (widget) => widget is PlayerAvatar && widget.avatar == 'moon',
    );
    await tester.tap(moon);
    await tester.pumpAndSettle();
    expect(accounts.calls, ['options', 'update:avatar=moon']);
    final selected = tester
        .widgetList<PlayerAvatar>(find.byType(PlayerAvatar))
        .where((a) => a.selected)
        .map((a) => a.avatar);
    expect(selected, ['moon']);
  });

  testWidgets('change the name; a refused name says why', (tester) async {
    final accounts = await openProfile(tester);
    final field = find.byType(TextField).first;

    accounts
      ..failWith = 'invalid_input'
      ..fieldErrors = {
        'display_name': ['name_length'],
      };
    await tester.enterText(field, 'S');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(find.text('Names are 2 to 20 characters.'), findsOneWidget);

    accounts
      ..failWith = null
      ..fieldErrors = const {};
    await tester.enterText(field, 'Sara Al Majlis');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(accounts.calls.last, 'update:name=Sara Al Majlis');
    expect(find.text('Sara Al Majlis'), findsWidgets);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('languages: pick up to the limit', (tester) async {
    final accounts = await openProfile(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Arabic'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'English'));
    await tester.pumpAndSettle();
    expect(accounts.calls.sublist(1), [
      'update:languages=ar',
      'update:languages=ar,en',
    ]);
    // The limit (2 here) is reached: the others can't be picked.
    final urdu = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Urdu'),
    );
    expect(urdu.onSelected, isNull);

    await tester.tap(find.widgetWithText(FilterChip, 'Arabic'));
    await tester.pumpAndSettle();
    expect(accounts.calls.last, 'update:languages=en');
  });

  testWidgets('a country can be shown and hidden', (tester) async {
    final accounts = await openProfile(
      tester,
      account: testAccount.copyWith(country: 'BH'),
    );
    expect(find.textContaining('Bahrain'), findsOneWidget);

    await tester.tap(find.text("Don't show my country"));
    await tester.pumpAndSettle();
    expect(accounts.calls.last, 'update:country=');
    expect(find.text('Not shown'), findsOneWidget);
  });

  test('profile options from the server JSON', () {
    final options = ProfileOptions.fromJson({
      'avatars': ['dice', 'moon'],
      'languages': ['en', 'ar'],
      'max_languages': 2,
      'name_min_length': 2,
      'name_max_length': 20,
    });
    expect(options.avatars, ['dice', 'moon']);
    expect(options.maxLanguages, 2);
    expect((options.nameMinLength, options.nameMaxLength), (2, 20));
  });

  testWidgets('an avatar key the app does not know shows a plain picture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Column(
            children: [
              PlayerAvatar(avatar: 'dragon'),
              PlayerAvatar(avatar: 'dhow'),
            ],
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.sailing), findsOneWidget);
  });
}
