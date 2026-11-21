import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../multiplayer/data/room_repository.dart';
import '../../multiplayer/domain/room_session_controller.dart';
import '../domain/game_catalog.dart';
import '../game_registry.dart';

/// `/game/:code`: the board of the room's game, picked by its `game_type`.
class GameRouteScreen extends ConsumerWidget {
  const GameRouteScreen({super.key, required this.roomCode});

  final String roomCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(roomSessionProvider);
    final gameType = session?.roomCode == roomCode
        ? session!.gameType
        : GameChoice.ludo;
    final module = ref.watch(gameModulesProvider)[gameType];
    if (module == null) return UnsupportedGameScreen(roomCode: roomCode);
    return module.onlineGame(roomCode);
  }
}

/// A game the server runs but this version of the app can't draw yet. The
/// player can leave it (so they can play something else) or go home.
class UnsupportedGameScreen extends ConsumerWidget {
  const UnsupportedGameScreen({super.key, required this.roomCode});

  final String roomCode;

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(roomRepositoryProvider).leaveRoom(roomCode);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.apiErrorText(e))));
      }
      return;
    }
    ref.read(roomSessionProvider.notifier).clear();
    if (context.mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update,
                    size: 48,
                    color: context.majlis.gold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.gameUnsupportedTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.gameUnsupportedBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.majlis.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  MajlisButton(
                    label: l10n.gameLeave,
                    icon: Icons.exit_to_app,
                    onPressed: () => _leave(context, ref),
                  ),
                  const SizedBox(height: 12),
                  MajlisButton(
                    label: l10n.notFoundGoHome,
                    icon: Icons.home_outlined,
                    style: MajlisButtonStyle.secondary,
                    onPressed: () => context.go(AppRoutes.home),
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
