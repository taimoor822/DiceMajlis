import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../ludo/domain/engine/ludo_engine.dart';
import '../domain/local_game_setup.dart';
import '../domain/local_play_providers.dart';
import 'local_names.dart';

/// Pick 2–4 players and who plays each colour (a person or the Majlis AI),
/// then start an offline game on this phone.
class LocalSetupScreen extends ConsumerStatefulWidget {
  const LocalSetupScreen({super.key});

  @override
  ConsumerState<LocalSetupScreen> createState() => _LocalSetupScreenState();
}

class _LocalSetupScreenState extends ConsumerState<LocalSetupScreen> {
  late LocalGameSetup _setup =
      ref.read(localGameSetupProvider) ?? LocalGameSetup.standard();

  void _start() {
    ref.read(localGameSetupProvider.notifier).set(_setup);
    context.push(AppRoutes.localGame);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.localSetupTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text(
                    l10n.localSetupBody,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: majlis.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.localSetupPlayers,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: [
                      for (
                        var n = LudoBoard.minPlayers;
                        n <= LudoBoard.maxPlayers;
                        n++
                      )
                        ButtonSegment(value: n, label: Text('$n')),
                    ],
                    selected: {_setup.playerCount},
                    showSelectedIcon: false,
                    onSelectionChanged: (choice) => setState(
                      () => _setup = _setup.withPlayerCount(choice.single),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.localSetupSeats,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  for (final seat in _setup.seats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SeatRow(
                        key: ValueKey('local-seat-$seat'),
                        seat: seat,
                        setup: _setup,
                        onChanged: (kind) => setState(
                          () => _setup = _setup.withKind(seat, kind),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  MajlisCard(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile(
                      title: Text(l10n.localSetupPlayOn),
                      subtitle: Text(l10n.localSetupPlayOnBody),
                      value: _setup.playOn,
                      onChanged: (value) =>
                          setState(() => _setup = _setup.withPlayOn(value)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  MajlisButton(
                    label: l10n.localSetupStart,
                    icon: Icons.play_arrow_rounded,
                    onPressed: _start,
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

class _SeatRow extends StatelessWidget {
  const _SeatRow({
    super.key,
    required this.seat,
    required this.setup,
    required this.onChanged,
  });

  final int seat;
  final LocalGameSetup setup;
  final ValueChanged<LocalSeatKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final color = MajlisColors.seatColor(LudoBoard.seatColors[seat]);

    return MajlisCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seatColorName(l10n, seat),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  localPlayerName(l10n, setup, seat),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: majlis.textMuted,
                  ),
                ),
              ],
            ),
          ),
          SegmentedButton<LocalSeatKind>(
            segments: [
              ButtonSegment(
                value: LocalSeatKind.human,
                icon: const Icon(Icons.person_outline),
                label: Text(l10n.localSeatHuman),
              ),
              ButtonSegment(
                value: LocalSeatKind.ai,
                icon: const Icon(Icons.smart_toy_outlined),
                label: Text(l10n.localSeatAi),
              ),
            ],
            selected: {setup.kinds[seat]!},
            showSelectedIcon: false,
            onSelectionChanged: (choice) => onChanged(choice.single),
          ),
        ],
      ),
    );
  }
}
