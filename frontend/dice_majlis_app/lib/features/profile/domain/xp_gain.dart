import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime_providers.dart';

/// XP the server added to this account (`xp_gained` on the `user/` channel),
/// with the new level progress. The app never works XP out itself.
class XpGain {
  const XpGain({
    required this.amount,
    required this.reason,
    required this.levelUp,
    required this.level,
    required this.xp,
    required this.levelXp,
    required this.nextLevelXp,
    this.roomCode,
  });

  final int amount;

  /// `game`, `reward` or `admin`.
  final String reason;

  /// The room of the game that gave it (games only).
  final String? roomCode;
  final bool levelUp;
  final int level;
  final int xp;
  final int levelXp;
  final int nextLevelXp;

  /// Null when the message isn't a usable XP update.
  static XpGain? fromJson(Map<String, dynamic> data) {
    final amount = data['amount'];
    final level = data['level'];
    final xp = data['xp'];
    if (amount is! int || level is! int || xp is! int) return null;
    return XpGain(
      amount: amount,
      reason: data['reason']?.toString() ?? '',
      roomCode: data['room_code']?.toString(),
      levelUp: data['level_up'] == true,
      level: level,
      xp: xp,
      levelXp: data['level_xp'] is int ? data['level_xp'] as int : 0,
      nextLevelXp: data['next_level_xp'] is int
          ? data['next_level_xp'] as int
          : 0,
    );
  }
}

/// XP from online games, by room code (the game-over dialog shows it).
class XpGainsController extends Notifier<Map<String, XpGain>> {
  @override
  Map<String, XpGain> build() {
    ref.watch(accountProvider.select((account) => account?.playerId));
    return const {};
  }

  void add(String roomCode, XpGain gain) => state = {...state, roomCode: gain};
}

final xpGainsProvider =
    NotifierProvider<XpGainsController, Map<String, XpGain>>(
      XpGainsController.new,
    );

/// Keeps the signed-in account's level live: listens for `xp_gained` and
/// updates the account (and [xpGainsProvider] for games). Watched by the app
/// root, so it runs whenever someone is signed in with a live connection.
final xpLiveProvider = Provider<void>((ref) {
  final playerId = ref.watch(
    accountProvider.select((account) => account?.playerId),
  );
  final realtime = ref.watch(realtimeClientProvider);
  if (realtime == null || playerId == null) return;
  final live = realtime.channel(RealtimeChannels.user(playerId)).listen((
    message,
  ) {
    if (message.type != 'xp_gained') return;
    final gain = XpGain.fromJson(message.data);
    if (gain == null) return;
    final account = ref.read(accountProvider);
    if (account != null && account.playerId == playerId) {
      ref
          .read(authControllerProvider.notifier)
          .accountChanged(
            account.copyWith(
              level: gain.level,
              xp: gain.xp,
              levelXp: gain.levelXp,
              nextLevelXp: gain.nextLevelXp,
            ),
          );
    }
    final room = gain.roomCode;
    if (room != null) ref.read(xpGainsProvider.notifier).add(room, gain);
  });
  ref.onDispose(live.cancel);
});
