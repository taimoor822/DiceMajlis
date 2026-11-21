import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import 'realtime_client.dart';
import 'realtime_connection.dart';

/// How sockets are opened. Tests override it with a fake server.
final realtimeConnectorProvider = Provider<RealtimeConnector>(
  (ref) => WebSocketRealtimeConnection.connect,
);

/// The live connection while someone is signed in (null when signed out).
/// One per signed-in account: signing out or switching accounts closes it.
final realtimeClientProvider = Provider<RealtimeClient?>((ref) {
  final playerId = ref.watch(
    accountProvider.select((account) => account?.playerId),
  );
  if (playerId == null) return null;
  final auth = ref.read(authControllerProvider.notifier);
  final client = RealtimeClient(
    connect: ref.read(realtimeConnectorProvider),
    uri: AppConfig.realtimeUri,
    accessToken: auth.accessToken,
    refreshAccess: auth.refreshAccess,
  );
  ref.onDispose(client.stop);
  client.start();
  return client;
});

/// Channel names (server: `realtime/topics.py`, `game/topics.py`).
abstract final class RealtimeChannels {
  /// Your account: balances today; items and invites later.
  static String user(int playerId) => 'user/$playerId';

  static String notifications(int playerId) => 'notifications/$playerId';

  /// Who is seated, and the game starting (members only).
  static String room(String roomId) => 'room/$roomId';

  /// A game's events, each with the state version (seated players only).
  static String game(String gameId) => 'game/$gameId';
}
