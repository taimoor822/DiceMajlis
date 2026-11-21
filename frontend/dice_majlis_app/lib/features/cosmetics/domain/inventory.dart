/// One item the player owns (from `GET /api/me/items/`).
class OwnedItem {
  const OwnedItem({
    required this.code,
    required this.type,
    required this.name,
    required this.rarity,
    required this.asset,
    this.slot,
    this.description = '',
    this.quantity = 1,
    this.expiresAt,
    this.starter = false,
  });

  factory OwnedItem.fromJson(Map<String, dynamic> json) => OwnedItem(
    code: json['code'] as String,
    type: json['type'] as String? ?? 'cosmetic',
    slot: json['slot'] as String?,
    name: json['name'] as String? ?? json['code'] as String,
    description: json['description'] as String? ?? '',
    rarity: json['rarity'] as String? ?? 'common',
    asset: json['asset'] as String? ?? '',
    quantity: json['quantity'] as int? ?? 1,
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.tryParse(json['expires_at'] as String),
    starter: json['starter'] == true,
  );

  final String code;
  final String type;

  /// Where a cosmetic is worn (`dice`, `board`, `frame`).
  final String? slot;
  final String name;
  final String description;
  final String rarity;
  final String asset;
  final int quantity;

  /// Null: never expires.
  final DateTime? expiresAt;

  /// Owned by everyone from the start.
  final bool starter;
}

/// What the player owns and wears.
class Inventory {
  const Inventory({
    this.items = const [],
    this.equipped = const {},
    this.cosmetics = const {},
  });

  factory Inventory.fromJson(Map<String, dynamic> json) => Inventory(
    items: [
      for (final item in json['items'] as List? ?? const [])
        OwnedItem.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    equipped: _slots(json['equipped']),
    cosmetics: _slots(json['cosmetics']),
  );

  final List<OwnedItem> items;

  /// Item code worn per slot (null = nothing).
  final Map<String, String?> equipped;

  /// Asset key worn per slot, as the app draws it.
  final Map<String, String?> cosmetics;

  List<OwnedItem> forSlot(String slot) =>
      items.where((item) => item.slot == slot).toList();

  static Map<String, String?> _slots(Object? value) => value is Map
      ? {
          for (final entry in value.entries)
            entry.key.toString(): entry.value?.toString(),
        }
      : const {};
}

/// The slots the Customise screen shows, in order.
abstract final class CosmeticSlots {
  static const dice = 'dice';
  static const board = 'board';
  static const frame = 'frame';
  static const all = [dice, board, frame];

  /// Slots that may be empty.
  static const optional = {frame};
}
