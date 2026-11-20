// What a player sees at app start: welcome, guest sign-in, going back to
// their room, offline retry, and signing out.

import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/core/network/api_exception.dart';
import 'package:dice_majlis_app/features/auth/presentation/welcome_screen.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/ludo/presentation/game_board_screen.dart';
import 'package:dice_majlis_app/features/multiplayer/presentation/waiting_room_screen.dart';
import 'package:dice_majlis_app/features/splash/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// Starts the app and waits out the splash screen.
Future<void> launch(
  WidgetTester tester, {
  FakeAuthApi? auth,
  MemoryTokenStore? tokens,
  FakeSockets? sockets,
}) async {
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: sockets ?? FakeSockets(),
      auth: auth,
      tokens: tokens,
    ),
  );
  await tester.pump(const Duration(seconds: 2)); // splash
  // Not pumpAndSettle: a board, if shown, keeps a loading spinner going.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('first visit: play as guest, then Home shows the Player ID', (
    tester,
  ) async {
    final auth = FakeAuthApi();
    final tokens = MemoryTokenStore();
    await launch(tester, auth: auth, tokens: tokens);

    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.tap(find.text('PLAY AS GUEST'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['guest:test-device-0001']);
    expect(tokens.refreshToken, 'refresh-1');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Guest 6789'), findsOneWidget);
    expect(find.text('Player ID 123 456 789'), findsOneWidget);
  });

  testWidgets('a failed guest sign-in says why and stays on Welcome', (
    tester,
  ) async {
    final auth = FakeAuthApi(failWith: 'rate_limited');
    await launch(tester, auth: auth, tokens: MemoryTokenStore());

    await tester.tap(find.text('PLAY AS GUEST'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Too many tries. Please wait a moment and try again.'),
      findsOneWidget,
    );
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('other sign-in options say coming soon', (tester) async {
    await launch(tester, tokens: MemoryTokenStore());
    await tester.tap(find.text('Sign in with email'));
    await tester.pump();
    expect(find.text('Sign in with email is coming soon.'), findsOneWidget);
  });

  testWidgets('a saved sign-in opens Home directly', (tester) async {
    await launch(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('back to the waiting room the account is in', (tester) async {
    final sockets = FakeSockets();
    final auth = FakeAuthApi(
      account: const Account(
        playerId: 123456789,
        displayName: 'Guest 6789',
        activeRoom: ActiveRoom(code: 'AB12', seatId: 'p-host', isHost: true),
      ),
    );
    await launch(tester, auth: auth, sockets: sockets);
    expect(find.byType(WaitingRoomScreen), findsOneWidget);
    expect(find.text('AB12'), findsOneWidget);
    expect(sockets.last.connectedRoom, 'AB12');
  });

  testWidgets('back to the board when the game has started', (tester) async {
    final sockets = FakeSockets();
    final auth = FakeAuthApi(
      account: const Account(
        playerId: 123456789,
        displayName: 'Guest 6789',
        activeRoom: ActiveRoom(code: 'AB12', seatId: 'p-host', started: true),
      ),
    );
    await launch(tester, auth: auth, sockets: sockets);
    expect(find.byType(GameBoardScreen), findsOneWidget);
    expect(sockets.last.connectedRoom, 'AB12');
  });

  testWidgets('offline at start: try again when the server is back', (
    tester,
  ) async {
    final auth = FakeAuthApi(failWith: ApiException.networkError);
    await launch(tester, auth: auth);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
      find.textContaining("Can't reach the Majlis server"),
      findsOneWidget,
    );

    auth.failWith = null;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a saved sign-in the server ended goes to Welcome', (
    tester,
  ) async {
    final tokens = MemoryTokenStore(refreshToken: 'saved-refresh');
    await launch(
      tester,
      auth: FakeAuthApi(failWith: 'session_revoked'),
      tokens: tokens,
    );
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(tokens.refreshToken, isNull);
  });

  testWidgets('signing out from Settings asks first, then shows Welcome', (
    tester,
  ) async {
    final auth = FakeAuthApi();
    final tokens = MemoryTokenStore(refreshToken: 'saved-refresh');
    await launch(tester, auth: auth, tokens: tokens);

    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Player ID 123 456 789'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be recovered"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(auth.calls.last, 'signOut:access-1');
    expect(tokens.refreshToken, isNull);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
