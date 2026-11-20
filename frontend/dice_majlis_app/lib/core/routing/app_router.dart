import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/hub/presentation/game_hub_screen.dart';
import '../../features/ludo/presentation/game_board_screen.dart';
import '../../features/multiplayer/domain/room_session.dart';
import '../../features/multiplayer/domain/room_session_controller.dart';
import '../../features/multiplayer/presentation/create_room_screen.dart';
import '../../features/multiplayer/presentation/join_room_screen.dart';
import '../../features/multiplayer/presentation/waiting_room_screen.dart';
import '../../features/navigation/presentation/main_shell.dart';
import '../../features/navigation/presentation/tab_placeholders.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../auth/auth_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_routes.dart';

/// Where a page request must go instead, or null to show it.
///
/// - While the saved sign-in is being checked (or the server can't be
///   reached), everything waits on the splash screen.
/// - Signed out: the welcome screen ("Play as guest").
/// - Signed in: never the welcome screen again, and rooms need a session for
///   that room ([roomGuard]). The splash screen moves on by itself.
String? appRedirect({
  required AuthState auth,
  required RoomSession? session,
  required Uri location,
}) {
  final path = location.path;
  final atSplash = path == AppRoutes.splash;
  final atWelcome = path == AppRoutes.welcome;
  return switch (auth) {
    AuthLoading() || AuthOffline() => atSplash ? null : AppRoutes.splash,
    SignedOut() => atSplash || atWelcome ? null : AppRoutes.welcome,
    SignedIn() => atWelcome ? AppRoutes.home : roomGuard(session, location),
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
  // Signing in or out sends the player to the right place at once.
  final authChanged = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => authChanged.value++);
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
              builder: (context, state) => const CreateRoomScreen(),
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
            GameBoardScreen(roomCode: state.pathParameters['code']!),
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
