import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime_message.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../data/room_repository.dart';
import 'room_info.dart';

/// Invites to rooms (by Player ID). Loaded from the server, then kept live by
/// the `user/<player id>` channel (`room_invite`), so an invite shows on Home
/// the moment a friend sends it.
class RoomInvitesController extends AsyncNotifier<List<RoomInvite>> {
  @override
  Future<List<RoomInvite>> build() async {
    final playerId = ref.watch(
      accountProvider.select((account) => account?.playerId),
    );
    if (playerId == null) return const [];
    final realtime = ref.watch(realtimeClientProvider);
    if (realtime != null) {
      final live = realtime
          .channel(RealtimeChannels.user(playerId))
          .listen(_onUserEvent);
      ref.onDispose(live.cancel);
    }
    return ref.read(roomRepositoryProvider).invites();
  }

  void _onUserEvent(RealtimeMessage message) {
    if (message.type != 'room_invite') return;
    final invite = RoomInvite.fromJson(message.data);
    final others = (state.valueOrNull ?? const <RoomInvite>[]).where(
      (i) => i.roomCode != invite.roomCode,
    );
    state = AsyncData([invite, ...others]);
  }

  /// Joined, declined or gone: off the list.
  void remove(String roomCode) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final invite in current)
        if (invite.roomCode != roomCode) invite,
    ]);
  }
}

final roomInvitesProvider =
    AsyncNotifierProvider<RoomInvitesController, List<RoomInvite>>(
      RoomInvitesController.new,
    );
