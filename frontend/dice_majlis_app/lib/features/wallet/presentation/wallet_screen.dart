import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../data/wallet_repository.dart';
import '../domain/wallet_models.dart';
import 'currency.dart';

/// Balances and the history of every change (the server's ledger).
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  final List<WalletEntry> _entries = [];
  String? _next;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(first: true);
    // Balances may have changed on the server since Home loaded them.
    Future.microtask(() => ref.read(balancesProvider.notifier).refresh());
  }

  Future<void> _load({bool first = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(walletRepositoryProvider)
          .history(before: first ? null : _next);
      if (!mounted) return;
      setState(() {
        if (first) _entries.clear();
        _entries.addAll(page.entries);
        _next = page.next;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(balancesProvider.notifier).refresh(),
      _load(first: true),
    ]);
  }

  String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
    'reward_daily' => l10n.walletTypeDaily,
    'reward_achievement' => l10n.walletTypeAchievement,
    'admin_grant' => l10n.walletTypeAdminGrant,
    'admin_revoke' => l10n.walletTypeAdminRevoke,
    'reversal' => l10n.walletTypeReversal,
    _ => l10n.walletTypeOther,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final balances = ref.watch(balancesProvider).value;
    final when = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).add_jm();

    Widget balanceCard(String currency, int? amount) => Expanded(
      child: MajlisCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CurrencyIcon(currency, size: 30),
            const SizedBox(height: 6),
            Text(
              amount == null ? '–' : formatAmount(context, amount),
              style: theme.textTheme.headlineSmall,
            ),
            Text(
              currencyName(l10n, currency),
              style: theme.textTheme.bodySmall?.copyWith(
                color: majlis.textMuted,
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l10n.walletTitle),
        actions: [
          IconButton(
            key: const Key('wallet-reward-history'),
            tooltip: l10n.rewardHistoryTitle,
            icon: const Icon(Icons.redeem),
            onPressed: () => context.push(AppRoutes.rewardHistory),
          ),
        ],
      ),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        balanceCard(Currencies.gold, balances?.gold),
                        const SizedBox(width: 12),
                        balanceCard(Currencies.diamond, balances?.diamond),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.walletEarnHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: majlis.textMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.walletHistory,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_entries.isEmpty && !_loading && _error == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          l10n.walletEmpty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: majlis.textMuted,
                          ),
                        ),
                      ),
                    for (final entry in _entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CurrencyIcon(entry.currency, size: 26),
                        title: Text(_typeLabel(l10n, entry.type)),
                        subtitle: Text(
                          [
                            if (entry.createdAt != null)
                              when.format(entry.createdAt!.toLocal()),
                            entry.reference,
                          ].join(' · '),
                        ),
                        trailing: Text(
                          entry.amount > 0
                              ? '+${formatAmount(context, entry.amount)}'
                              : formatAmount(context, entry.amount),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: entry.amount > 0
                                ? majlis.success
                                : majlis.danger,
                          ),
                        ),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      Column(
                        children: [
                          Text(l10n.apiErrorText(_error!)),
                          TextButton(
                            onPressed: () => _load(first: _entries.isEmpty),
                            child: Text(l10n.commonRetry),
                          ),
                        ],
                      )
                    else if (_next != null)
                      TextButton(
                        onPressed: _load,
                        child: Text(l10n.walletLoadMore),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
