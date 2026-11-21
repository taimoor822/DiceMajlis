import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/social_sign_in.dart';
import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/coming_soon.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../../shared/widgets/majlis_wordmark.dart';

/// First visit (or after signing out): "Play as guest", email, Google or
/// Apple. Google and Apple show only when the server and this build are set up
/// for them (`socialProvidersProvider`); otherwise they say "coming soon".
///
/// Signing in needs no navigation here: the router moves a signed-in player
/// on to Home.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _loading = false;

  Future<void> _playAsGuest() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).signInAsGuest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.apiErrorText(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWith(SocialProvider provider) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signInWithProvider(provider);
    } on SocialSignInCancelled {
      // The player closed Google's / Apple's sheet: nothing to say.
    } on SocialSignInFailed {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.socialSignInFailed)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.apiErrorText(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _comingSoon(String feature) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.comingSoonNamed(feature))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final ready =
        ref.watch(socialProvidersProvider).valueOrNull ??
        const <SocialProvider>[];
    final social = [
      (
        SocialProvider.google,
        Icons.account_circle_outlined,
        l10n.welcomeGoogle,
      ),
      (SocialProvider.apple, Icons.phone_iphone, l10n.welcomeApple),
    ];

    return Scaffold(
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MajlisWordmark(
                      title: l10n.appTitle,
                      tagline: l10n.appTagline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.welcomeBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: majlis.textMuted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    MajlisButton(
                      label: l10n.welcomePlayAsGuest,
                      icon: Icons.person_outline,
                      loading: _loading,
                      onPressed: _loading ? null : _playAsGuest,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.welcomeGuestHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: majlis.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    MajlisCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.mail_outline,
                              color: majlis.gold,
                            ),
                            title: Text(l10n.welcomeEmail),
                            subtitle: Text(l10n.welcomeEmailSubtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _loading
                                ? null
                                : () => context.push(AppRoutes.welcomeEmail),
                          ),
                          for (final (provider, icon, label) in social)
                            if (ready.contains(provider))
                              ListTile(
                                leading: Icon(icon, color: majlis.gold),
                                title: Text(label),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _loading
                                    ? null
                                    : () => _signInWith(provider),
                              )
                            else
                              ListTile(
                                leading: Icon(icon, color: majlis.textMuted),
                                title: Text(label),
                                trailing: const SoonBadge(),
                                onTap: () => _comingSoon(label),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      icon: const Icon(Icons.phone_android),
                      label: Text(l10n.welcomePlayOffline),
                      onPressed: _loading
                          ? null
                          : () => context.push(AppRoutes.localPlay),
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
