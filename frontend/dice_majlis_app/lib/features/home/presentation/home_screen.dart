import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_wordmark.dart';

// TODO(1.5 navigation): becomes the Home tab with Events, Game Hub,
// Battle, Chat and Social.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MajlisWordmark(
                      title: l10n.appTitle,
                      tagline: l10n.appTagline,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.homeSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: context.majlis.textMuted,
                      ),
                    ),
                    const SizedBox(height: 48),
                    MajlisButton(
                      label: l10n.homeCreateRoom,
                      icon: Icons.add_circle_outline,
                      onPressed: () => context.push(AppRoutes.createRoom),
                    ),
                    const SizedBox(height: 16),
                    MajlisButton(
                      label: l10n.homeJoinRoom,
                      icon: Icons.login,
                      style: MajlisButtonStyle.secondary,
                      onPressed: () => context.push(AppRoutes.joinRoom),
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
