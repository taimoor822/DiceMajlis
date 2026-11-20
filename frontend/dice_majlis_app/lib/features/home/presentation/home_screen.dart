import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/account.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/coming_soon.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../../shared/widgets/majlis_wordmark.dart';
import '../../../shared/widgets/player_avatar.dart';

/// Where the app opens. The profile card shows the signed-in account; wallet
/// and the shortcuts fill in as their plan steps land (profile 1.7, currency
/// 1.8, ...); until then they say "coming soon" instead of made-up numbers.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;

    return Scaffold(
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: IconButton(
                        tooltip: l10n.homeSettings,
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => context.go(AppRoutes.settings),
                      ),
                    ),
                    MajlisWordmark(
                      title: l10n.appTitle,
                      tagline: l10n.appTagline,
                      size: 34,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.homeSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: majlis.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    MajlisButton(
                      label: l10n.homePlay,
                      icon: Icons.casino_outlined,
                      onPressed: () => context.go(AppRoutes.hub),
                    ),
                    const SizedBox(height: 12),
                    MajlisButton(
                      label: l10n.homeJoinWithCode,
                      icon: Icons.login,
                      style: MajlisButtonStyle.secondary,
                      onPressed: () => context.go(AppRoutes.joinRoom),
                    ),
                    const SizedBox(height: 24),
                    const _ProfileCard(),
                    const SizedBox(height: 24),
                    Text(
                      l10n.homeShortcuts,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _Shortcuts(
                      items: [
                        _Shortcut(Icons.storefront_outlined, l10n.homeShop),
                        _Shortcut(
                          Icons.collections_bookmark_outlined,
                          l10n.homeCollection,
                        ),
                        _Shortcut(
                          Icons.leaderboard_outlined,
                          l10n.homeRankings,
                        ),
                        _Shortcut(
                          Icons.workspace_premium_outlined,
                          l10n.homeVip,
                        ),
                        _Shortcut(
                          Icons.notifications_none,
                          l10n.homeNotifications,
                        ),
                        _Shortcut(
                          Icons.settings_outlined,
                          l10n.homeSettings,
                          route: AppRoutes.settings,
                        ),
                      ],
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

/// Who you are: avatar, name, level and permanent Player ID (friends add you
/// with it). Tap to open your profile.
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    if (account == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;

    Future<void> copyPlayerId() async {
      await Clipboard.setData(ClipboardData(text: '${account.playerId}'));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.homePlayerIdCopied)));
    }

    final card = MajlisCard(
      child: Row(
        children: [
          PlayerAvatar(avatar: account.avatar, radius: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      account.displayName,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      l10n.homeLevel(account.level),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: majlis.gold,
                      ),
                    ),
                    if (account.isGuest)
                      Text(
                        l10n.homeGuestTag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: majlis.textMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.homePlayerId(formatPlayerId(account.playerId)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: majlis.gold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.homeProfileHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: majlis.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.homeCopyPlayerId,
            icon: const Icon(Icons.copy_rounded),
            onPressed: copyPlayerId,
          ),
        ],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.go(AppRoutes.profile),
        child: card,
      ),
    );
  }
}

class _Shortcut {
  const _Shortcut(this.icon, this.label, {this.route});

  final IconData icon;
  final String label;

  /// Null while the feature isn't built yet.
  final String? route;
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.items});

  final List<_Shortcut> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        for (final item in items)
          Material(
            color: majlis.glassFill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: majlis.glassBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                final route = item.route;
                if (route != null) {
                  context.go(route);
                  return;
                }
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(content: Text(l10n.comingSoonNamed(item.label))),
                  );
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.icon,
                      color: item.route == null
                          ? majlis.textMuted
                          : majlis.gold,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                    if (item.route == null) ...[
                      const SizedBox(height: 4),
                      const SoonBadge(),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
