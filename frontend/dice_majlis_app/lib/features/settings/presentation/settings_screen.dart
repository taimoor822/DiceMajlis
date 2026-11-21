import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/account.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/social_sign_in.dart';
import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../profile/data/account_repository.dart';

/// Your account (save it, sign out) and device settings: the theme (saved on
/// this device).
// TODO(Phase 2): language, sound, notifications; change password.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const _AccountCard(),
                  const SizedBox(height: 16),
                  MajlisCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.settingsTheme,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 14),
                        SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text(l10n.settingsThemeDark),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text(l10n.settingsThemeLight),
                            ),
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text(l10n.settingsThemeSystem),
                            ),
                          ],
                          selected: {mode},
                          onSelectionChanged: (choice) => ref
                              .read(themeModeProvider.notifier)
                              .set(choice.single),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.settingsThemeHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.majlis.textMuted,
                          ),
                        ),
                      ],
                    ),
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

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final isGuest = ref.read(accountProvider)?.isGuest ?? false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsSignOutTitle),
        content: Text(
          isGuest ? l10n.settingsSignOutGuest : l10n.settingsSignOutBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The router takes the player to the welcome screen.
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    if (account == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;

    return MajlisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsAccount, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(account.displayName, style: theme.textTheme.bodyLarge),
          Text(
            l10n.homePlayerId(formatPlayerId(account.playerId)),
            style: theme.textTheme.bodyMedium?.copyWith(color: majlis.gold),
          ),
          if (account.email case final email?)
            Text(
              email,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: majlis.textMuted,
              ),
            ),
          if (account.isGuest) ...[
            Text(
              l10n.settingsGuestAccount,
              style: theme.textTheme.bodySmall?.copyWith(
                color: majlis.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.settingsGuestSaveHint, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            MajlisButton(
              label: l10n.saveAccountTitle,
              icon: Icons.verified_user_outlined,
              onPressed: () => context.push(AppRoutes.saveAccount),
            ),
          ],
          const _SignInMethods(),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: Text(l10n.settingsSignOut),
              onPressed: () => _signOut(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google / Apple on this account: linked ones (with Unlink) and the ones this
/// phone can add. A guest who links one is saved, with everything kept.
class _SignInMethods extends ConsumerStatefulWidget {
  const _SignInMethods();

  @override
  ConsumerState<_SignInMethods> createState() => _SignInMethodsState();
}

class _SignInMethodsState extends ConsumerState<_SignInMethods> {
  bool _busy = false;

  String _name(AppLocalizations l10n, SocialProvider provider) =>
      switch (provider) {
        SocialProvider.google => l10n.providerGoogle,
        SocialProvider.apple => l10n.providerApple,
      };

  Future<void> _run(Future<String> Function() action) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final done = await action();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
    } on SocialSignInCancelled {
      // Closed Google's / Apple's sheet.
    } on SocialSignInFailed {
      messenger.showSnackBar(SnackBar(content: Text(l10n.socialSignInFailed)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.apiErrorText(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _link(SocialProvider provider) async {
    final l10n = AppLocalizations.of(context);
    final credential = await ref
        .read(socialSignInProvider)
        .credential(provider);
    final account = await ref
        .read(accountRepositoryProvider)
        .linkSocial(provider, credential);
    ref.read(authControllerProvider.notifier).accountChanged(account);
    return l10n.linkDone(_name(l10n, provider));
  }

  Future<String> _unlink(SocialProvider provider) async {
    final l10n = AppLocalizations.of(context);
    final account = await ref
        .read(accountRepositoryProvider)
        .unlinkSocial(provider);
    ref.read(authControllerProvider.notifier).accountChanged(account);
    return l10n.unlinkDone(_name(l10n, provider));
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    if (account == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final majlis = context.majlis;
    final available =
        ref.watch(socialProvidersProvider).valueOrNull ??
        const <SocialProvider>[];
    final linked = [
      for (final key in account.linked) ?SocialProvider.fromKey(key),
    ];
    final canAdd = [
      for (final provider in available)
        if (!linked.contains(provider)) provider,
    ];
    if (linked.isEmpty && canAdd.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final provider in linked)
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: majlis.gold, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.linkedWith(_name(l10n, provider)))),
                TextButton(
                  onPressed: _busy ? null : () => _run(() => _unlink(provider)),
                  child: Text(l10n.unlinkButton),
                ),
              ],
            ),
          for (final provider in canAdd)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: Icon(
                  provider == SocialProvider.google
                      ? Icons.account_circle_outlined
                      : Icons.phone_iphone,
                ),
                label: Text(
                  account.isGuest
                      ? l10n.saveWith(_name(l10n, provider))
                      : l10n.linkButton(_name(l10n, provider)),
                ),
                onPressed: _busy ? null : () => _run(() => _link(provider)),
              ),
            ),
        ],
      ),
    );
  }
}
