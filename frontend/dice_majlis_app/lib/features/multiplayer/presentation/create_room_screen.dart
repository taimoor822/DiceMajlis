import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/game_registry.dart';
import '../data/room_repository.dart';
import '../domain/room_session_controller.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key, this.game = const GameChoice()});

  /// The game and variant picked in Game Hub.
  final GameChoice game;

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  /// The player's pick; null means "the server's default".
  int? _picked;
  bool _loading = false;

  Future<void> _create(int maxPlayers) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      final session = await ref
          .read(roomRepositoryProvider)
          .createRoom(maxPlayers: maxPlayers, game: widget.game);
      if (!mounted) return;
      ref.read(roomSessionProvider.notifier).start(session);
      context.push(AppRoutes.room(session.roomCode));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.apiErrorText(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = ref.watch(roomOptionsProvider(widget.game));
    final module = ref.watch(gameModulesProvider)[widget.game.gameType];
    final ready = options.asData?.value;
    final selected = ready == null
        ? null
        : (_picked != null && ready.playerCounts.contains(_picked)
              ? _picked!
              : ready.defaultPlayerCount);

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
                if (module != null) ...[
                  Text(
                    gameTitle(l10n, module, widget.game.variant),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                ],
                MajlisCard(
                  child: options.when(
                    data: (data) => _PlayerCountPicker(
                      counts: data.playerCounts,
                      selected: selected,
                      enabled: !_loading,
                      onSelected: (count) => setState(() => _picked = count),
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => _OptionsError(
                      message: l10n.apiErrorText(error),
                      onRetry: () =>
                          ref.invalidate(roomOptionsProvider(widget.game)),
                    ),
                  ),
                ),
                const Spacer(),
                MajlisButton(
                  label: l10n.createRoomCreate,
                  icon: Icons.casino_outlined,
                  loading: _loading,
                  onPressed: (_loading || selected == null)
                      ? null
                      : () => _create(selected),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerCountPicker extends StatelessWidget {
  const _PlayerCountPicker({
    required this.counts,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final List<int> counts;
  final int? selected;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.createRoomMaxPlayers, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          children: [
            for (final count in counts)
              ChoiceChip(
                label: Text('$count'),
                selected: selected == count,
                onSelected: enabled ? (_) => onSelected(count) : null,
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
    );
  }
}

class _OptionsError extends StatelessWidget {
  const _OptionsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.createRoomOptionsFailed, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.majlis.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.commonRetry),
        ),
      ],
    );
  }
}
