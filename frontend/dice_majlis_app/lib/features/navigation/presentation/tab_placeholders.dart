import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../shared/widgets/coming_soon.dart';
import '../../../shared/widgets/majlis_button.dart';

// The tabs whose features come in later phases. Each one is replaced by its
// real screen when built (Events: Phase 8, Battle: Phases 4/6, Chat and
// Social: Phase 5; see docs/planning.md).

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ComingSoonPage(
      title: l10n.eventsTitle,
      icon: Icons.celebration_outlined,
      message: l10n.eventsBody,
    );
  }
}

class BattleScreen extends StatelessWidget {
  const BattleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ComingSoonPage(
      title: l10n.battleTitle,
      icon: Icons.bolt_outlined,
      message: l10n.battleBody,
      action: MajlisButton(
        label: l10n.battleOpenHub,
        icon: Icons.casino_outlined,
        style: MajlisButtonStyle.secondary,
        onPressed: () => context.go(AppRoutes.hub),
      ),
    );
  }
}

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ComingSoonPage(
      title: l10n.chatTitle,
      icon: Icons.chat_bubble_outline,
      message: l10n.chatBody,
    );
  }
}

class SocialScreen extends StatelessWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ComingSoonPage(
      title: l10n.socialTitle,
      icon: Icons.people_outline,
      message: l10n.socialBody,
    );
  }
}
