/// Totals for one game type, or for all of them (from `GET /api/me/stats/`).
/// The server counts real online games against people only.
class StatsSummary {
  const StatsSummary({
    this.gamesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.forfeits = 0,
    this.winRate = 0,
    this.winStreak = 0,
    this.bestWinStreak = 0,
  });

  factory StatsSummary.fromJson(Map<String, dynamic> json) => StatsSummary(
    gamesPlayed: json['games_played'] as int? ?? 0,
    wins: json['wins'] as int? ?? 0,
    losses: json['losses'] as int? ?? 0,
    forfeits: json['forfeits'] as int? ?? 0,
    winRate: json['win_rate'] as int? ?? 0,
    winStreak: json['win_streak'] as int? ?? 0,
    bestWinStreak: json['best_win_streak'] as int? ?? 0,
  );

  final int gamesPlayed;
  final int wins;
  final int losses;
  final int forfeits;

  /// Whole percent, worked out by the server.
  final int winRate;
  final int winStreak;
  final int bestWinStreak;
}

/// One finished game, newest first.
class GameResultEntry {
  const GameResultEntry({
    required this.gameType,
    required this.variant,
    required this.place,
    required this.playerCount,
    required this.won,
    required this.forfeited,
    required this.finishedAt,
  });

  factory GameResultEntry.fromJson(Map<String, dynamic> json) =>
      GameResultEntry(
        gameType: json['game_type'] as String? ?? '',
        variant: json['variant'] as String? ?? '',
        place: json['place'] as int? ?? 0,
        playerCount: json['player_count'] as int? ?? 0,
        won: json['won'] == true,
        forfeited: json['forfeited'] == true,
        finishedAt:
            DateTime.tryParse(json['finished_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String gameType;
  final String variant;
  final int place;
  final int playerCount;
  final bool won;
  final bool forfeited;
  final DateTime finishedAt;
}

class StatsOverview {
  const StatsOverview({
    this.total = const StatsSummary(),
    this.gameTypes = const {},
    this.recent = const [],
  });

  factory StatsOverview.fromJson(Map<String, dynamic> json) => StatsOverview(
    total: StatsSummary.fromJson(
      Map<String, dynamic>.from(json['total'] as Map? ?? const {}),
    ),
    gameTypes: {
      for (final entry in (json['game_types'] as Map? ?? const {}).entries)
        entry.key.toString(): StatsSummary.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        ),
    },
    recent: [
      for (final result in json['recent'] as List? ?? const [])
        GameResultEntry.fromJson(Map<String, dynamic>.from(result as Map)),
    ],
  );

  final StatsSummary total;
  final Map<String, StatsSummary> gameTypes;
  final List<GameResultEntry> recent;
}
