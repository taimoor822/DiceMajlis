import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = RoomSession(roomCode: 'AB12', playerId: 'p1');

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
  });
}
