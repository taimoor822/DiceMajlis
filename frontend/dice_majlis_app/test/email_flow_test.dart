// Email accounts in the app: sign in, create an account, forgotten password,
// and a guest saving their account.

import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/features/auth/presentation/email_screen.dart';
import 'package:dice_majlis_app/features/auth/presentation/welcome_screen.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/multiplayer/presentation/waiting_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// Starts signed out and opens the email screen from Welcome.
Future<void> openEmail(
  WidgetTester tester, {
  required FakeAuthApi auth,
  FakeSockets? sockets,
}) async {
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: sockets ?? FakeSockets(),
      auth: auth,
      tokens: MemoryTokenStore(),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  expect(find.byType(WelcomeScreen), findsOneWidget);
  await tester.tap(find.text('Sign in with email'));
  await tester.pumpAndSettle();
  expect(find.byType(EmailScreen), findsOneWidget);
}

Future<void> fill(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    password,
  );
}

void main() {
  testWidgets('sign in with email opens Home', (tester) async {
    final auth = FakeAuthApi(
      account: testAccount.copyWith(isGuest: false, email: 'sara@example.com'),
    );
    await openEmail(tester, auth: auth);

    await fill(tester, ' sara@example.com ', 'Majlis-night-2026');
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['login:sara@example.com:Majlis-night-2026']);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Guest'), findsNothing);
  });

  testWidgets('signing in goes back to the room the account is in', (
    tester,
  ) async {
    final sockets = FakeSockets();
    final auth = FakeAuthApi(
      account: testAccount.copyWith(
        isGuest: false,
        activeRoom: const ActiveRoom(code: 'AB12', seatId: 'p-host'),
      ),
    );
    await openEmail(tester, auth: auth, sockets: sockets);
    await fill(tester, 'sara@example.com', 'Majlis-night-2026');
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();
    expect(find.byType(WaitingRoomScreen), findsOneWidget);
    expect(sockets.last.connectedRoom, 'AB12');
  });

  testWidgets('wrong password and a bad email say why', (tester) async {
    final auth = FakeAuthApi(failWith: 'invalid_credentials');
    await openEmail(tester, auth: auth);

    await fill(tester, 'not-an-email', 'x');
    await tester.tap(find.text('SIGN IN'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(auth.calls, isEmpty);

    await fill(tester, 'sara@example.com', 'wrong');
    await tester.tap(find.text('SIGN IN'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.byType(EmailScreen), findsOneWidget);
  });

  testWidgets('create an account', (tester) async {
    final auth = FakeAuthApi();
    await openEmail(tester, auth: auth);
    await tester.tap(find.text('Create account').first);
    await tester.pump();

    await fill(tester, 'new@example.com', 'Desert-rose-2027');
    await tester.tap(find.text('CREATE ACCOUNT'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['register:new@example.com']);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('forgotten password: code by email, then a new password', (
    tester,
  ) async {
    final auth = FakeAuthApi();
    await openEmail(tester, auth: auth);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'sara@example.com',
    );
    await tester.tap(find.text('SEND CODE'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['reset:sara@example.com']);
    expect(find.textContaining('a code is on its way'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '6-digit code'),
      '12a34',
    );
    await tester.tap(find.text('CHANGE PASSWORD'));
    await tester.pump();
    expect(find.text('Enter the 6 digits from the email.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '6-digit code'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'Desert-rose-2027',
    );
    await tester.tap(find.text('CHANGE PASSWORD'));
    await tester.pumpAndSettle();
    expect(auth.calls.sublist(1), [
      'confirm:sara@example.com:123456:Desert-rose-2027',
      'login:sara@example.com:Desert-rose-2027',
    ]);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a wrong code says so', (tester) async {
    final auth = FakeAuthApi();
    await openEmail(tester, auth: auth);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'sara@example.com',
    );
    await tester.tap(find.text('SEND CODE'));
    await tester.pumpAndSettle();

    auth.failWith = 'invalid_code';
    await tester.enterText(
      find.widgetWithText(TextFormField, '6-digit code'),
      '000000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'Desert-rose-2027',
    );
    await tester.tap(find.text('CHANGE PASSWORD'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text("That code isn't right. Check the email and try again."),
      findsOneWidget,
    );
  });

  testWidgets('a guest saves their account from Settings', (tester) async {
    final accounts = FakeAccountRepository();
    await tester.pumpWidget(
      testApp(
        repository: FakeRoomRepository(),
        sockets: FakeSockets(),
        accounts: accounts,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE YOUR ACCOUNT'));
    await tester.pumpAndSettle();
    await fill(tester, 'guest@example.com', 'Desert-rose-2027');
    await tester.tap(find.text('SAVE ACCOUNT'));
    await tester.pumpAndSettle();

    expect(accounts.calls, ['save:guest@example.com']);
    expect(find.text('guest@example.com'), findsOneWidget);
    expect(find.text('SAVE YOUR ACCOUNT'), findsNothing);
  });

  testWidgets('saving with a weak password says why', (tester) async {
    final accounts = FakeAccountRepository()
      ..failWith = 'invalid_input'
      ..fieldErrors = {
        'password': ['password_too_common'],
      };
    await tester.pumpWidget(
      testApp(
        repository: FakeRoomRepository(),
        sockets: FakeSockets(),
        accounts: accounts,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE YOUR ACCOUNT'));
    await tester.pumpAndSettle();
    await fill(tester, 'guest@example.com', 'password');
    await tester.tap(find.text('SAVE ACCOUNT'));
    await tester.pump();
    await tester.pump();
    expect(find.text('That password is too easy to guess.'), findsOneWidget);
  });
}
