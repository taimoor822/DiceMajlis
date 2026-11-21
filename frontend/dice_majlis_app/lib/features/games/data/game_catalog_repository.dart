import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../domain/game_catalog.dart';

/// The games the server can run. Tests swap in a fake through
/// [gameCatalogRepositoryProvider].
abstract class GameCatalogRepository {
  Future<List<CatalogGame>> catalog();
}

class ApiGameCatalogRepository implements GameCatalogRepository {
  const ApiGameCatalogRepository(this._api);

  final ApiService _api;

  @override
  Future<List<CatalogGame>> catalog() async =>
      parseCatalog(await _api.gameCatalog());
}

final gameCatalogRepositoryProvider = Provider<GameCatalogRepository>(
  (ref) => ApiGameCatalogRepository(ref.watch(apiServiceProvider)),
);

/// Loaded when Game Hub opens; `ref.invalidate` to try again.
final gameCatalogProvider = FutureProvider.autoDispose<List<CatalogGame>>(
  (ref) => ref.watch(gameCatalogRepositoryProvider).catalog(),
);
