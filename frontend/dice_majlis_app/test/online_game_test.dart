// Online games over the live connection (step 1.12): the room socket turns
// room/ and game/ channel events into the screens' messages, keeps versions
// in order and loads the whole state again after a gap; roll and move go
// over the socket with the version the board shows.
//
// testWidgets gives a fake clock: `tester.pump()` delivers the fake server's
// answers.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dice_majlis_app/core/network/api_exception.dart';
import 'package:dice_majlis_app/core/network/api_service.dart';
import 'package:dice_majlis_app/core/realtime/game_sync.dart';
import 'package:dice_majlis_app/core/realtime/realtime_client.dart';
import 'package:dice_majlis_app/core/realtime/realtime_message.dart';
import 'package:dice_majlis_app/core/realtime/realtime_room_socket.dart';
import 'package:dice_majlis_app/features/multiplayer/data/room_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

const code = 'ABC123';
const roomId = '11111111-2222-3333-4444-555555555555';
const roomChannel = 'room/$roomId';
const gameChannel = 'game/7';

const players = [
  {'id': 'p1', 'name': 'You', 'color': 'red', 'is_host': true},
  {'id': 'p2', 'name': 'Friend', 'color': 'blue', 'is_host': false},
];

/// What the server's `request_state` / `game_started` carry.
Map<String, dynamic> snapshot({int? version = 3, bool started = true}) => {
  'room_code': code,
  'room_id': roomId,
  'game_type': 'ludo',
  'variant': 'classic',
  'game_id': started ? '7' : null,
  'players': players,
  'current_turn_player_id': started ? 'p1' : null,
  'version': started ? version : null,
  'tokens': const [],
};

Map<String, dynamic> event(
  String channel,
  String type,
  Map<String, dynamic> data, {
  int? version,
}) => {
  'v': 1,
  'type': type,
  'channel': channel,
  'data': data,
  'version': ?version,
};

/// No REST calls in these tests: game actions go over the socket.
class NoRestApi implements ApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('REST was called: ${invocation.memberName}');
}

class Harness {
  Harness() {
    client = RealtimeClient(
      connect: server.connect,
      uri: Uri.parse('ws://test/ws/v1/'),
      accessToken: () async => 'access',
      refreshAccess: () async => 'access',
      random: Random(1),
    );
    server.handlers['request_state'] = (data) {
      stateRequests.add(data);
      return state;
    };
  }

  final server = FakeRealtimeServer();
  final sync = GameSync();
  late final RealtimeClient client;
  late final RealtimeRoomSocket socket;
  StreamSubscription<dynamic>? _listening;

  /// What `request_state` answers.
  Map<String, dynamic> state = snapshot();
  final stateRequests = <Map<String, dynamic>>[];

  /// Messages the screen got, decoded.
  final got = <Map<String, dynamic>>[];
  List<String> get types => [for (final m in got) m['type'] as String];

  Future<void> open(WidgetTester tester, {String? withRoomId = roomId}) async {
    client.start();
    await tester.pump();
    socket = RealtimeRoomSocket(client, sync: sync);
    _listening = socket.stream.listen(
      (m) => got.add(Map<String, dynamic>.from(jsonDecode(m as String) as Map)),
    );
    socket.connect(code, roomId: withRoomId);
    await tester.pump();
  }

  void push(String channel, String type, Map<String, dynamic> data, {int? v}) =>
      server.push(channel, type, data, version: v);

  /// Stop everything inside the test, so no timer outlives it.
  Future<void> finish(WidgetTester tester) async {
    unawaited(_listening?.cancel());
    socket.disconnect();
    await client.stop();
    await tester.pump();
  }
}

