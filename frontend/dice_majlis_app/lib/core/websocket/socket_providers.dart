import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../realtime/game_sync.dart';
import '../realtime/realtime_providers.dart';
import '../realtime/realtime_room_socket.dart';
import 'socket_service.dart';

/// Creates a room socket per screen: on the live connection (`/ws/v1/`) when
/// signed in, else the old lobby socket. Tests override this with a fake so
/// no real network is opened.
final socketServiceFactoryProvider = Provider<SocketService Function()>((ref) {
  final client = ref.watch(realtimeClientProvider);
  if (client == null) return LobbySocketService.new;
  final sync = ref.watch(gameSyncProvider);
  return () => RealtimeRoomSocket(client, sync: sync);
});
