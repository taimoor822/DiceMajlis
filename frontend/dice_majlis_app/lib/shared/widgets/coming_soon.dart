import 'package:flutter/material.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/majlis_colors.dart';
import 'majlis_background.dart';
import 'majlis_card.dart';

/// Small "Soon" label for features that aren't built yet.
class SoonBadge extends StatelessWidget {
  const SoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: majlis.gold.withValues(alpha: 0.6)),
      ),
      child: Text(
        AppLocalizations.of(context).comingSoonBadge,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: majlis.gold,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A whole page for a section that isn't built yet: says so plainly, never
/// shows made-up content. [action] can point somewhere that does work.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    this.action,
  });

  final String title;
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(title)),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: MajlisCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 56, color: majlis.gold),
                      const SizedBox(height: 16),
                      Text(l10n.comingSoon, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: majlis.textMuted,
                        ),
                      ),
                      if (action != null) ...[
                        const SizedBox(height: 20),
                        action!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
