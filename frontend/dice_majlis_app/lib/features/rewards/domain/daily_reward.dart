import '../../wallet/domain/wallet_models.dart';

/// One day of the daily reward cycle and what it gives.
class DailyRewardDay {
  const DailyRewardDay({required this.day, this.gold = 0, this.diamond = 0});

  factory DailyRewardDay.fromJson(Map<String, dynamic> json) {
    int amount(Object? value) => value is num ? value.toInt() : 0;
    return DailyRewardDay(
      day: amount(json['day']),
      gold: amount(json['gold']),
      diamond: amount(json['diamond']),
    );
  }

  final int day;
  final int gold;
  final int diamond;
}

/// Today's daily reward, as the server sees it (its clock, not the phone's).
class DailyRewardStatus {
  const DailyRewardStatus({
    required this.day,
    required this.claimedToday,
    required this.days,
    required this.secondsUntilReset,
  });

  factory DailyRewardStatus.fromJson(Map<String, dynamic> json) =>
      DailyRewardStatus(
        day: (json['day'] as num?)?.toInt() ?? 1,
        claimedToday: json['claimed_today'] == true,
        days: [
          for (final day in json['days'] as List? ?? const [])
            DailyRewardDay.fromJson(Map<String, dynamic>.from(day as Map)),
        ],
        secondsUntilReset: (json['seconds_until_reset'] as num?)?.toInt() ?? 0,
      );

  /// Today's day in the cycle (the one claimed, or the one to claim).
  final int day;
  final bool claimedToday;
  final List<DailyRewardDay> days;

  /// Until the next reward-day starts.
  final int secondsUntilReset;

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