void main() {
  testWidgets('a waiting room: who is seated, from the room channel', (
    tester,
  ) async {
    final h = Harness()..state = snapshot(started: false);
    h.server.initialEvents[roomChannel] = [
      event(roomChannel, 'players_updated', {'players': players}),
    ];
    await h.open(tester);

    expect(h.server.last.channels, {roomChannel});
    expect(h.stateRequests.single, {'code': code});
    expect(h.types, ['players_updated', 'players_updated']);
    expect(h.got.first['players'], players);

    h.push(roomChannel, 'players_updated', {
      'players': players.take(1).toList(),
    });
    await tester.pump();
    expect((h.got.last['players'] as List), hasLength(1));

    // Room news passes through as it is (status, kicks, the rematch).
    h.push(roomChannel, 'room_updated', {'status': 'ready', 'host_id': 'p1'});
    h.push(roomChannel, 'player_kicked', {'player_id': 'p2'});
    await tester.pump();
    expect(h.got[h.got.length - 2], {
      'type': 'room_updated',
      'status': 'ready',
      'host_id': 'p1',
    });
    expect(h.got.last, {'type': 'player_kicked', 'player_id': 'p2'});
    await h.finish(tester);
  });

  testWidgets('the game starts: one snapshot, then events in version order', (
    tester,
  ) async {
    final h = Harness()..state = snapshot(started: false);
    await h.open(tester);
    h.got.clear();

    h.state = snapshot(version: 0);
    h.server.initialEvents[gameChannel] = [
      event(gameChannel, 'state_snapshot', snapshot(version: 0), version: 0),
    ];
    h.push(roomChannel, 'game_started', snapshot(version: 0), v: 0);
    await tester.pump();

    expect(h.server.last.channels, {roomChannel, gameChannel});
    // The game channel's own first snapshot is the same picture: sent once.
    expect(h.types, ['game_started']);
    expect(h.got.single['game_id'], '7');
    expect(h.sync.version(code), 0);

    final rolled = {
      'player_id': 'p1',
      'dice': 6,
      'movable_token_ids': ['t1'],
    };
    h.push(gameChannel, 'dice_rolled', rolled, v: 1);
    h.push(gameChannel, 'token_moved', {'token_id': 't1', 'to': 0}, v: 2);
    h.push(gameChannel, 'turn_changed', {'player_id': 'p1'}, v: 2); // same move
    h.push(gameChannel, 'dice_rolled', rolled, v: 1); // already on the board
    await tester.pump();

    expect(h.types, [
      'game_started',
      'dice_rolled',
      'token_moved',
      'turn_changed',
    ]);
    expect(h.got[1], {'type': 'dice_rolled', ...rolled, 'version': 1});
    expect(h.sync.version(code), 2);
    expect(h.stateRequests, hasLength(1)); // only when the socket opened
    await h.finish(tester);
  });

  testWidgets('a missed event: the whole state is loaded again', (
    tester,
  ) async {
    final h = Harness()..state = snapshot(version: 3);
    await h.open(tester);
    expect(h.types, ['game_started']);
    expect(h.sync.version(code), 3);

    h.state = snapshot(version: 6);
    h.push(gameChannel, 'token_moved', {'token_id': 't1'}, v: 6); // 4, 5 missed
    await tester.pump();

    expect(h.stateRequests, hasLength(2));
    expect(h.types, ['game_started', 'game_started']);
    expect(h.got.last['version'], 6);
    expect(h.sync.version(code), 6);

    h.push(gameChannel, 'turn_changed', {'player_id': 'p2'}, v: 7);
    await tester.pump();
    expect(h.types.last, 'turn_changed');
    await h.finish(tester);
  });

  testWidgets('opened without the room id: the server tells it', (
    tester,
  ) async {
    final h = Harness()..state = snapshot(version: 4);
    await h.open(tester, withRoomId: null);

    expect(h.server.last.channels, {roomChannel, gameChannel});
    expect(h.types, ['game_started']);
    expect(h.got.single['version'], 4);
    await h.finish(tester);
  });

  testWidgets('roll and move go over the socket with the board version', (
    tester,
  ) async {
    final h = Harness()..state = snapshot(version: 4);
    await h.open(tester);
    final asked = <String, Map<String, dynamic>>{};
    h.server.handlers['roll_dice'] = (data) {
      asked['roll'] = data;
      return {
        'version': 5,
        'dice': 6,
        'movable_token_ids': ['t1', 't2'],
      };
    };
    h.server.handlers['move_token'] = (data) {
      asked['move'] = data;
      return {'version': 6, 'finished': false, 'winner': false};
    };
    final repository = ApiRoomRepository(
      NoRestApi(),
      realtime: h.client,
      sync: h.sync,
    );

    final rolling = repository.rollDice(code);
    await tester.pump();
    final roll = await rolling;
    expect(asked['roll'], {'code': code, 'expected_version': 4});
    expect(roll.dice, 6);
    expect(roll.movableTokenIds, ['t1', 't2']);
    expect(h.sync.version(code), 5); // the answer's version, before its event

    final moving = repository.moveToken(code, 't2');
    await tester.pump();
    await moving;
    expect(asked['move'], {
      'code': code,
      'expected_version': 5,
      'token_id': 't2',
    });
    expect(h.server.last.sentOfType('roll_dice').single['req_id'], isNotNull);
    await h.finish(tester);
  });

  testWidgets('an old board: refused, then the state is loaded again', (
    tester,
  ) async {
    final h = Harness()..state = snapshot(version: 4);
    await h.open(tester);
    h.server.handlers['roll_dice'] = (data) =>
        throw const RealtimeException('stale_version', 'the game is at 9');
    final repository = ApiRoomRepository(
      NoRestApi(),
      realtime: h.client,
      sync: h.sync,
    );

    h.state = snapshot(version: 9);
    final rolling = repository.rollDice(code);
    final failed = expectLater(
      rolling,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'stale_version'),
      ),
    );
    await tester.pump();
    await failed;
    await tester.pump();

    expect(h.stateRequests, hasLength(2));
    expect(h.got.last['type'], 'game_started');
    expect(h.got.last['version'], 9);
    expect(h.sync.version(code), 9);
    await h.finish(tester);
  });

  test('offline: the action fails as a network error', () async {
    final offline = RealtimeClient(
      connect: FakeRealtimeServer().connect,
      uri: Uri.parse('ws://test/ws/v1/'),
      accessToken: () async => 'access',
      refreshAccess: () async => 'access',
    );
    final repository = ApiRoomRepository(
      NoRestApi(),
      realtime: offline,
      sync: GameSync(),
    );
    await expectLater(
      repository.rollDice(code),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiException.networkError,
        ),
      ),
    );
  });
}
