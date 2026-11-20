import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../wallet/domain/wallet_models.dart';
import '../../wallet/presentation/currency.dart';
import '../data/rewards_repository.dart';
import '../domain/daily_reward.dart';

/// The daily reward on Home: the 7 days of the cycle, today's highlighted,
/// and a Claim button (or when the next one comes).
class DailyRewardCard extends ConsumerStatefulWidget {
  const DailyRewardCard({super.key});

  @override
  ConsumerState<DailyRewardCard> createState() => _DailyRewardCardState();
}

class _DailyRewardCardState extends ConsumerState<DailyRewardCard> {
  bool _claiming = false;

  String _describe(DailyRewardDay day) {
    final parts = [
      if (day.gold > 0)
        '${formatAmount(context, day.gold)} ${AppLocalizations.of(context).currencyGold}',
      if (day.diamond > 0)
        '${formatAmount(context, day.diamond)} ${AppLocalizations.of(context).currencyDiamond}',
    ];
    return parts.join(' + ');
  }

  Future<void> _claim() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _claiming = true);
    try {
      final got = await ref.read(dailyRewardProvider.notifier).claim();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.dailyGot(_describe(got)))));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.apiErrorText(error))));
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final daily = ref.watch(dailyRewardProvider);

    return MajlisCard(
      child: daily.when(
        loading: () => const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Row(
          children: [
            Expanded(child: Text(l10n.dailyFailed)),
            TextButton(
              onPressed: () => ref.read(dailyRewardProvider.notifier).refresh(),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
        data: (status) {
          final today = status.today;
          final nextDay = status.days.isEmpty
              ? 1
              : status.day % status.days.length + 1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.card_giftcard, color: majlis.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.dailyTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    l10n.dailyDay(status.day),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: majlis.gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final day in status.days)
                    Expanded(
                      child: _DayTile(
                        day: day,
                        isToday: day.day == status.day,
                        done:
                            day.day < status.day ||
                            (day.day == status.day && status.claimedToday),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!status.claimedToday && today != null)
                MajlisButton(
                  label: l10n.dailyClaim,
                  icon: Icons.redeem,
                  loading: _claiming,
                  onPressed: _claiming ? null : _claim,
                )
              else ...[
                Text(
                  l10n.dailyClaimed(nextDay),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.dailyNextIn(_hoursLeft(status.secondsUntilReset)),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: majlis.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                l10n.dailyHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: majlis.textMuted,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Whole hours, rounded; 0 means "less than an hour".
int _hoursLeft(int seconds) => seconds < 3600 ? 0 : (seconds + 1800) ~/ 3600;

/// One day of the cycle: its number and what it gives.
class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.isToday,
    required this.done,
  });

  final DailyRewardDay day;
  final bool isToday;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final diamond = day.diamond > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isToday
              ? majlis.gold.withValues(alpha: 0.16)
              : majlis.glassFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isToday ? majlis.gold : majlis.glassBorder,
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: majlis.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            done
                ? Icon(Icons.check_circle, size: 20, color: majlis.success)
                : CurrencyIcon(
                    diamond ? Currencies.diamond : Currencies.gold,
                    size: 20,
                  ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                diamond
                    ? formatAmount(context, day.diamond)
                    : formatAmount(context, day.gold),
                semanticsLabel:
                    '${l10n.dailyDay(day.day)}: '
                    '${formatAmount(context, diamond ? day.diamond : day.gold)}',
                style: theme.textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
