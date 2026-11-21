import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';

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
