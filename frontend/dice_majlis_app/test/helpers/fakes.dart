import 'dart:async';
import 'dart:convert';

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/core/auth/auth_api.dart';
import 'package:dice_majlis_app/core/auth/token_store.dart';
import 'package:dice_majlis_app/core/network/api_exception.dart';
import 'package:dice_majlis_app/core/websocket/socket_providers.dart';
import 'package:dice_majlis_app/core/websocket/socket_service.dart';
import 'package:dice_majlis_app/features/multiplayer/data/room_repository.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Room API without a server. Records calls; [failWith] makes every call fail
/// with that server error code (e.g. `room_full`, `network_error`).
class FakeRoomRepository implements RoomRepository {
  FakeRoomRepository({
    this.failWith,
    this.options = const RoomOptions(
      playerCounts: [2, 3, 4],
      defaultPlayerCount: 4,
    ),
    this.joinStarted = false,
  });

  String? failWith;
  RoomOptions options;

  /// Joining returns a room whose game has already started (rejoining).
  bool joinStarted;
  final calls = <String>[];

  void _maybeFail() {
    final code = failWith;
    if (code != null) throw ApiException(code);
  }

  RoomSession _session(String code, {required bool host, int? maxPlayers}) =>
      RoomSession(
        roomCode: code,
        playerId: host ? 'p-host' : 'p-guest',
        isHost: host,
        isStarted: !host && joinStarted,
        maxPlayers: maxPlayers,
        self: RoomPlayer(
          id: host ? 'p-host' : 'p-guest',
          name: host ? 'Guest 6789' : 'Guest 4321',
          color: host ? 'red' : 'blue',
          isHost: host,
        ),
      );

  @override
  Future<RoomOptions> roomOptions() async {
    calls.add('options');
    _maybeFail();
    return options;
  }

  @override
  Future<RoomSession> createRoom({required int maxPlayers}) async {
    calls.add('create:$maxPlayers');
    _maybeFail();
    return _session('AB12', host: true, maxPlayers: maxPlayers);
  }

  @override
  Future<RoomSession> joinRoom(String code) async {
    calls.add('join:$code');
    _maybeFail();
    return _session(code, host: false, maxPlayers: 4);
  }

  @override
  Future<void> startGame(String roomCode) async {
    calls.add('start:$roomCode');
    _maybeFail();
  }

  @override
  Future<RollResult> rollDice(String roomCode) async {
    calls.add('roll:$roomCode');
    _maybeFail();
    return const RollResult(dice: 6, movableTokenIds: []);
  }

  @override
  Future<void> moveToken(String roomCode, String tokenId) async {
    calls.add('move:$roomCode:$tokenId');
    _maybeFail();
  }

  @override
  Future<void> leaveRoom(String roomCode) async {
    calls.add('leave:$roomCode');
    _maybeFail();
  }
}

/// The account the fake server signs everyone in as.
const testAccount = Account(
  playerId: 123456789,
  displayName: 'Guest 6789',
  isGuest: true,
);

/// Sign-in API without a server. [failWith] makes calls fail with that code
/// (`network_error`, `session_revoked`, ...). Each answer has new tokens.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({this.account = testAccount, this.failWith, Duration? lifetime})
    : lifetime = lifetime ?? const Duration(minutes: 15);

  Account account;
  String? failWith;

  /// How long each access token lasts (zero: every request refreshes).
  Duration lifetime;
  final calls = <String>[];
  int _issued = 0;

  AuthTokens _tokens() {
    final code = failWith;
    if (code != null) throw ApiException(code);
    _issued++;
    return AuthTokens(
      access: 'access-$_issued',
      refresh: 'refresh-$_issued',
      accessExpiresIn: lifetime,
      account: account,
    );
  }

  @override
  Future<AuthTokens> signInAsGuest({
    required String deviceId,
    required String platform,
  }) async {
    calls.add('guest:$deviceId');
    return _tokens();
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    calls.add('refresh:$refreshToken');
    return _tokens();
  }

  @override
  Future<Account> me(String access) async => account;

  @override
  Future<void> signOut(String access) async => calls.add('signOut:$access');
}

/// Token storage in memory. Starts with [refreshToken] (null = signed out).
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore({this.refreshToken});

  String? refreshToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveRefreshToken(String token) async => refreshToken = token;

  @override
  Future<void> clearRefreshToken() async => refreshToken = null;

  @override
  Future<String> deviceId() async => 'test-device-0001';
}

/// A socket the test drives by hand: [emit] plays a server message.
class FakeSocketService extends SocketService {
  // sync: a message reaches the screen as soon as the test emits it.
  final _controller = StreamController<dynamic>.broadcast(sync: true);
  String? connectedRoom;
  bool disconnected = false;

  @override
  void connect(String roomCode) => connectedRoom = roomCode;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void disconnect() => disconnected = true;

  void emit(Map<String, dynamic> message) =>
      _controller.add(jsonEncode(message));
}

/// Every socket the app opened, newest last.
class FakeSockets {
  final opened = <FakeSocketService>[];
  FakeSocketService get last => opened.last;

  FakeSocketService create() {
    final socket = FakeSocketService();
    opened.add(socket);
    return socket;
  }
}

/// Provider overrides that swap the network for fakes. Without [auth] and
/// [tokens] the player has a saved sign-in, so the app opens signed in.
List<Override> fakeNetwork({
  required FakeRoomRepository repository,
  required FakeSockets sockets,
  FakeAuthApi? auth,
  MemoryTokenStore? tokens,
}) => [
  roomRepositoryProvider.overrideWithValue(repository),
  socketServiceFactoryProvider.overrideWithValue(sockets.create),
  authApiProvider.overrideWithValue(auth ?? FakeAuthApi()),
  tokenStoreProvider.overrideWithValue(
    tokens ?? MemoryTokenStore(refreshToken: 'saved-refresh'),
  ),
];

/// The whole app with fakes in place of the network. [overrides] adds more
/// (e.g. settings storage).
Widget testApp({
  required FakeRoomRepository repository,
  required FakeSockets sockets,
  FakeAuthApi? auth,
  MemoryTokenStore? tokens,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    ...fakeNetwork(
      repository: repository,
      sockets: sockets,
      auth: auth,
      tokens: tokens,
    ),
    ...overrides,
  ],
  child: const DiceMajlisApp(),
);
