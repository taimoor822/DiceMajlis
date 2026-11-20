import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_service.dart';
import '../../wallet/data/wallet_repository.dart';
import '../domain/daily_reward.dart';

/// Daily rewards. The app only asks to claim; the server decides what is given.
abstract class RewardsRepository {
  Future<DailyRewardStatus> dailyStatus();
  Future<DailyClaimResult> claimDaily();
}

class ApiRewardsRepository implements RewardsRepository {
  const ApiRewardsRepository(this._api);

  final ApiService _api;

  @override
  Future<DailyRewardStatus> dailyStatus() async =>
      DailyRewardStatus.fromJson(await _api.dailyReward());

  @override
  Future<DailyClaimResult> claimDaily() async =>
      DailyClaimResult.fromJson(await _api.claimDailyReward());
}

final rewardsRepositoryProvider = Provider<RewardsRepository>(
  (ref) => ApiRewardsRepository(ref.watch(apiServiceProvider)),
);

class DailyRewardController extends AsyncNotifier<DailyRewardStatus> {
  @override
  Future<DailyRewardStatus> build() {
    ref.watch(accountProvider.select((account) => account?.playerId));
    return ref.read(rewardsRepositoryProvider).dailyStatus();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(rewardsRepositoryProvider).dailyStatus(),
    );
  }

  /// Claims today's reward and updates the balances. Throws on failure (the
  /// status is reloaded, e.g. when another phone claimed first).
  Future<DailyRewardDay> claim() async {
    try {
      final result = await ref.read(rewardsRepositoryProvider).claimDaily();
      state = AsyncData(result.status);
      ref.read(balancesProvider.notifier).set(result.balances);
      return result.claimed;
    } catch (_) {
      await refresh();
      rethrow;
    }
  }
}

final dailyRewardProvider =
    AsyncNotifierProvider<DailyRewardController, DailyRewardStatus>(
      DailyRewardController.new,
    );
