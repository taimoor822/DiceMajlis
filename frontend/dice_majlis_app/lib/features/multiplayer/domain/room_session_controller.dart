import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'room_session.dart';

/// Holds the current [RoomSession] in memory. After a restart (or a web
/// refresh), and whenever the player signs in, the server says which room the
/// account is in and it is put back here.
class RoomSessionController extends Notifier<RoomSession?> {
  @override
  RoomSession? build() {
    ref.listen(authControllerProvider, (previous, next) {
      // Signing out leaves the room screens behind.
      if (next is SignedOut) state = null;
      // Signing in (any way) goes back to the room the account is in.
      if (next is SignedIn && previous is! SignedIn) {
        final room = next.account.activeRoom;
        if (room != null) state = RoomSession.fromActiveRoom(room);
      }
    });
    return null;
  }

  void start(RoomSession session) => state = session;

  void clear() => state = null;
}

final roomSessionProvider =
    NotifierProvider<RoomSessionController, RoomSession?>(
      RoomSessionController.new,
    );
