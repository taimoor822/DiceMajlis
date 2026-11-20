/// Every path in the app, in one place.
abstract final class AppRoutes {
  static const splash = '/';

  // Main navigation: five tabs (each keeps its own history). Battle, in the
  // centre, is the Home lobby where the app opens.
  static const events = '/events';
  static const hub = '/hub';
  static const home = '/home';
  static const chat = '/chat';
  static const social = '/social';

  static const settings = '/home/settings';

  // Today's room flow lives in Game Hub.
  static const createRoom = '/hub/create-room';
  static const joinRoom = '/hub/join-room';

  /// Waiting room for a game room: `/room/AB12` (full screen, no tab bar).
  static String room(String code) => '/room/$code';

  /// Game board for a game room: `/game/AB12` (full screen, no tab bar).
  static String game(String code) => '/game/$code';
}
