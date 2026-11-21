import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/achievements/presentation/achievements_screen.dart';
import '../../features/auth/presentation/email_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/cosmetics/presentation/customise_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/hub/presentation/game_hub_screen.dart';
import '../../features/local_play/presentation/local_game_screen.dart';
import '../../features/local_play/presentation/local_setup_screen.dart';
import '../../features/games/domain/game_catalog.dart';
import '../../features/games/presentation/game_route_screen.dart';
import '../../features/multiplayer/domain/room_session.dart';
import '../../features/multiplayer/domain/room_session_controller.dart';
import '../../features/multiplayer/presentation/create_room_screen.dart';
import '../../features/multiplayer/presentation/join_room_screen.dart';
import '../../features/multiplayer/presentation/waiting_room_screen.dart';
import '../../features/navigation/presentation/main_shell.dart';
import '../../features/navigation/presentation/tab_placeholders.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/save_account_screen.dart';
import '../../features/rewards/presentation/reward_history_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../auth/auth_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_routes.dart';

/// Where a page request must go instead, or null to show it.
///
/// - While the saved sign-in is being checked (or the server can't be
///   reached), everything waits on the splash screen.
/// - Signed out: the welcome screens (guest, email, forgotten password).
/// - Signed in: never the welcome screens again (straight back to the room the
///   account is in, if any), and rooms need a session for that room
///   ([roomGuard]). The splash screen moves on by itself.
/// - Offline games on this phone are open in every case: they need no
///   account and no server.
String? appRedirect({
  required AuthState auth,
  required RoomSession? session,
  required Uri location,
}) {
  final path = location.path;
  if (AppRoutes.isLocal(path)) return null;
  final atSplash = path == AppRoutes.splash;
  final atWelcome =
      path == AppRoutes.welcome || path.startsWith('${AppRoutes.welcome}/');
  return switch (auth) {
    AuthLoading() || AuthOffline() => atSplash ? null : AppRoutes.splash,
    SignedOut() => atSplash || atWelcome ? null : AppRoutes.welcome,
    SignedIn() when atWelcome =>
      session == null
          ? AppRoutes.home
          : AppRoutes.roomOrGame(session.roomCode, started: session.isStarted),
    SignedIn() => roomGuard(session, location),
  };
}

/// Room and game pages need a session for that room; without one (e.g. a
/// stale link) the player goes Home instead of seeing a broken screen.
/// Returns the path to redirect to, or null.
String? roomGuard(RoomSession? session, Uri location) {
  final segments = location.pathSegments;
  if (segments.length < 2) return null;
  if (segments.first != 'room' && segments.first != 'game') return null;
  final code = segments[1];
  if (session == null || session.roomCode != code) return AppRoutes.home;
  return null;
}

/// One tab of the main navigation: its first page and the pages under it.
StatefulShellBranch _tab(
  String path,
  Widget page, [
  List<RouteBase> children = const [],
]) => StatefulShellBranch(
  routes: [
    GoRoute(path: path, builder: (context, state) => page, routes: children),
  ],
);

final appRouterProvider = Provider<GoRouter>((ref) {
  // Signing in or out sends the player to the right place at once. The room
  // session is read first so it follows sign-in changes (it listens too)
  // before the router reacts to them.
  ref.read(roomSessionProvider);
  final authChanged = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (previous, next) {
    // Only signing in/out matters here, not a newer copy of the account.
    if (previous.runtimeType != next.runtimeType) authChanged.value++;
  });
  ref.onDispose(authChanged.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authChanged,
    redirect: (context, state) => appRedirect(
      auth: ref.read(authControllerProvider),
      session: ref.read(roomSessionProvider),
      location: state.uri,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'email',
            builder: (context, state) => const EmailScreen(),
          ),
          GoRoute(
            path: 'forgot',
            builder: (context, state) => const ForgotPasswordScreen(),
          ),
        ],
      ),
      // The five tabs, with the bottom bar. The order here is the order of
      // the bar (MainShell); Battle, in the centre, is the Home lobby.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(navigationShell: shell),
        branches: [
          _tab(AppRoutes.events, const EventsScreen()),
          _tab(AppRoutes.hub, const GameHubScreen(), [
            GoRoute(
              path: 'create-room',
              builder: (context, state) => CreateRoomScreen(
                game: GameChoice(
                  gameType:
                      state.uri.queryParameters['game'] ?? GameChoice.ludo,
                  variant:
                      state.uri.queryParameters['variant'] ??
                      GameChoice.classic,
                ),
              ),
            ),
            GoRoute(
              path: 'join-room',
              builder: (context, state) => const JoinRoomScreen(),
            ),
          ]),
          _tab(AppRoutes.home, const HomeScreen(), [
            GoRoute(
              path: 'settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'save-account',
                  builder: (context, state) => const SaveAccountScreen(),
                ),
              ],
            ),
            GoRoute(
              path: 'profile',
              builder: (context, state) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'customise',
                  builder: (context, state) => const CustomiseScreen(),
                ),
                GoRoute(
                  path: 'achievements',
                  builder: (context, state) => const AchievementsScreen(),
                ),
              ],
            ),
            GoRoute(
              path: 'wallet',
              builder: (context, state) => const WalletScreen(),
              routes: [
                GoRoute(
                  path: 'rewards',
                  builder: (context, state) => const RewardHistoryScreen(),
                ),
              ],
            ),
          ]),
          _tab(AppRoutes.chat, const ChatScreen()),
          _tab(AppRoutes.social, const SocialScreen()),
        ],
      ),
      // Rooms and games are full screen, above the tab bar.
      GoRoute(
        path: '/room/:code',
        builder: (context, state) =>
            WaitingRoomScreen(roomCode: state.pathParameters['code']!),
      ),
      GoRoute(
        path: '/game/:code',
        builder: (context, state) =>
            GameRouteScreen(roomCode: state.pathParameters['code']!),
      ),
      GoRoute(
        path: AppRoutes.localPlay,
        builder: (context, state) => const LocalSetupScreen(),
        routes: [
          GoRoute(
            path: 'game',
            builder: (context, state) => const LocalGameScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const _NotFoundScreen(),
  );
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notFoundTitle)),
      body: Center(
        child: TextButton(
          onPressed: () => context.go(AppRoutes.home),
          child: Text(l10n.notFoundGoHome),
        ),
      ),
    );
  }
}
