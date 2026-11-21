// Google and Apple sign-in (step 1.15): the buttons show only when the server
// AND this build are set up; signing in sends the provider's ID token to the
// server; a guest can link Google/Apple in Settings and keeps everything.

import 'package:dice_majlis_app/core/auth/social_sign_in.dart';
import 'package:dice_majlis_app/features/auth/presentation/welcome_screen.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

Future<void> launch(
  WidgetTester tester, {
  required FakeAuthApi auth,
  FakeSocialSignIn? social,
  FakeAccountRepository? accounts,
  MemoryTokenStore? tokens,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      auth: auth,
      tokens: tokens,
      social: social,
      accounts: accounts,
    ),
  );
  await tester.pump(const Duration(seconds: 2)); // splash
  await tester.pumpAndSettle();
}

void main() {
  test('Apple nonce: random, and only its SHA-256 goes to Apple', () {
    final a = randomNonce();
    expect(a, isNot(randomNonce()));
    expect(a.length, greaterThanOrEqualTo(40));
    expect(
      sha256Hex('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  testWidgets('not set up on the server: Google and Apple say coming soon', (
    tester,
  ) async {
    final auth = FakeAuthApi(); // the server has no client IDs yet
    await launch(tester, auth: auth, tokens: MemoryTokenStore());
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(find.text('Continue with Google is coming soon.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('set up on the server but not in this build: still hidden', (
    tester,
  ) async {
    final auth = FakeAuthApi()
      ..serverProviders = {'google': true, 'apple': true};
    await launch(
      tester,
      auth: auth,
      social: FakeSocialSignIn(usable: {}),
      tokens: MemoryTokenStore(),
    );
    await tester.tap(find.text('Continue with Apple'));
    await tester.pump();
    expect(find.text('Continue with Apple is coming soon.'), findsOneWidget);
  });

  testWidgets('continue with Google: the ID token goes to the server', (
    tester,
  ) async {
    final auth = FakeAuthApi()
      ..serverProviders = {'google': true, 'apple': false};
    final social = FakeSocialSignIn();
    await launch(
      tester,
      auth: auth,
      social: social,
      tokens: MemoryTokenStore(),
    );

    await tester.tap(find.text('Continue with Apple'));
    await tester.pump();
    expect(find.text('Continue with Apple is coming soon.'), findsOneWidget);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(social.asked, [SocialProvider.google]);
    expect(auth.calls, ['social:google:google-token']);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Apple sends its nonce; closing the sheet changes nothing', (
    tester,
  ) async {
    final auth = FakeAuthApi()
      ..serverProviders = {'google': false, 'apple': true};
    final social = FakeSocialSignIn()..cancel = true;
    await launch(
      tester,
      auth: auth,
      social: social,
      tokens: MemoryTokenStore(),
    );

    await tester.tap(find.text('Continue with Apple'));
    await tester.pumpAndSettle();
    expect(auth.calls, isEmpty);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    social.cancel = false;
    await tester.tap(find.text('Continue with Apple'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['social:apple:apple-token:apple-nonce']);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the server refuses: it says why', (tester) async {
    final auth = FakeAuthApi()
      ..serverProviders = {'google': true, 'apple': true}
      ..failWith = 'email_taken';
    await launch(tester, auth: auth, tokens: MemoryTokenStore());
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(
      find.text('That email already has an account. Sign in instead.'),
      findsOneWidget,
    );
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('a guest saves the account with Google in Settings', (
    tester,
  ) async {
    final guest = testAccount.copyWith(isGuest: true);
    final auth = FakeAuthApi(account: guest)
      ..serverProviders = {'google': true, 'apple': true};
    final accounts = FakeAccountRepository(account: guest);
    await launch(tester, auth: auth, accounts: accounts);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.ensureVisible(find.text('Save with Google'));
    await tester.tap(find.text('Save with Google'));
    await tester.pumpAndSettle();
    expect(accounts.calls, ['link:google:google-token']);
    expect(
      find.text('Google is linked. Sign in with it on any phone.'),
      findsOneWidget,
    );
    expect(find.text('Linked with Google'), findsOneWidget);
    // Not a guest any more: the other one is now "Link", not "Save with".
    expect(find.text('Link Apple'), findsOneWidget);
    expect(find.text('Save your account'), findsNothing);

    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();
    expect(accounts.calls.last, 'unlink:google');
    expect(find.text('Google is no longer linked.'), findsOneWidget);
  });

  testWidgets('linking a Google account another player uses is refused', (
    tester,
  ) async {
    final saved = testAccount.copyWith(isGuest: false);
    final auth = FakeAuthApi(account: saved)
      ..serverProviders = {'google': true, 'apple': false};
    final accounts = FakeAccountRepository(account: saved)
      ..failWith = 'social_account_taken';
    await launch(tester, auth: auth, accounts: accounts);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Link Google'));
    await tester.tap(find.text('Link Google'));
    await tester.pumpAndSettle();
    expect(
      find.text('That account is already linked to another player.'),
      findsOneWidget,
    );
  });
}
