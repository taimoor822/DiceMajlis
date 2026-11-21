import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/cosmetic_looks.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../wallet/domain/wallet_models.dart';
import '../../wallet/presentation/currency.dart';
import '../domain/reward_bundle.dart';

/// "+100 Gold, +20 XP, Pearl (7 days)" for a reward.
String describeReward(BuildContext context, RewardBundle reward) {
  final l10n = AppLocalizations.of(context);
  return [
    if (reward.gold > 0)
      l10n.rewardAmount(formatAmount(context, reward.gold), l10n.currencyGold),
    if (reward.diamond > 0)
      l10n.rewardAmount(
        formatAmount(context, reward.diamond),
        l10n.currencyDiamond,
      ),
    if (reward.xp > 0) l10n.rewardXp(reward.xp),
    for (final item in reward.items)
      item.days == null
          ? item.name
          : l10n.rewardItemDays(item.name, item.days!),
  ].join(', ');
}

/// A reward as small chips: coins, diamonds, XP and items.
class RewardChips extends StatelessWidget {
  const RewardChips({super.key, required this.reward, this.style});

  final RewardBundle reward;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final majlis = context.majlis;
    final textStyle = style ?? Theme.of(context).textTheme.labelMedium;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (reward.gold > 0)
          CurrencyAmount(
            currency: Currencies.gold,
            amount: reward.gold,
            signed: true,
            style: textStyle,
          ),
        if (reward.diamond > 0)
          CurrencyAmount(
            currency: Currencies.diamond,
            amount: reward.diamond,
            signed: true,
            style: textStyle,
          ),
        if (reward.xp > 0)
          Text(
            l10n.rewardXp(reward.xp),
            style: textStyle?.copyWith(color: majlis.gold),
          ),
        for (final item in reward.items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: (textStyle?.fontSize ?? 14) + 2,
                color: CosmeticLooks.rarity(item.rarity, majlis),
              ),
              const SizedBox(width: 3),
              Text(
                item.days == null
                    ? item.name
                    : l10n.rewardItemDays(item.name, item.days!),
                style: textStyle,
              ),
            ],
          ),
      ],
    );
  }
}
