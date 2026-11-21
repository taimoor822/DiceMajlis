import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/coming_soon.dart';
import '../../../shared/widgets/majlis_card.dart';

/// Pictures for privilege icon keys; unknown keys show a star.
const privilegeIcons = <String, IconData>{
  'bolt': Icons.bolt,
  'trending_up': Icons.trending_up,
  'diamond': Icons.diamond_outlined,
  'frame': Icons.filter_frames_outlined,
  'crown': Icons.workspace_premium,
  'visibility': Icons.visibility_outlined,
  'visibility_off': Icons.visibility_off_outlined,
  'mic': Icons.mic_none,
  'chat': Icons.chat_bubble_outline,
  'door': Icons.meeting_room_outlined,
  'gift': Icons.card_giftcard,
  'palette': Icons.palette_outlined,
};

/// The privileges your account has (shown only when it has some). Ones the app
/// doesn't act on yet say "coming soon".
class PrivilegesCard extends ConsumerWidget {
  const PrivilegesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privileges = ref.watch(entitlementsProvider).value?.privileges;
    if (privileges == null || privileges.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MajlisCard(
        key: const Key('privileges-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.privilegesTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in privileges)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  privilegeIcons[p.icon] ?? Icons.star_outline,
                  color: majlis.gold,
                ),
                title: Text(
                  p.value != null && p.valueType != 'flag'
                      ? l10n.privilegeWithValue(p.name, p.value!)
                      : p.name,
                ),
                subtitle: Text(p.description),
                trailing: p.built ? null : const SoonBadge(),
              ),
          ],
        ),
      ),
    );
  }
}
