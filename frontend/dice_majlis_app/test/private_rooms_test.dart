// Private rooms v2 (step 1.13): ready, host controls, rules, invites, the
// start countdown and the rematch, against a fake server.

import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_info.dart';
import 'package:dice_majlis_app/features/multiplayer/presentation/waiting_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

const roomId = '11111111-2222-3333-4444-555555555555';

Map<String, dynamic> roomNews({
  String status = 'waiting',
  String hostId = 'p-host',
  bool locked = false,
  int? startsIn,
  Map<String, Object?> options = const {
    'turn_timeout_seconds': 30,
    'capture_enabled': true,
  },
}) => {
  'type': 'room_updated',
  'room_id': roomId,
  'code': 'AB12',
  'status': status,
  'is_locked': locked,
  'game_type': 'ludo',
  'variant': 'classic',
  'max_players': 2,
  'options': options,
  'option_choices': [
    {
      'key': 'turn_timeout_seconds',
      'default': 30,
      'choices': [15, 30, 60],
    },
    {
      'key': 'capture_enabled',
      'default': true,
      'choices': [true, false],
    },
    // A rule this app doesn't know: not shown.
    {
      'key': 'jump_over',
      'default': false,
      'choices': [true, false],
    },
  ],
  'host_id': hostId,
  'starts_in': startsIn,
  'next_room': null,
};

Map<String, dynamic> players({bool guestReady = false}) => {
  'type': 'players_updated',
  'players': [
    {
      'id': 'p-host',
      'name': 'Host Hamad',
      'color': 'red',
      'is_host': true,
      'is_ready': true,
    },
    {
      'id': 'p-guest',
      'name': 'Guest Sara',
      'color': 'blue',
      'is_host': false,
      'is_ready': guestReady,
    },
  ],
};

