/// Every path in the app, in one place.
abstract final class AppRoutes {
  static const splash = '/';
  static const home = '/home';
  static const createRoom = '/create-room';
  static const joinRoom = '/join-room';

  /// Waiting room for a game room: `/room/AB12`.
  static String room(String code) => '/room/$code';

  /// Game board for a game room: `/game/AB12`.
  static String game(String code) => '/game/$code';
}
