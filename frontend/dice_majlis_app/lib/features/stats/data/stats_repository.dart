import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_service.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../domain/player_stats.dart';

/// Your statistics, read only: the server keeps them from finished games.
/// Tests swap in a fake through [statsRepositoryProvider].
abstract class StatsRepository {
  Future<StatsOverview> myStats();
}

class ApiStatsRepository implements StatsRepository {
  const ApiStatsRepository(this._api);

  final ApiService _api;

  @override
  Future<StatsOverview> myStats() async =>
      StatsOverview.fromJson(await _api.myStats());
}

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => ApiStatsRepository(ref.watch(apiServiceProvider)),
);

/// The signed-in player's statistics; reloads when a game updates them
/// (`stats_changed` on the `user/` channel).
class StatsController extends AsyncNotifier<StatsOverview> {
  @override
  Future<StatsOverview> build() async {
    final playerId = ref.watch(
      accountProvider.select((account) => account?.playerId),
    );
    final realtime = ref.watch(realtimeClientProvider);
    if (realtime != null && playerId != null) {
      final live = realtime.channel(RealtimeChannels.user(playerId)).listen((
        message,
      ) {
        if (message.type == 'stats_changed') ref.invalidateSelf();
      });
      ref.onDispose(live.cancel);
    }
    return ref.read(statsRepositoryProvider).myStats();
  }
}

final statsProvider = AsyncNotifierProvider<StatsController, StatsOverview>(
  StatsController.new,
);
