import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = RoomSession(roomCode: 'AB12', playerId: 'p1');
  const signedIn = SignedIn(
    Account(playerId: 123456789, displayName: 'Guest 6789'),
  );

  String? redirect(AuthState auth, String path, [RoomSession? room]) =>
      appRedirect(auth: auth, session: room, location: Uri.parse(path));

  group('appRedirect', () {
    test('while checking the sign-in, everything waits on the splash', () {
      for (final auth in const [AuthLoading(), AuthOffline()]) {
        expect(redirect(auth, '/'), isNull);
        expect(redirect(auth, '/home'), AppRoutes.splash);
        expect(redirect(auth, '/game/AB12', session), AppRoutes.splash);
      }
    });

    test('signed out: only the welcome screen (and the splash)', () {
      expect(redirect(const SignedOut(), '/welcome'), isNull);
      expect(redirect(const SignedOut(), '/'), isNull);
      expect(redirect(const SignedOut(), '/home'), AppRoutes.welcome);
      expect(
        redirect(const SignedOut(), '/hub/create-room'),
        AppRoutes.welcome,
      );
    });

    test('signed in: never the welcome screen; rooms need a session', () {
      expect(redirect(signedIn, '/welcome'), AppRoutes.home);
      expect(redirect(signedIn, '/home'), isNull);
      expect(redirect(signedIn, '/'), isNull);
      expect(redirect(signedIn, '/room/AB12'), AppRoutes.home);
      expect(redirect(signedIn, '/room/AB12', session), isNull);
    });
  });

  group('roomGuard', () {
    test('open pages never redirect', () {
      for (final path in ['/', '/home', '/create-room', '/join-room']) {
        expect(roomGuard(null, Uri.parse(path)), isNull, reason: path);
      }
    });

    test('room and game pages need a session', () {
      expect(roomGuard(null, Uri.parse('/room/AB12')), AppRoutes.home);
      expect(roomGuard(null, Uri.parse('/game/AB12')), AppRoutes.home);
    });

    test('the session must be for that same room', () {
      expect(roomGuard(session, Uri.parse('/room/AB12')), isNull);
      expect(roomGuard(session, Uri.parse('/game/AB12')), isNull);
      expect(roomGuard(session, Uri.parse('/room/ZZ99')), AppRoutes.home);
      expect(roomGuard(session, Uri.parse('/game/ZZ99')), AppRoutes.home);
    });
  });

  test('route paths', () {
    expect(AppRoutes.room('AB12'), '/room/AB12');
    expect(AppRoutes.game('AB12'), '/game/AB12');
    expect(AppRoutes.roomOrGame('AB12', started: false), '/room/AB12');
    expect(AppRoutes.roomOrGame('AB12', started: true), '/game/AB12');
  });
}
