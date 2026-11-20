import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/coming_soon.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../../shared/widgets/majlis_wordmark.dart';

/// First visit (or after signing out). "Play as guest" works today; email,
/// Google and Apple sign-in say "coming soon" until their plan steps.
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
    final later = [
      (Icons.mail_outline, l10n.welcomeEmail),
      (Icons.account_circle_outlined, l10n.welcomeGoogle),
      (Icons.phone_iphone, l10n.welcomeApple),
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
                          for (final (icon, label) in later)
                            ListTile(
                              leading: Icon(icon, color: majlis.textMuted),
                              title: Text(label),
                              trailing: const SoonBadge(),
                              onTap: () => _comingSoon(label),
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
      ),
    );
  }
}
