import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../data/items_repository.dart';
import 'inventory.dart';

/// The signed-in player's items. Reloads when the server says they changed
/// (`inventory_changed` on the `user/` channel, e.g. an item given by a reward).
class InventoryController extends AsyncNotifier<Inventory> {
  @override
  Future<Inventory> build() async {
    final playerId = ref.watch(
      accountProvider.select((account) => account?.playerId),
    );
    final realtime = ref.watch(realtimeClientProvider);
    if (realtime != null && playerId != null) {
      final live = realtime.channel(RealtimeChannels.user(playerId)).listen((
        message,
      ) {
        if (message.type == 'inventory_changed') ref.invalidateSelf();
      });
      ref.onDispose(live.cancel);
    }
    return ref.read(itemsRepositoryProvider).inventory();
  }

  /// Wear [item] in [slot] (null = the default). Throws the server's refusal.
  Future<void> equip(String slot, String? item) async {
    final inventory = await ref.read(itemsRepositoryProvider).equip(slot, item);
    state = AsyncData(inventory);
    final account = ref.read(accountProvider);
    if (account != null) {
      ref
          .read(authControllerProvider.notifier)
          .accountChanged(account.copyWith(cosmetics: inventory.cosmetics));
    }
  }
}

final inventoryProvider = AsyncNotifierProvider<InventoryController, Inventory>(
  InventoryController.new,
);
