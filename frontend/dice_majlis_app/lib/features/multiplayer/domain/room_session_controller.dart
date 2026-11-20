import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'room_session.dart';

/// Holds the current [RoomSession] in memory. After a restart (or a web
/// refresh) the server says which room the account is in, and the splash
/// screen puts it back here.
class RoomSessionController extends Notifier<RoomSession?> {
  @override
  RoomSession? build() {
    // Signing out leaves the room screens behind.
    ref.listen(authControllerProvider, (_, next) {
      if (next is SignedOut) state = null;
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
