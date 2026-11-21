import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../data/stats_repository.dart';
import '../domain/player_stats.dart';

/// Your statistics from online games against people, and your latest results.
class StatsCard extends ConsumerWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final stats = ref.watch(statsProvider);
    return MajlisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.statsTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          stats.when(
            data: (stats) => _Body(stats: stats),
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Column(
              children: [
                Text(l10n.apiErrorText(error)),
                TextButton(
                  onPressed: () => ref.invalidate(statsProvider),
                  child: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.statsOnlyRealGames,
            style: theme.textTheme.bodySmall?.copyWith(color: majlis.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats});

  final StatsOverview stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final total = stats.total;
    if (total.gamesPlayed == 0) {
      return Text(l10n.statsEmpty, key: const Key('stats-empty'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Number(
              key: const Key('stats-games'),
              value: '${total.gamesPlayed}',
              label: l10n.statsGames,
            ),
            _Number(
              key: const Key('stats-wins'),
              value: '${total.wins}',
              label: l10n.statsWins,
            ),
            _Number(
              key: const Key('stats-win-rate'),
              value: l10n.statsPercent(total.winRate),
              label: l10n.statsWinRate,
            ),
            _Number(
              key: const Key('stats-best-streak'),
              value: '${total.bestWinStreak}',
              label: l10n.statsBestStreak,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.statsCurrentStreak(total.winStreak),
          style: theme.textTheme.bodyMedium?.copyWith(color: majlis.gold),
        ),
        if (stats.recent.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.statsRecent, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final result in stats.recent) _ResultChip(result: result),
            ],
          ),
        ],
      ],
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.majlis.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  const _ResultChip({required this.result});

  final GameResultEntry result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final majlis = context.majlis;
    final color = result.won
        ? majlis.success
        : result.forfeited
        ? majlis.warning
        : majlis.textMuted;
    final text = result.forfeited
        ? l10n.statsResultLeft
        : l10n.statsResultPlace(result.place, result.playerCount);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}
