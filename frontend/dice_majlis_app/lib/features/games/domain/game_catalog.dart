/// Which game, and which way to play it: the server's `game_type` and
/// `variant` (its game registry decides what exists).
class GameChoice {
  const GameChoice({this.gameType = ludo, this.variant = classic});

  /// What a room is when the server doesn't say (older servers).
  static const ludo = 'ludo';
  static const classic = 'classic';

  final String gameType;
  final String variant;

  @override
  bool operator ==(Object other) =>
      other is GameChoice &&
      other.gameType == gameType &&
      other.variant == variant;

  @override
  int get hashCode => Object.hash(gameType, variant);

  @override
  String toString() => '$gameType/$variant';
}

/// One way to play a game, as the server's catalog describes it.
class CatalogVariant {
  const CatalogVariant({
    required this.code,
    required this.minPlayers,
    required this.maxPlayers,
    required this.defaultPlayers,
    this.ranked = false,
  });

  factory CatalogVariant.fromJson(Map<String, dynamic> json) => CatalogVariant(
    code: json['code'].toString(),
    minPlayers: (json['min_players'] as num).toInt(),
    maxPlayers: (json['max_players'] as num).toInt(),
    defaultPlayers: (json['default_players'] as num).toInt(),
    ranked: json['ranked'] == true,
  );

  final String code;
  final int minPlayers;
  final int maxPlayers;
  final int defaultPlayers;
  final bool ranked;
}

/// A game the server can run online, with its variants.
class CatalogGame {
  const CatalogGame({
    required this.gameType,
    required this.defaultVariant,
    required this.variants,
  });

  factory CatalogGame.fromJson(Map<String, dynamic> json) => CatalogGame(
    gameType: json['game_type'].toString(),
    defaultVariant: json['default_variant'].toString(),
    variants: [
      for (final v in json['variants'] as List)
        CatalogVariant.fromJson(Map<String, dynamic>.from(v as Map)),
    ],
  );

  final String gameType;
  final String defaultVariant;
  final List<CatalogVariant> variants;
}

/// `GET /api/game/catalog/`: every game the server offers.
List<CatalogGame> parseCatalog(Map<String, dynamic> json) => [
  for (final g in json['games'] as List)
    CatalogGame.fromJson(Map<String, dynamic>.from(g as Map)),
];
