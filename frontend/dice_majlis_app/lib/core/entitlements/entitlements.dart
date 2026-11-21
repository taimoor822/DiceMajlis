import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../network/api_service.dart';
import '../realtime/realtime_providers.dart';

/// A privilege the account has, and how to show it (from the server's catalog,
/// so new ones need no app update to be listed).
class PrivilegeInfo {
  const PrivilegeInfo({
    required this.code,
    required this.name,
    required this.description,
    required this.icon,
    required this.valueType,
    required this.value,
    required this.built,
  });

  factory PrivilegeInfo.fromJson(Map<String, dynamic> json) => PrivilegeInfo(
    code: json['code'] as String,
    name: json['name'] as String? ?? json['code'] as String,
    description: json['description'] as String? ?? '',
    icon: json['icon'] as String? ?? 'star',
    valueType: json['value_type'] as String? ?? 'flag',
    value: json['value'] is int ? json['value'] as int : null,
    built: json['built'] == true,
  );

  final String code;
  final String name;
  final String description;
  final String icon;

  /// `flag`, `number` or `limit`.
  final String valueType;

  /// For numbers and limits; null for flags.
  final int? value;

  /// False: listed, but the app doesn't do anything with it yet.
  final bool built;
}

/// What this account may do, as the server decided (ROYAL_VIP_ECONOMY §9).
/// The app only uses it to show or hide things; the server re-checks every
/// action.
class Entitlements {
  const Entitlements({this.values = const {}, this.privileges = const []});

  factory Entitlements.fromJson(Map<String, dynamic> json) => Entitlements(
    values: {
      for (final entry in (json['entitlements'] as Map? ?? const {}).entries)
        entry.key.toString(): entry.value,
    },
    privileges: [
      for (final p in json['privileges'] as List? ?? const [])
        PrivilegeInfo.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
  );

  final Map<String, Object?> values;
  final List<PrivilegeInfo> privileges;

  bool has(String code) {
    final found = values[code];
    return found == true || (found is int && found > 0);
  }

  int value(String code) {
    final found = values[code];
    if (found == true) return 1;
    return found is int ? found : 0;
  }
}

/// Entitlements from the server. Tests swap in a fake through
/// [entitlementsRepositoryProvider].
abstract class EntitlementsRepository {
  Future<Entitlements> mine();
}

class ApiEntitlementsRepository implements EntitlementsRepository {
  const ApiEntitlementsRepository(this._api);

  final ApiService _api;

  @override
  Future<Entitlements> mine() async =>
      Entitlements.fromJson(await _api.myEntitlements());
}

final entitlementsRepositoryProvider = Provider<EntitlementsRepository>(
  (ref) => ApiEntitlementsRepository(ref.watch(apiServiceProvider)),
);

/// The signed-in account's entitlements, kept live (`entitlements_updated`).
class EntitlementsController extends AsyncNotifier<Entitlements> {
  @override
  Future<Entitlements> build() async {
    final playerId = ref.watch(
      accountProvider.select((account) => account?.playerId),
    );
    if (playerId == null) return const Entitlements();
    final realtime = ref.watch(realtimeClientProvider);
    if (realtime != null) {
      final live = realtime.channel(RealtimeChannels.user(playerId)).listen((
        message,
      ) {
        if (message.type == 'entitlements_updated') {
          state = AsyncData(Entitlements.fromJson(message.data));
        }
      });
      ref.onDispose(live.cancel);
    }
    return ref.read(entitlementsRepositoryProvider).mine();
  }
}

final entitlementsProvider =
    AsyncNotifierProvider<EntitlementsController, Entitlements>(
      EntitlementsController.new,
    );
