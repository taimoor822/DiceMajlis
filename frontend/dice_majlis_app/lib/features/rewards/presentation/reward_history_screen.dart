import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../data/rewards_repository.dart';
import '../domain/reward_bundle.dart';
import 'reward_view.dart';

/// Every reward you got (daily rewards, achievements ...), newest first.
class RewardHistoryScreen extends ConsumerStatefulWidget {
  const RewardHistoryScreen({super.key});

  @override
  ConsumerState<RewardHistoryScreen> createState() =>
      _RewardHistoryScreenState();
}

class _RewardHistoryScreenState extends ConsumerState<RewardHistoryScreen> {
  final _entries = <RewardHistoryEntry>[];
  String? _next;
  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load(first: true));
  }

  Future<void> _load({bool first = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(rewardsRepositoryProvider)
          .history(before: first ? null : _next);
      if (!mounted) return;
      setState(() {
        if (first) _entries.clear();
        _entries.addAll(page.entries);
        _next = page.next;
        _loadedOnce = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _title(AppLocalizations l10n, RewardHistoryEntry entry) =>
      switch (entry.kind) {
        'daily_login' => l10n.rewardHistoryDaily(entry.day ?? 1),
        'achievement' => l10n.rewardHistoryAchievement(
          entry.threshold == null
              ? entry.achievement ?? ''
              : '${entry.achievement ?? ''} (${entry.threshold})',
        ),
        _ => l10n.rewardHistoryOther,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final locale = Localizations.localeOf(context).toString();
    final when = DateFormat.yMMMd(locale).add_jm();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.rewardHistoryTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: RefreshIndicator(
                onRefresh: () => _load(first: true),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_loadedOnce && _entries.isEmpty)
                      MajlisCard(
                        child: Text(
                          l10n.rewardHistoryEmpty,
                          key: const Key('reward-history-empty'),
                        ),
                      ),
                    for (final entry in _entries) ...[
                      MajlisCard(
                        key: ValueKey('reward-${entry.id}'),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title(l10n, entry),
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              when.format(entry.createdAt.toLocal()),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: majlis.textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            RewardChips(reward: entry.reward),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_error != null)
                      Column(
                        children: [
                          Text(l10n.apiErrorText(_error!)),
                          TextButton(
                            onPressed: () => _load(first: !_loadedOnce),
                            child: Text(l10n.commonRetry),
                          ),
                        ],
                      )
                    else if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
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
