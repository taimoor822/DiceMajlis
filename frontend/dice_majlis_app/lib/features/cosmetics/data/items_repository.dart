import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../domain/inventory.dart';

/// What the player owns and wears. Items are given by the server (rewards,
/// achievements, the team); the app can only choose what to wear. Tests swap in
/// a fake through [itemsRepositoryProvider].
abstract class ItemsRepository {
  Future<Inventory> inventory();

  /// Wear [item] in [slot]; null = back to the default.
  Future<Inventory> equip(String slot, String? item);
}

class ApiItemsRepository implements ItemsRepository {
  const ApiItemsRepository(this._api);

  final ApiService _api;

  @override
  Future<Inventory> inventory() async =>
      Inventory.fromJson(await _api.myItems());

  @override
  Future<Inventory> equip(String slot, String? item) async =>
      Inventory.fromJson(await _api.equipItem(slot, item));
}

final itemsRepositoryProvider = Provider<ItemsRepository>(
  (ref) => ApiItemsRepository(ref.watch(apiServiceProvider)),
);
