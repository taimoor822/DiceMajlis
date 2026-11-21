import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime_message.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../achievements/data/achievements_repository.dart';
import '../../achievements/domain/achievements.dart';
import 'xp_gain.dart';

/// Keeps the signed-in account live from its `user/` channel: XP and level
/// (`xp_gained`, also kept per game in [xpGainsProvider]) and what it wears
/// (`cosmetics_changed`, e.g. chosen on another phone), and achievements it
/// unlocks (`achievement_unlocked`, into [achievementUnlocksProvider]). Watched by the app root,
/// so it runs whenever someone is signed in with a live connection.
final accountLiveProvider = Provider<void>((ref) {
  final playerId = ref.watch(
    accountProvider.select((account) => account?.playerId),
  );
  final realtime = ref.watch(realtimeClientProvider);
  if (realtime == null || playerId == null) return;

  void update(RealtimeMessage message) {
    final account = ref.read(accountProvider);
    if (account == null || account.playerId != playerId) return;
    final auth = ref.read(authControllerProvider.notifier);
    switch (message.type) {
      case 'xp_gained':
        final gain = XpGain.fromJson(message.data);
        if (gain == null) return;
        auth.accountChanged(
          account.copyWith(
            level: gain.level,
            xp: gain.xp,
            levelXp: gain.levelXp,
            nextLevelXp: gain.nextLevelXp,
          ),
        );
        final room = gain.roomCode;
        if (room != null) ref.read(xpGainsProvider.notifier).add(room, gain);
      case 'achievement_unlocked':
        final unlocked = AchievementUnlocked.fromJson(message.data);
        if (unlocked != null) {
          ref.read(achievementUnlocksProvider.notifier).add(unlocked);
        }
      case 'cosmetics_changed':
        final cosmetics = message.data['cosmetics'];
        if (cosmetics is! Map) return;
        auth.accountChanged(
          account.copyWith(
            cosmetics: {
              for (final entry in cosmetics.entries)
                entry.key.toString(): entry.value?.toString(),
            },
          ),
        );
    }
  }

  final live = realtime.channel(RealtimeChannels.user(playerId)).listen(update);
  ref.onDispose(live.cancel);
});
