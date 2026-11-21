/// One step of an achievement: reach [threshold] (and get [reward]).
class AchievementTierInfo {
  const AchievementTierInfo({
    required this.threshold,
    this.reward = const {},
    this.unlockedAt,
  });

  factory AchievementTierInfo.fromJson(Map<String, dynamic> json) =>
      AchievementTierInfo(
        threshold: json['threshold'] as int? ?? 0,
        reward: _bundle(json['reward']),
        unlockedAt: json['unlocked_at'] == null
            ? null
            : DateTime.tryParse(json['unlocked_at'] as String),
      );

  final int threshold;

  /// What it gives, by currency (`gold`, `diamond`).
  final Map<String, int> reward;
  final DateTime? unlockedAt;

  bool get unlocked => unlockedAt != null;
}

/// An achievement and how far the player is (from `GET /api/me/achievements/`).
class AchievementInfo {
  const AchievementInfo({
    required this.code,
    required this.name,
    required this.description,
    required this.icon,
    required this.rarity,
    required this.value,
    required this.tiers,
    this.nextThreshold,
    this.completed = false,
  });

  factory AchievementInfo.fromJson(Map<String, dynamic> json) =>
      AchievementInfo(
        code: json['code'] as String,
        name: json['name'] as String? ?? json['code'] as String,
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? 'trophy',
        rarity: json['rarity'] as String? ?? 'common',
        value: json['value'] as int? ?? 0,
        tiers: [
          for (final tier in json['tiers'] as List? ?? const [])
            AchievementTierInfo.fromJson(
              Map<String, dynamic>.from(tier as Map),
            ),
        ],
        nextThreshold: json['next_threshold'] as int?,
        completed: json['completed'] == true,
      );

  final String code;
  final String name;
  final String description;
  final String icon;
  final String rarity;

  /// The metric's value now (games, wins, level ...).
  final int value;
  final List<AchievementTierInfo> tiers;
  final int? nextThreshold;
  final bool completed;

  int get unlockedTiers => tiers.where((tier) => tier.unlocked).length;

  /// Towards the next tier, 0 to 1.
  double get progress {
    final next = nextThreshold;
    if (next == null || next <= 0) return 1;
    return (value / next).clamp(0.0, 1.0);
  }
}

class AchievementsOverview {
  const AchievementsOverview({
    this.achievements = const [],
    this.unlockedTiers = 0,
    this.totalTiers = 0,
    this.hiddenLeft = 0,
  });

  factory AchievementsOverview.fromJson(Map<String, dynamic> json) =>
      AchievementsOverview(
        achievements: [
          for (final a in json['achievements'] as List? ?? const [])
            AchievementInfo.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        unlockedTiers: json['unlocked_tiers'] as int? ?? 0,
        totalTiers: json['total_tiers'] as int? ?? 0,
        hiddenLeft: json['hidden_left'] as int? ?? 0,
      );

  final List<AchievementInfo> achievements;
  final int unlockedTiers;
  final int totalTiers;

  /// Hidden achievements not found yet.
  final int hiddenLeft;
}

/// An achievement the server just unlocked (`achievement_unlocked` push).
class AchievementUnlocked {
  const AchievementUnlocked({
    required this.code,
    required this.name,
    required this.tier,
    this.reward = const {},
    this.roomCode,
  });

  static AchievementUnlocked? fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    if (code is! String) return null;
    return AchievementUnlocked(
      code: code,
      name: json['name'] as String? ?? code,
      tier: json['tier'] as int? ?? 1,
      reward: _bundle(json['reward']),
      roomCode: json['room_code'] as String?,
    );
  }

  final String code;
  final String name;
  final int tier;
  final Map<String, int> reward;

  /// The room of the game that unlocked it, if a game did.
  final String? roomCode;
}

Map<String, int> _bundle(Object? value) => value is Map
    ? {
        for (final entry in value.entries)
          if (entry.value is int) entry.key.toString(): entry.value as int,
      }
    : const {};
