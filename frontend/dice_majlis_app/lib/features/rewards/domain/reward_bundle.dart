/// An item inside a reward (a cosmetic today).
class RewardItem {
  const RewardItem({
    required this.code,
    required this.name,
    this.asset = '',
    this.slot,
    this.rarity = 'common',
    this.quantity = 1,
    this.days,
  });

  factory RewardItem.fromJson(Map<String, dynamic> json) => RewardItem(
    code: json['code'] as String? ?? '',
    name: json['name'] as String? ?? json['code'] as String? ?? '',
    asset: json['asset'] as String? ?? '',
    slot: json['slot'] as String?,
    rarity: json['rarity'] as String? ?? 'common',
    quantity: json['quantity'] as int? ?? 1,
    days: json['days'] as int?,
  );

  final String code;
  final String name;
  final String asset;
  final String? slot;
  final String rarity;
  final int quantity;

  /// Lent for this many days; null = kept for good.
  final int? days;
}

/// What a reward gives, as the server describes it: currencies, XP, items.
class RewardBundle {
  const RewardBundle({
    this.gold = 0,
    this.diamond = 0,
    this.xp = 0,
    this.items = const [],
  });

  factory RewardBundle.fromJson(Object? json) {
    if (json is! Map) return const RewardBundle();
    int amount(Object? value) => value is num ? value.toInt() : 0;
    return RewardBundle(
      gold: amount(json['gold']),
      diamond: amount(json['diamond']),
      xp: amount(json['xp']),
      items: [
        for (final item in json['items'] as List? ?? const [])
          RewardItem.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  final int gold;
  final int diamond;
  final int xp;
  final List<RewardItem> items;

  bool get isEmpty => gold == 0 && diamond == 0 && xp == 0 && items.isEmpty;
}

/// One reward you got (`GET /api/rewards/history/`).
class RewardHistoryEntry {
  const RewardHistoryEntry({
    required this.id,
    required this.kind,
    required this.reward,
    required this.createdAt,
    this.day,
    this.achievement,
    this.threshold,
  });

  factory RewardHistoryEntry.fromJson(Map<String, dynamic> json) =>
      RewardHistoryEntry(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? '',
        reward: RewardBundle.fromJson(json['reward']),
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        day: json['day'] as int?,
        achievement: json['achievement'] as String?,
        threshold: json['threshold'] as int?,
      );

  final String id;

  /// `daily_login`, `achievement`, ...
  final String kind;
  final RewardBundle reward;
  final DateTime createdAt;

  /// Daily rewards: the day in the cycle.
  final int? day;

  /// Achievements: its name and the tier reached.
  final String? achievement;
  final int? threshold;
}

class RewardHistoryPage {
  const RewardHistoryPage({required this.entries, this.next});

  factory RewardHistoryPage.fromJson(Map<String, dynamic> json) =>
      RewardHistoryPage(
        entries: [
          for (final entry in json['claims'] as List? ?? const [])
            RewardHistoryEntry.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
        ],
        next: json['next'] as String?,
      );

  final List<RewardHistoryEntry> entries;

  /// Pass as `before` for the next page; null = no more.
  final String? next;
}
