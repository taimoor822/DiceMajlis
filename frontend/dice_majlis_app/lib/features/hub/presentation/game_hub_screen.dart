import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/coming_soon.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../games/data/game_catalog_repository.dart';
import '../../games/domain/game_catalog.dart';
import '../../games/game_registry.dart';

/// Every game and mode. Online games come from the server's game registry
/// (the catalog) and show when this app has a module for them; offline games
/// on this phone come from the app's modules. The rest is listed honestly as
/// coming soon.
class GameHubScreen extends ConsumerWidget {
  const GameHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final modules = ref.watch(gameModulesProvider);
    final catalog = ref.watch(gameCatalogProvider);

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
                  ...catalog.when(
                    data: (games) => [
                      for (final game in games)
                        if (modules[game.gameType] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _OnlineGameCard(
                              key: ValueKey('hub-game-${game.gameType}'),
                              module: modules[game.gameType]!,
                              game: game,
                            ),
                          ),
                      if (games.any((g) => modules[g.gameType] == null))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: MajlisCard(
                            child: Row(
                              children: [
                                Icon(Icons.system_update, color: majlis.gold),
                                const SizedBox(width: 12),
                                Expanded(child: Text(l10n.hubUpdateForGames)),
                              ],
                            ),
                          ),
                        ),
                    ],
                    loading: () => const [
                      Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: MajlisCard(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      ),
                    ],
                    error: (error, _) => [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: MajlisCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.hubCatalogFailed,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.apiErrorText(error),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: majlis.textMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () =>
                                    ref.invalidate(gameCatalogProvider),
                                icon: const Icon(Icons.refresh),
                                label: Text(l10n.commonRetry),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  for (final module in modules.values)
                    if (module.offlineRoute != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: MajlisCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.phone_android,
                                    color: majlis.gold,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    l10n.hubLocalPlay,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.hubLocalPlayBody,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: majlis.textMuted,
                                ),
                              ),
                              const SizedBox(height: 14),
                              MajlisButton(
                                label: l10n.hubLocalPlayStart,
                                icon: Icons.play_arrow_rounded,
                                style: MajlisButtonStyle.secondary,
                                onPressed: () =>
                                    context.push(module.offlineRoute!),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 12),
                  Text(l10n.hubMoreModes, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
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

/// One online game from the catalog: pick a variant (when there are several),
/// then create or join a room.
class _OnlineGameCard extends StatefulWidget {
  const _OnlineGameCard({super.key, required this.module, required this.game});

  final GameModule module;
  final CatalogGame game;

  @override
  State<_OnlineGameCard> createState() => _OnlineGameCardState();
}

class _OnlineGameCardState extends State<_OnlineGameCard> {
  late String _variant = widget.game.defaultVariant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final module = widget.module;
    final variants = widget.game.variants;

    return MajlisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(module.icon, color: majlis.gold, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  gameTitle(l10n, module, _variant),
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            module.description(l10n),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: majlis.textMuted,
            ),
          ),
          if (variants.length > 1) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final variant in variants)
                  ChoiceChip(
                    label: Text(module.variantName(l10n, variant.code)),
                    selected: variant.code == _variant,
                    onSelected: (_) => setState(() => _variant = variant.code),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          MajlisButton(
            label: l10n.hubCreateRoom,
            icon: Icons.add_circle_outline,
            onPressed: () =>
                context.go(AppRoutes.createRoomFor(module.gameType, _variant)),
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
