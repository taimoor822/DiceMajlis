// Signing in, staying signed in and signing out, without a server.

import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/core/auth/auth_api.dart';
import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/core/auth/token_store.dart';
import 'package:dice_majlis_app/core/network/api_exception.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeAuthApi api;
  late MemoryTokenStore store;
  late ProviderContainer container;

  ProviderContainer start({String? savedRefresh}) {
    api = FakeAuthApi();
    store = MemoryTokenStore(refreshToken: savedRefresh);
    container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  AuthController auth() => container.read(authControllerProvider.notifier);
  AuthState state() => container.read(authControllerProvider);

  group('app start', () {
    test('no saved sign-in: signed out', () async {
      start();
      expect(state(), isA<AuthLoading>());
      expect(await auth().restore(), isA<SignedOut>());
      expect(api.calls, isEmpty);
    });

    test('a saved sign-in is refreshed and the new token saved', () async {
      start(savedRefresh: 'saved');
      final result = await auth().restore();
      expect(result, isA<SignedIn>());
      expect((result as SignedIn).account.playerId, 123456789);
      expect(api.calls, ['refresh:saved']);
      expect(store.refreshToken, 'refresh-1');
      expect(container.read(accountProvider)?.displayName, 'Player 6789');
    });

    test('a sign-in the server ended is forgotten', () async {
      for (final code in [
        'session_revoked',
        'refresh_expired',
        'invalid_refresh',
      ]) {
        start(savedRefresh: 'saved');
        api.failWith = code;
        expect(await auth().restore(), isA<SignedOut>(), reason: code);
        expect(store.refreshToken, isNull, reason: code);
      }
    });

    test('offline: the saved sign-in is kept for a retry', () async {
      start(savedRefresh: 'saved');
      api.failWith = ApiException.networkError;
      expect(await auth().restore(), isA<AuthOffline>());
      expect(store.refreshToken, 'saved');

      api.failWith = null;
      expect(await auth().restore(), isA<SignedIn>());
    });
  });

  test('play as guest signs in with this device', () async {
    start();
    await auth().restore();
    await auth().signInAsGuest();
    expect(state(), isA<SignedIn>());
    expect(api.calls, ['guest:test-device-0001']);
    expect(store.refreshToken, 'refresh-1');
  });

  group('email', () {
    test('sign in with email', () async {
      start();
      await auth().restore();
      await auth().signInWithEmail(' sara@example.com ', 'pw-123456');
      expect(state(), isA<SignedIn>());
      expect(api.calls, ['login:sara@example.com:pw-123456']);
      expect(store.refreshToken, 'refresh-1');
    });

    test('wrong password: still signed out, the error is passed on', () async {
      start();
      await auth().restore();
      api.failWith = 'invalid_credentials';
      await expectLater(
        auth().signInWithEmail('sara@example.com', 'nope'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      expect(state(), isA<SignedOut>());
    });

    test('create an account', () async {
      start();
      await auth().restore();
      await auth().createAccount('new@example.com', 'pw-123456');
      final account = (state() as SignedIn).account;
      expect((account.email, account.isGuest), ('new@example.com', false));
    });

    test('reset password: new password, then signed in with it', () async {
      start();
      await auth().restore();
      await auth().resetPassword(
        email: 'sara@example.com',
        code: ' 123456 ',
        newPassword: 'new-pw-2027',
      );
      expect(api.calls, [
        'confirm:sara@example.com:123456:new-pw-2027',
        'login:sara@example.com:new-pw-2027',
      ]);
      expect(state(), isA<SignedIn>());
    });

    test('a newer account copy replaces the signed-in one', () async {
      start(savedRefresh: 'saved');
      await auth().restore();
      auth().accountChanged(testAccount.copyWith(displayName: 'Sara'));
      expect(container.read(accountProvider)?.displayName, 'Sara');
    });
  });

  group('access token', () {
    test('reused while fresh', () async {
      start(savedRefresh: 'saved');
      await auth().restore();
      expect(await auth().accessToken(), 'access-1');
      expect(await auth().accessToken(), 'access-1');
      expect(api.calls, ['refresh:saved']);
    });

    test('about to expire: one refresh for everyone waiting', () async {
      start(savedRefresh: 'saved');
      api.lifetime = Duration.zero;
      await auth().restore();
      final tokens = await Future.wait([
        auth().accessToken(),
        auth().accessToken(),
        auth().accessToken(),
      ]);
      expect(tokens, ['access-2', 'access-2', 'access-2']);
      expect(api.calls, ['refresh:saved', 'refresh:refresh-1']);
      expect(store.refreshToken, 'refresh-2');
    });

    test('signed out: none', () async {
      start();
      await auth().restore();
      expect(await auth().accessToken(), isNull);
    });

    test('the server ended the session: signed out', () async {
      start(savedRefresh: 'saved');
      await auth().restore();
      api.failWith = 'session_revoked';
      expect(await auth().refreshAccess(), isNull);
      expect(state(), isA<SignedOut>());
      expect(store.refreshToken, isNull);
    });

    test('offline: the request fails but the player stays signed in', () async {
      start(savedRefresh: 'saved');
      await auth().restore();
      api.failWith = ApiException.networkError;
      await expectLater(auth().refreshAccess(), throwsA(isA<ApiException>()));
      expect(state(), isA<SignedIn>());
      expect(store.refreshToken, 'refresh-1');
    });
  });

  test('signing out tells the server and leaves the room screens', () async {
    start(savedRefresh: 'saved');
    await auth().restore();
    container
        .read(roomSessionProvider.notifier)
        .start(const RoomSession(roomCode: 'AB12', playerId: 'p1'));

    await auth().signOut();
    expect(api.calls.last, 'signOut:access-1');
    expect(state(), isA<SignedOut>());
    expect(store.refreshToken, isNull);
    expect(container.read(roomSessionProvider), isNull);
  });

  test('signing out offline still signs out here', () async {
    start(savedRefresh: 'saved');
    await auth().restore();
    api.failWith = ApiException.networkError;
    await auth().signOut();
    expect(state(), isA<SignedOut>());
  });

  test('the account and its room come from the server JSON', () {
    final account = Account.fromJson({
      'player_id': 123456789,
      'display_name': 'Guest 6789',
      'is_guest': true,
      'email': null,
      'avatar': 'dhow',
      'country': 'BH',
      'languages': ['ar', 'en'],
      'level': 2,
      'xp': 150,
      'level_xp': 100,
      'next_level_xp': 300,
      'created_at': '2026-11-20T10:00:00Z',
      'active_room': {
        'code': 'AB12',
        'seat_id': 'seat-1',
        'is_host': false,
        'max_players': 4,
        'started': true,
      },
    });
    expect(account.isGuest, isTrue);
    expect((account.avatar, account.country), ('dhow', 'BH'));
    expect(account.languages, ['ar', 'en']);
    expect((account.level, account.xp), (2, 150));
    expect(account.levelProgress, 0.25);
    expect(account.activeRoom?.code, 'AB12');
    expect(account.activeRoom?.seatId, 'seat-1');
    expect(account.activeRoom?.started, isTrue);
  });

  test('Player IDs read in groups of three', () {
    expect(formatPlayerId(123456789), '123 456 789');
    expect(formatPlayerId(100000000), '100 000 000');
    expect(formatPlayerId(12345), '12 345');
  });

  test('device ids are 32 random hex characters', () {
    final id = newDeviceId();
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(newDeviceId(), isNot(id));
  });
}
