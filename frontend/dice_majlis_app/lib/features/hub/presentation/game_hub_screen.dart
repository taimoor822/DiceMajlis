import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/coming_soon.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';

/// Every game and mode. Today: Classic Ludo in a private room (with the
/// Majlis AI if you're alone). The rest is listed honestly as coming soon.
// TODO(1.10 game platform): modes come from the server's game registry.
class GameHubScreen extends StatelessWidget {
  const GameHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.hubTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  MajlisCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.casino, color: majlis.gold, size: 32),
                            const SizedBox(width: 12),
                            Text(
                              l10n.hubClassicTitle,
                              style: theme.textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.hubClassicBody,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: majlis.textMuted,
                          ),
                        ),
                        const SizedBox(height: 18),
                        MajlisButton(
                          label: l10n.hubCreateRoom,
                          icon: Icons.add_circle_outline,
                          onPressed: () => context.go(AppRoutes.createRoom),
                        ),
                        const SizedBox(height: 12),
                        MajlisButton(
                          label: l10n.hubJoinRoom,
                          icon: Icons.login,
                          style: MajlisButtonStyle.secondary,
                          onPressed: () => context.go(AppRoutes.joinRoom),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(l10n.hubMoreModes, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _SoonMode(
                    icon: Icons.phone_android,
                    title: l10n.hubLocalPlay,
                    body: l10n.hubLocalPlayBody,
                  ),
                  _SoonMode(
                    icon: Icons.groups_2_outlined,
                    title: l10n.hubTeamLudo,
                    body: l10n.hubTeamLudoBody,
                  ),
                  _SoonMode(
                    icon: Icons.emoji_events_outlined,
                    title: l10n.hubTournaments,
                    body: l10n.hubTournamentsBody,
                  ),
                  _SoonMode(
                    icon: Icons.extension_outlined,
                    title: l10n.hubMoreGames,
                    body: l10n.hubMoreGamesBody,
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

class _SoonMode extends StatelessWidget {
  const _SoonMode({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MajlisCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: majlis.textMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: majlis.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SoonBadge(),
          ],
        ),
      ),
    );
  }
}
