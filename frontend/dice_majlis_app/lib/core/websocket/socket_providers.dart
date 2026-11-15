import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'socket_service.dart';

/// Creates a socket connection per screen. Tests override this with a fake
/// so no real network is opened.
final socketServiceFactoryProvider = Provider<SocketService Function()>(
  (ref) => SocketService.new,
);
