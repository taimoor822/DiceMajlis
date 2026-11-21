import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_service.dart';
import '../../../core/realtime/realtime_message.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../domain/wallet_models.dart';

/// The wallet, read only: balances change on the server (rewards, gifts,
/// purchases), never from the app. Tests swap in a fake through
/// [walletRepositoryProvider].
abstract class WalletRepository {
  Future<Balances> balances();
  Future<WalletPage> history({String? before});
}

class ApiWalletRepository implements WalletRepository {
  const ApiWalletRepository(this._api);

  final ApiService _api;

  @override
  Future<Balances> balances() async {
    final json = await _api.wallet();
    return Balances.fromJson(
      Map<String, dynamic>.from(json['balances'] as Map),
    );
  }

  @override
  Future<WalletPage> history({String? before}) async =>
      WalletPage.fromJson(await _api.walletTransactions(before: before));
}

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => ApiWalletRepository(ref.watch(apiServiceProvider)),
);

/// The signed-in player's balances. Loaded from the server; replaced straight
/// away when another answer brings new balances (e.g. a claimed reward), and
/// kept live by the `user/<player id>` socket channel (`balances_changed`), so
/// a reward claimed on another phone shows here too.
class BalancesController extends AsyncNotifier<Balances> {
  /// The newest balances the socket sent while the server load was running.
  Balances? _pushedWhileLoading;
  bool _loading = false;

  @override
  Future<Balances> build() async {
    // A different player (or none), or a new connection: start again.
    final playerId = ref.watch(
      accountProvider.select((account) => account?.playerId),
    );
    final realtime = ref.watch(realtimeClientProvider);
    _pushedWhileLoading = null;
    if (realtime != null && playerId != null) {
      final live = realtime
          .channel(RealtimeChannels.user(playerId))
          .listen(_onUserEvent);
      ref.onDispose(live.cancel);
    }
    _loading = true;
    try {
      final loaded = await ref.read(walletRepositoryProvider).balances();
      // The socket may have answered first, with newer balances.
      return _pushedWhileLoading ?? loaded;
    } finally {
      _loading = false;
    }
  }

  void _onUserEvent(RealtimeMessage message) {
    final balances = message.data['balances'];
    if (message.type != 'balances_changed' || balances is! Map) return;
    final pushed = Balances.fromJson(Map<String, dynamic>.from(balances));
    if (_loading) _pushedWhileLoading = pushed;
    set(pushed);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(walletRepositoryProvider).balances(),
    );
  }

  /// The server sent the new balances with another answer.
  void set(Balances balances) => state = AsyncData(balances);
}

final balancesProvider = AsyncNotifierProvider<BalancesController, Balances>(
  BalancesController.new,
);