Future<void> openHub(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(480, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.pump(const Duration(seconds: 2)); // splash
  await tester.pumpAndSettle();
  await tester.tap(find.text('Game Hub'));
  await tester.pumpAndSettle();
}

/// The host's waiting room for room AB12 (2 seats).
Future<FakeSockets> hostRoom(
  WidgetTester tester,
  FakeRoomRepository repo,
) async {
  final sockets = FakeSockets();
  await openHub(tester, testApp(repository: repo, sockets: sockets));
  await tester.tap(find.text('CREATE ROOM'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('2'));
  await tester.pump();
  await tester.tap(find.text('CREATE'));
  await tester.pumpAndSettle();
  expect(find.byType(WaitingRoomScreen), findsOneWidget);
  return sockets;
}

/// A guest's waiting room for room ZX9Q.
Future<FakeSockets> guestRoom(
  WidgetTester tester,
  FakeRoomRepository repo,
) async {
  final sockets = FakeSockets();
  await openHub(tester, testApp(repository: repo, sockets: sockets));
  await tester.tap(find.text('JOIN ROOM'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField), 'ZX9Q');
  await tester.tap(find.text('JOIN'));
  await tester.pumpAndSettle();
  expect(find.byType(WaitingRoomScreen), findsOneWidget);
  return sockets;
}

void main() {
  testWidgets('a guest says they are ready, and can take it back', (
    tester,
  ) async {
    final repo = FakeRoomRepository();
    final sockets = await guestRoom(tester, repo);
    sockets.last.emit(players());
    sockets.last.emit(roomNews());
    await tester.pump();

    expect(find.text('Waiting for everyone to be ready…'), findsOneWidget);
    expect(find.text('Not ready'), findsOneWidget); // Sara's line
    await tester.tap(find.text("I'M READY"));
    await tester.pump();
    expect(repo.calls.last, 'ready:ZX9Q:true');

    sockets.last.emit(players(guestReady: true));
    sockets.last.emit(roomNews(status: 'ready'));
    await tester.pump();
    expect(find.text('Everyone is ready.'), findsOneWidget);
    await tester.tap(find.text('NOT READY YET'));
    await tester.pump();
    expect(repo.calls.last, 'ready:ZX9Q:false');
  });

  testWidgets('the host starts only when everyone is ready; then a countdown', (
    tester,
  ) async {
    final repo = FakeRoomRepository();
    final sockets = await hostRoom(tester, repo);
    sockets.last.emit(players());
    sockets.last.emit(roomNews());
    await tester.pump();

    await tester.tap(find.text('START GAME'));
    await tester.pump();
    expect(repo.calls, isNot(contains('start:AB12')));

    sockets.last.emit(players(guestReady: true));
    sockets.last.emit(roomNews(status: 'ready'));
    await tester.pump();
    await tester.tap(find.text('START GAME'));
    await tester.pump();
    expect(repo.calls.last, 'start:AB12');

    sockets.last.emit(roomNews(status: 'starting', startsIn: 3));
    await tester.pump();
    expect(find.text('Starting in 3…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Starting in 2…'), findsOneWidget);
    expect(find.text('STARTING IN 2…'), findsOneWidget);
    // Leaving the screen stops the countdown's ticker.
    sockets.last.emit(roomNews(status: 'waiting'));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('host controls: remove, make host, lock', (tester) async {
    final repo = FakeRoomRepository();
    final sockets = await hostRoom(tester, repo);
    sockets.last.emit(players());
    sockets.last.emit(roomNews());
    await tester.pump();

    await tester.tap(find.byTooltip('Player options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from the room'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'kick:AB12:p-guest');

    await tester.tap(find.byTooltip('Player options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make host'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'host:AB12:p-guest');

    await tester.tap(find.byTooltip('Lock the room'));
    await tester.pump();
    expect(repo.calls.last, 'lock:AB12:true');
    sockets.last.emit(roomNews(locked: true));
    await tester.pump();
    expect(find.text('Locked: invited players only'), findsOneWidget);
    expect(find.byTooltip('Unlock the room'), findsOneWidget);

    // The host role moved: the controls go with it.
    sockets.last.emit(roomNews(hostId: 'p-guest'));
    await tester.pump();
    expect(find.text('START GAME'), findsNothing);
    expect(find.byTooltip('Player options'), findsNothing);
  });

  testWidgets('the host picks the rules from the server choices', (
    tester,
  ) async {
    final repo = FakeRoomRepository();
    final sockets = await hostRoom(tester, repo);
    sockets.last.emit(roomNews());
    await tester.pump();

    expect(find.text('Turn time'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    expect(find.text('Captures'), findsOneWidget);
    expect(find.text('jump_over'), findsNothing); // unknown rules stay out

    await tester.tap(find.text('Turn time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60 s'));
    await tester.pumpAndSettle();
    expect(
      repo.calls.last,
      'rules:AB12:{turn_timeout_seconds: 60, capture_enabled: true}',
    );
  });

  testWidgets('a guest sees the rules but cannot change them', (tester) async {
    final repo = FakeRoomRepository();
    final sockets = await guestRoom(tester, repo);
    sockets.last.emit(roomNews(options: const {'capture_enabled': false}));
    await tester.pump();
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('Captures'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('invite a friend by Player ID', (tester) async {
    final repo = FakeRoomRepository();
    await hostRoom(tester, repo);

    await tester.tap(find.byTooltip('Invite by Player ID'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('Send invite'));
    await tester.pump();
    expect(find.text('Enter a 9-digit Player ID.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123 456 789');
    await tester.tap(find.text('Send invite'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'invite:AB12:123456789');
    expect(find.text('Invite sent'), findsOneWidget);
  });

  testWidgets('removed by the host: back to the Game Hub', (tester) async {
    final repo = FakeRoomRepository();
    final sockets = await guestRoom(tester, repo);
    sockets.last.emit({'type': 'player_kicked', 'player_id': 'someone-else'});
    await tester.pump();
    expect(find.byType(WaitingRoomScreen), findsOneWidget);

    sockets.last.emit({'type': 'player_kicked', 'player_id': 'p-guest'});
    await tester.pumpAndSettle();
    expect(find.byType(WaitingRoomScreen), findsNothing);
    expect(find.text('The host removed you from the room.'), findsOneWidget);
  });

  testWidgets('invites on Home: live from the user channel; join or decline', (
    tester,
  ) async {
    final repo = FakeRoomRepository()
      ..pendingInvites = [
        const RoomInvite(roomCode: 'QQ11', fromName: 'Hamad'),
      ];
    final server = FakeRealtimeServer();
    await tester.binding.setSurfaceSize(const Size(480, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      testApp(repository: repo, sockets: FakeSockets(), realtime: server),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Hamad invited you to Classic Ludo'), findsOneWidget);

    final channel = server.last.channels.single;
    server.push(channel, 'room_invite', {
      'room_code': 'WW22',
      'game_type': 'ludo',
      'variant': 'classic',
      'from': {'name': 'Sara', 'player_id': 111222333},
    });
    await tester.pumpAndSettle();
    expect(find.text('Sara invited you to Classic Ludo'), findsOneWidget);

    await tester.tap(find.text('Decline').last); // Hamad's (Sara's is first)
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'decline:QQ11');
    expect(find.text('Hamad invited you to Classic Ludo'), findsNothing);

    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'join:WW22');
    expect(find.byType(WaitingRoomScreen), findsOneWidget);
  });
}
