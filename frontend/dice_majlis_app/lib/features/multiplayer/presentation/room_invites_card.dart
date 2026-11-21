import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../games/game_registry.dart';
import '../data/room_repository.dart';
import '../domain/room_info.dart';
import '../domain/room_invites_controller.dart';
import '../domain/room_session_controller.dart';

/// Home: rooms friends invited you to, with Join and Decline. Nothing shows
/// when there are none (or they can't be loaded).
class RoomInvitesCard extends ConsumerStatefulWidget {
  const RoomInvitesCard({super.key});

  @override
  ConsumerState<RoomInvitesCard> createState() => _RoomInvitesCardState();
}

class _RoomInvitesCardState extends ConsumerState<RoomInvitesCard> {
  String? _busyCode;

  /// Invites the server no longer takes: off the list.
  static const _gone = {
    'room_not_found',
    'game_already_started',
    'game_starting',
    'room_full',
    'room_locked',
    'player_kicked',
  };

  Future<void> _join(RoomInvite invite) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyCode = invite.roomCode);
    try {
      final session = await ref
          .read(roomRepositoryProvider)
          .joinRoom(invite.roomCode);
      if (!mounted) return;
      ref.read(roomInvitesProvider.notifier).remove(invite.roomCode);
      ref.read(roomSessionProvider.notifier).start(session);
      context.go(
        AppRoutes.roomOrGame(session.roomCode, started: session.isStarted),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && _gone.contains(e.code)) {
        ref.read(roomInvitesProvider.notifier).remove(invite.roomCode);
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.apiErrorText(e))));
    } finally {
      if (mounted) setState(() => _busyCode = null);
    }
  }

  Future<void> _decline(RoomInvite invite) async {
    ref.read(roomInvitesProvider.notifier).remove(invite.roomCode);
    try {
      await ref.read(roomRepositoryProvider).declineInvite(invite.roomCode);
    } catch (_) {
      // Already gone from the list; the server forgets it when the room starts.
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(roomInvitesProvider).valueOrNull ?? const [];
    if (invites.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final modules = ref.watch(gameModulesProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: MajlisCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.mail_outline_rounded, color: majlis.gold),
                const SizedBox(width: 8),
                Text(l10n.invitesTitle, style: theme.textTheme.titleMedium),
              ],
            ),
            for (final invite in invites)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.inviteFrom(
                          invite.fromName,
                          switch (modules[invite.gameType]) {
                            final GameModule module => gameTitle(
                              l10n,
                              module,
                              invite.variant,
                            ),
                            null => invite.gameType,
                          },
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busyCode == null
                          ? () => _decline(invite)
                          : null,
                      child: Text(l10n.inviteDecline),
                    ),
                    FilledButton(
                      onPressed: _busyCode == null ? () => _join(invite) : null,
                      child: Text(l10n.inviteJoin),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
