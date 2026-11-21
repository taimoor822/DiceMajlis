import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/cosmetic_looks.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../../shared/widgets/player_avatar.dart';
import '../../ludo/presentation/widgets/dice_widget.dart';
import '../domain/inventory.dart';
import '../domain/inventory_controller.dart';

/// Choose what you wear: dice, board and profile frame, from the items you
/// own. The server checks every choice; everyone at your table sees your dice.
class CustomiseScreen extends ConsumerStatefulWidget {
  const CustomiseScreen({super.key});

  @override
  ConsumerState<CustomiseScreen> createState() => _CustomiseScreenState();
}

class _CustomiseScreenState extends ConsumerState<CustomiseScreen> {
  /// The slot being saved (its choices wait meanwhile).
  String? _saving;

  Future<void> _equip(String slot, String? code) async {
    if (_saving != null) return;
    setState(() => _saving = slot);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(inventoryProvider.notifier).equip(slot, code);
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.apiErrorText(e))));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inventory = ref.watch(inventoryProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.customiseTitle)),
      body: MajlisBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: inventory.when(
                data: (inventory) => RefreshIndicator(
                  onRefresh: () => ref.refresh(inventoryProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      for (final slot in CosmeticSlots.all) ...[
                        _SlotCard(
                          slot: slot,
                          items: inventory.forSlot(slot),
                          equipped: inventory.equipped[slot],
                          saving: _saving == slot,
                          enabled: _saving == null,
                          onChoose: (code) => _equip(slot, code),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        l10n.customiseMoreSoon,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.majlis.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: MajlisCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.apiErrorText(error)),
                          TextButton(
                            onPressed: () => ref.invalidate(inventoryProvider),
                            child: Text(l10n.commonRetry),
                          ),
                        ],
                      ),
                    ),
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

class _SlotCard extends ConsumerWidget {
  const _SlotCard({
    required this.slot,
    required this.items,
    required this.equipped,
    required this.saving,
    required this.enabled,
    required this.onChoose,
  });

  final String slot;
  final List<OwnedItem> items;
  final String? equipped;
  final bool saving;
  final bool enabled;
  final ValueChanged<String?> onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = switch (slot) {
      CosmeticSlots.dice => l10n.customiseDice,
      CosmeticSlots.board => l10n.customiseBoard,
      _ => l10n.customiseFrame,
    };
    return MajlisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (saving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (CosmeticSlots.optional.contains(slot))
                _Choice(
                  key: ValueKey('choice-$slot-none'),
                  name: l10n.customiseNone,
                  selected: equipped == null,
                  onTap: enabled ? () => onChoose(null) : null,
                  preview: _Preview(slot: slot, asset: null),
                ),
              for (final item in items)
                _Choice(
                  key: ValueKey('choice-${item.code}'),
                  name: item.name,
                  rarity: item.rarity,
                  expiresAt: item.expiresAt,
                  selected: equipped == item.code,
                  onTap: enabled && equipped != item.code
                      ? () => onChoose(item.code)
                      : null,
                  preview: _Preview(slot: slot, asset: item.asset),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small picture of the item, drawn the way the game draws it.
class _Preview extends ConsumerWidget {
  const _Preview({required this.slot, required this.asset});

  final String slot;
  final String? asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final majlis = context.majlis;
    switch (slot) {
      case CosmeticSlots.dice:
        return IgnorePointer(
          child: FittedBox(child: DiceWidget(value: 6, skin: asset)),
        );
      case CosmeticSlots.board:
        final look = CosmeticLooks.board(asset);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: look == null
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: look.rim,
                  ),
            border: Border.all(
              color: look?.trim ?? majlis.glassBorder,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(7),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: majlis.backgroundBottom,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.grid_view_rounded, color: majlis.gold),
          ),
        );
      default:
        final avatar = ref.watch(
          accountProvider.select((account) => account?.avatar),
        );
        return Center(
          child: PlayerAvatar(avatar: avatar, radius: 20, frame: asset),
        );
    }
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
    required this.preview,
    this.rarity,
    this.expiresAt,
  });

  final String name;
  final String? rarity;
  final DateTime? expiresAt;
  final bool selected;
  final VoidCallback? onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ends = expiresAt;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 100,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: majlis.glassFill,
            border: Border.all(
              color: selected ? majlis.gold : majlis.glassBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: 56, width: 56, child: preview),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
              if (rarity != null)
                Text(
                  l10n.itemRarity(rarity!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: CosmeticLooks.rarity(rarity!, majlis),
                  ),
                ),
              if (ends != null)
                Text(
                  l10n.itemExpires(ends.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: majlis.warning,
                  ),
                ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: majlis.gold,
                  semanticLabel: l10n.customiseWearing,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
