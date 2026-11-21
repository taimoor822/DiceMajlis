/// Every path in the app, in one place.
abstract final class AppRoutes {
  static const splash = '/';

  /// First visit or signed out: "Play as guest" or email.
  static const welcome = '/welcome';
  static const welcomeEmail = '/welcome/email';
  static const forgotPassword = '/welcome/forgot';

  // Main navigation: five tabs (each keeps its own history). Battle, in the
  // centre, is the Home lobby where the app opens.
  static const events = '/events';
  static const hub = '/hub';
  static const home = '/home';
  static const chat = '/chat';
  static const social = '/social';

  static const settings = '/home/settings';
  static const saveAccount = '/home/settings/save-account';
  static const profile = '/home/profile';
  static const customise = '/home/profile/customise';
  static const achievements = '/home/profile/achievements';
  static const wallet = '/home/wallet';
  static const rewardHistory = '/home/wallet/rewards';

  // Today's room flow lives in Game Hub.
  static const createRoom = '/hub/create-room';

  /// Create a room for one game and variant: `/hub/create-room?game=ludo&variant=classic`.
  static String createRoomFor(String gameType, String variant) => Uri(
    path: createRoom,
    queryParameters: {'game': gameType, 'variant': variant},
  ).toString();
  static const joinRoom = '/hub/join-room';

  /// Offline games on this phone (vs AI, pass-and-play): pick players, then
  /// play. Full screen, and open whether signed in or not (no server needed).
  static const localPlay = '/local';
  static const localGame = '/local/game';

  /// True for the offline-game pages.
  static bool isLocal(String path) =>
      path == localPlay || path.startsWith('$localPlay/');

  /// Waiting room for a game room: `/room/AB12` (full screen, no tab bar).
  static String room(String code) => '/room/$code';

  /// Game board for a game room: `/game/AB12` (full screen, no tab bar).
  static String game(String code) => '/game/$code';

  /// The page for a room you're in: the board once the game has started.
  static String roomOrGame(String code, {required bool started}) =>
      started ? game(code) : room(code);
}
