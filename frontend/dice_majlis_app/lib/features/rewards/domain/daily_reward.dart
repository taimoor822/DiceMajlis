import '../../wallet/domain/wallet_models.dart';
import 'reward_bundle.dart';

/// One day of the daily reward cycle and what it gives.
class DailyRewardDay {
  const DailyRewardDay({
    required this.day,
    this.gold = 0,
    this.diamond = 0,
    this.xp = 0,
    this.items = const [],
  });

  factory DailyRewardDay.fromJson(Map<String, dynamic> json) {
    int amount(Object? value) => value is num ? value.toInt() : 0;
    final bundle = RewardBundle.fromJson(json);
    return DailyRewardDay(
      day: amount(json['day']),
      gold: bundle.gold,
      diamond: bundle.diamond,
      xp: bundle.xp,
      items: bundle.items,
    );
  }

  final int day;
  final int gold;
  final int diamond;
  final int xp;
  final List<RewardItem> items;

  RewardBundle get bundle =>
      RewardBundle(gold: gold, diamond: diamond, xp: xp, items: items);
}

/// Today's daily reward, as the server sees it (its clock, not the phone's).
class DailyRewardStatus {
  DailyRewardStatus({
    required this.day,
    required this.claimedToday,
    required this.days,
    required this.secondsUntilReset,
    int? nextDay,
    this.available = true,
    this.restartsOnMiss = true,
  }) : nextDay = nextDay ?? (days.isEmpty ? 1 : day % days.length + 1);

  factory DailyRewardStatus.fromJson(Map<String, dynamic> json) =>
      DailyRewardStatus(
        day: (json['day'] as num?)?.toInt() ?? 1,
        claimedToday: json['claimed_today'] == true,
        days: [
          for (final day in json['days'] as List? ?? const [])
            DailyRewardDay.fromJson(Map<String, dynamic>.from(day as Map)),
        ],
        secondsUntilReset: (json['seconds_until_reset'] as num?)?.toInt() ?? 0,
        nextDay: (json['next_day'] as num?)?.toInt(),
        available: json['available'] != false,
        restartsOnMiss: json['on_miss'] != 'continue',
      );

  /// Today's day in the cycle (the one claimed, or the one to claim).
  final int day;
  final bool claimedToday;
  final List<DailyRewardDay> days;

  /// Until the next reward-day starts.
  final int secondsUntilReset;

  /// Tomorrow's day if the streak goes on (the server's cycle settings).
  final int nextDay;

  /// False when the team has no daily reward set up.
  final bool available;

  /// Missing a day starts the cycle again (or else carries on).
  final bool restartsOnMiss;

  DailyRewardDay? get today {
    for (final entry in days) {
      if (entry.day == day) return entry;
    }
    return null;
  }
}

/// What a claim gave, plus the new balances and status.
class DailyClaimResult {
  const DailyClaimResult({
    required this.claimed,
    required this.balances,
    required this.status,
  });

  factory DailyClaimResult.fromJson(Map<String, dynamic> json) =>
      DailyClaimResult(
        claimed: DailyRewardDay.fromJson(
          Map<String, dynamic>.from(json['claimed'] as Map),
        ),
        balances: Balances.fromJson(
          Map<String, dynamic>.from(json['balances'] as Map),
        ),
        status: DailyRewardStatus.fromJson(
          Map<String, dynamic>.from(json['daily'] as Map),
        ),
      );

  final DailyRewardDay claimed;
  final Balances balances;
  final DailyRewardStatus status;
}
