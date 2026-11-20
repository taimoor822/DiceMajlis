import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_service.dart';
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
/// away when another answer brings new balances (e.g. a claimed reward).
class BalancesController extends AsyncNotifier<Balances> {
  @override
  Future<Balances> build() {
    // A different player (or none): start again.
    ref.watch(accountProvider.select((account) => account?.playerId));
    return ref.read(walletRepositoryProvider).balances();
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
