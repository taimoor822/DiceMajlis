import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/cosmetic_looks.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../wallet/presentation/currency.dart';
import '../data/achievements_repository.dart';
import '../domain/achievements.dart';

/// The pictures achievements use, by the key the server sends. A key this app
/// doesn't know yet shows a trophy.
const achievementIcons = <String, IconData>{
  'trophy': Icons.emoji_events,
  'dice': Icons.casino,
  'flame': Icons.local_fire_department,
  'star': Icons.star_rounded,
  'crown': Icons.workspace_premium,
};

/// Your achievements: what each counts, how far you are, the tiers and their
/// rewards. They unlock on the server, from real online games.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final overview = ref.watch(achievementsProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.achievementsTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: overview.when(
                data: (overview) => RefreshIndicator(
                  onRefresh: () => ref.refresh(achievementsProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        l10n.achievementsSummary(
                          overview.unlockedTiers,
                          overview.totalTiers,
                        ),
                        key: const Key('achievements-summary'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: majlis.gold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.achievementsOnlyRealGames,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: majlis.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final achievement in overview.achievements) ...[
                        _AchievementCard(achievement: achievement),
                        const SizedBox(height: 12),
                      ],
                      if (overview.hiddenLeft > 0)
                        Text(
                          l10n.achievementsHidden(overview.hiddenLeft),
                          key: const Key('achievements-hidden'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: majlis.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: MajlisCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.apiErrorText(error)),
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(achievementsProvider),
                            child: Text(l10n.commonRetry),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.achievement});

  final AchievementInfo achievement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final rarity = CosmeticLooks.rarity(achievement.rarity, majlis);
    final next = achievement.nextThreshold;
    return MajlisCard(
      key: ValueKey('achievement-${achievement.code}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: rarity.withValues(alpha: 0.18),
                child: Icon(
                  achievementIcons[achievement.icon] ?? Icons.emoji_events,
                  color: achievement.unlockedTiers > 0
                      ? rarity
                      : majlis.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(achievement.name, style: theme.textTheme.titleMedium),
                    Text(
                      achievement.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: majlis.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (next != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: achievement.progress,
                minHeight: 6,
                color: majlis.gold,
                backgroundColor: majlis.glassBorder,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.achievementsProgress(achievement.value, next),
              style: theme.textTheme.labelMedium,
            ),
          ] else
            Text(
              l10n.achievementsCompleted,
              style: theme.textTheme.labelLarge?.copyWith(
                color: majlis.success,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tier in achievement.tiers) _TierChip(tier: tier),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({required this.tier});

  final AchievementTierInfo tier;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    final theme = Theme.of(context);
    final color = tier.unlocked ? majlis.gold : majlis.glassBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: tier.unlocked ? 1.5 : 1),
        color: majlis.glassFill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tier.unlocked ? Icons.check_circle : Icons.flag_outlined,
            size: 16,
            color: tier.unlocked ? majlis.gold : majlis.textMuted,
          ),
          const SizedBox(width: 6),
          Text('${tier.threshold}', style: theme.textTheme.labelLarge),
          for (final entry in tier.reward.entries) ...[
            const SizedBox(width: 8),
            CurrencyAmount(
              currency: entry.key,
              amount: entry.value,
              signed: true,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// "+100 Gold, +5 Diamonds" for a reward bundle.
String rewardText(BuildContext context, Map<String, int> reward) {
  final l10n = AppLocalizations.of(context);
  return reward.entries
      .map(
        (entry) => l10n.rewardAmount(
          formatAmount(context, entry.value),
          currencyName(l10n, entry.key),
        ),
      )
      .join(', ');
}
