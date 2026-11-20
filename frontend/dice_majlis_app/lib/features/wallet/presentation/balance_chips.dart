import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../data/wallet_repository.dart';
import '../domain/wallet_models.dart';
import 'currency.dart';

/// Gold and diamonds at the top of Home. Tap to open the wallet.
class BalanceChips extends ConsumerWidget {
  const BalanceChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final balances = ref.watch(balancesProvider);
    final majlis = context.majlis;
    final style = Theme.of(context).textTheme.labelLarge;

    Widget chip(String currency, int? amount) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: majlis.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: majlis.glassBorder),
      ),
      child: amount == null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CurrencyIcon(currency, size: 18),
                const SizedBox(width: 4),
                Text('–', style: style),
              ],
            )
          : CurrencyAmount(currency: currency, amount: amount, style: style),
    );

    final value = balances.value;
    return Semantics(
      button: true,
      label: l10n.homeWallet,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => context.go(AppRoutes.wallet),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip(Currencies.gold, value?.gold),
            const SizedBox(width: 8),
            chip(Currencies.diamond, value?.diamond),
          ],
        ),
      ),
    );
  }
}
