import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/majlis_colors.dart';
import '../domain/wallet_models.dart';

/// "1,250", or "1.2M" for big numbers, in the app's language.
String formatAmount(BuildContext context, int amount) {
  final locale = Localizations.localeOf(context).toString();
  return amount.abs() >= 1000000
      ? NumberFormat.compact(locale: locale).format(amount)
      : NumberFormat.decimalPattern(locale).format(amount);
}

/// The currency's name ("Gold", "Diamonds").
String currencyName(AppLocalizations l10n, String currency) =>
    currency == Currencies.diamond ? l10n.currencyDiamond : l10n.currencyGold;

/// The currency's icon in its colour: gold coins, turquoise diamond.
class CurrencyIcon extends StatelessWidget {
  const CurrencyIcon(this.currency, {super.key, this.size = 20});

  final String currency;
  final double size;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    final diamond = currency == Currencies.diamond;
    return Icon(
      diamond ? Icons.diamond : Icons.toll,
      size: size,
      color: diamond ? majlis.accent : majlis.gold,
      semanticLabel: currencyName(AppLocalizations.of(context), currency),
    );
  }
}

/// Icon + amount, e.g. 🪙 1,250.
class CurrencyAmount extends StatelessWidget {
  const CurrencyAmount({
    super.key,
    required this.currency,
    required this.amount,
    this.style,
    this.signed = false,
  });

  final String currency;
  final int amount;
  final TextStyle? style;

  /// Show + for amounts received.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final text = formatAmount(context, amount);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CurrencyIcon(currency, size: (style?.fontSize ?? 16) + 2),
        const SizedBox(width: 4),
        Text(signed && amount > 0 ? '+$text' : text, style: style),
      ],
    );
  }
}
