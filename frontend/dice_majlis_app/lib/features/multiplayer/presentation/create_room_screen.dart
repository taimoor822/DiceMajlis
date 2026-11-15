import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../data/room_repository.dart';
import '../domain/room_session_controller.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  // TODO(1.10 game platform): seat choices come from the game variant.
  static const seatChoices = [2, 3, 4];

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  int _maxPlayers = CreateRoomScreen.seatChoices.last;
  bool _loading = false;

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      final session = await ref
          .read(roomRepositoryProvider)
          .createRoom(maxPlayers: _maxPlayers);
      if (!mounted) return;
      ref.read(roomSessionProvider.notifier).start(session);
      context.push(AppRoutes.room(session.roomCode));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.createRoomFailed)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.createRoomTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MajlisCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.createRoomMaxPlayers,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final count in CreateRoomScreen.seatChoices)
                            ChoiceChip(
                              label: Text('$count'),
                              selected: _maxPlayers == count,
                              onSelected: _loading
                                  ? null
                                  : (_) => setState(() => _maxPlayers = count),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.createRoomHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.majlis.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                MajlisButton(
                  label: l10n.createRoomCreate,
                  icon: Icons.casino_outlined,
                  loading: _loading,
                  onPressed: _loading ? null : _create,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
