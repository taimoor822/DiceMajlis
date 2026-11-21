import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_service.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../domain/achievements.dart';

/// Achievements, read only: the server unlocks them from real progress.
/// Tests swap in a fake through [achievementsRepositoryProvider].
abstract class AchievementsRepository {
  Future<AchievementsOverview> myAchievements();
}

class ApiAchievementsRepository implements AchievementsRepository {
  const ApiAchievementsRepository(this._api);

  final ApiService _api;

  @override
  Future<AchievementsOverview> myAchievements() async =>
      AchievementsOverview.fromJson(await _api.myAchievements());
}

final achievementsRepositoryProvider = Provider<AchievementsRepository>(
  (ref) => ApiAchievementsRepository(ref.watch(apiServiceProvider)),
);

/// The signed-in player's achievements; reloads when progress changes them.
class AchievementsController extends AsyncNotifier<AchievementsOverview> {
  @override
  Future<AchievementsOverview> build() async {
    final playerId = ref.watch(
      accountProvider.select((account) => account?.playerId),
    );
    final realtime = ref.watch(realtimeClientProvider);
    if (realtime != null && playerId != null) {
      final live = realtime.channel(RealtimeChannels.user(playerId)).listen((
        message,
      ) {
        if (message.type == 'achievement_unlocked' ||
            message.type == 'stats_changed') {
          ref.invalidateSelf();
        }
      });
      ref.onDispose(live.cancel);
    }
    return ref.read(achievementsRepositoryProvider).myAchievements();
  }
}

final achievementsProvider =
    AsyncNotifierProvider<AchievementsController, AchievementsOverview>(
      AchievementsController.new,
    );

/// Achievements unlocked while the app is open, newest last (the app shows a
/// note for each, and the game-over dialog lists those of its game).
class AchievementUnlocksController extends Notifier<List<AchievementUnlocked>> {
  @override
  List<AchievementUnlocked> build() {
    ref.watch(accountProvider.select((account) => account?.playerId));
    return const [];
  }

  void add(AchievementUnlocked unlocked) => state = [...state, unlocked];
}

final achievementUnlocksProvider =
    NotifierProvider<AchievementUnlocksController, List<AchievementUnlocked>>(
      AchievementUnlocksController.new,
    );
