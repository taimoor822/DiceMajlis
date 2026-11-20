import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_wordmark.dart';
import '../../multiplayer/domain/room_session.dart';
import '../../multiplayer/domain/room_session_controller.dart';

/// App start: checks the saved sign-in, then goes back to the room the
/// account is in, or Home, or the welcome screen when signed out.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// The logo shows at least this long, even when sign-in is instant.
  static const minimumTime = Duration(milliseconds: 1200);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _offline = false;
  Timer? _minimumTimer;

  @override
  void initState() {
    super.initState();
    // After the first frame: providers can't change while widgets build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() => _offline = false);
    final minimum = Completer<void>();
    _minimumTimer?.cancel();
    _minimumTimer = Timer(SplashScreen.minimumTime, minimum.complete);
    final current = ref.read(authControllerProvider);
    final result = current is SignedIn
        ? current
        : await ref.read(authControllerProvider.notifier).restore();
    await minimum.future; // never completes if the screen closes first
    if (!mounted) return;

    switch (result) {
      case SignedIn(:final account):
        final room = account.activeRoom;
        if (room == null) {
          context.go(AppRoutes.home);
          return;
        }
        final session = RoomSession.fromActiveRoom(room);
        ref.read(roomSessionProvider.notifier).start(session);
        context.go(
          AppRoutes.roomOrGame(session.roomCode, started: session.isStarted),
        );
      case SignedOut():
        context.go(AppRoutes.welcome);
      case AuthOffline():
        setState(() => _offline = true);
      case AuthLoading():
        break;
    }
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    return Scaffold(
      body: MajlisBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MajlisWordmark(
                    title: l10n.appTitle,
                    tagline: l10n.appTagline,
                  ),
                  const SizedBox(height: 40),
                  if (_offline) ...[
                    Text(
                      l10n.splashOffline,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: majlis.textMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    MajlisButton(
                      label: l10n.commonRetry,
                      icon: Icons.refresh,
                      onPressed: _start,
                    ),
                  ] else
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: majlis.gold,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
