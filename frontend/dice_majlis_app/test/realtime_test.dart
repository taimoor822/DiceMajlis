// The app's one live connection (/ws/v1/): sign-in, heartbeats, reconnects,
// channels, requests, and Home's balances following the user/ channel.
//
// testWidgets gives a fake clock: `tester.pump(duration)` moves time on.

import 'dart:async';
import 'dart:math';

import 'package:dice_majlis_app/core/realtime/realtime_client.dart';
import 'package:dice_majlis_app/core/realtime/realtime_message.dart';
import 'package:dice_majlis_app/features/wallet/domain/wallet_models.dart';
import 'package:dice_majlis_app/features/wallet/presentation/balance_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// A client on a fake server, with a token source the test controls.
class Harness {
  Harness() {
    client = RealtimeClient(
      connect: server.connect,
      uri: Uri.parse('ws://test/ws/v1/'),
      accessToken: () async => signedOut ? null : 'access-$issued',
      refreshAccess: () async {
        refreshes++;
        issued++;
        return signedOut ? null : 'access-$issued';
      },
      random: Random(1),
    );
  }

  final server = FakeRealtimeServer();
  late final RealtimeClient client;
  int issued = 1;
  int refreshes = 0;
  bool signedOut = false;

  /// Stop the client inside the test, so no timer outlives it.
  Future<void> finish(WidgetTester tester) async {
    await client.stop();
    await tester.pump();
  }
}

Future<Harness> connected(WidgetTester tester) async {
  final h = Harness();
  h.client.start();
  await tester.pump();
  expect(h.client.status.value, RealtimeStatus.online);
  return h;
}

void main() {
  testWidgets('signs in with the access token as the first message', (
    tester,
  ) async {
    final h = await connected(tester);
    final first = h.server.last.sent.first;
    expect(first['v'], 1);
    expect(first['type'], 'auth');
    expect(first['data'], {'access_token': 'access-1'});
    expect(first['req_id'], isA<String>());
    expect(h.server.connections, hasLength(1));
    await h.finish(tester);
  });

  testWidgets('channels: subscribe on listen, events arrive, unsubscribe', (
    tester,
  ) async {
    final h = await connected(tester);
    final got = <RealtimeMessage>[];
    final sub = h.client.channel('user/123456789').listen(got.add);
    await tester.pump();
    expect(h.server.last.channels, {'user/123456789'});

    h.server.push('user/123456789', 'balances_changed', {
      'balances': {'gold': 5},
    });
    await tester.pump();
    expect(got.single.type, 'balances_changed');
    expect(got.single.data['balances'], {'gold': 5});

    // Not awaited: a cancel future can finish outside the test's fake clock.
    unawaited(sub.cancel());
    await tester.pump();
    expect(h.server.last.channels, isEmpty);
    expect(h.server.last.sentOfType('unsubscribe'), hasLength(1));
    await h.finish(tester);
  });

  testWidgets('a subscription made while offline is sent once signed in', (
    tester,
  ) async {
    final h = Harness();
    final got = <RealtimeMessage>[];
    h.client.channel('notifications/123456789').listen(got.add);
    h.client.start();
    await tester.pump();
    expect(h.server.last.channels, {'notifications/123456789'});
    await h.finish(tester);
  });

  testWidgets('a dropped connection comes back and subscribes again', (
    tester,
  ) async {
    final h = await connected(tester);
    h.client.channel('user/123456789').listen((_) {});
    await tester.pump();

    h.server.last.serverClose(1006); // network gone
    await tester.pump();
    expect(h.client.status.value, RealtimeStatus.connecting);
    expect(h.server.connections, hasLength(1));

    await tester.pump(const Duration(milliseconds: 1300)); // ~1 s + jitter
    expect(h.server.connections, hasLength(2));
    expect(h.client.status.value, RealtimeStatus.online);
    expect(h.server.last.channels, {'user/123456789'});
    expect(h.refreshes, 0); // same token
    await h.finish(tester);
  });

  testWidgets('retries wait longer each time, up to 30 seconds', (
    tester,
  ) async {
    final h = await connected(tester);
    h.server.reachable = false;
    h.server.last.serverClose(1006);
    await tester.pump();

    // Note when each attempt happens, in steps of a quarter second.
    const step = Duration(milliseconds: 250);
    final attemptsAt = <double>[0];
    var seen = h.server.attempts;
    for (var t = 1; t <= 4 * 150; t++) {
      await tester.pump(step);
      if (h.server.attempts > seen) {
        seen = h.server.attempts;
        attemptsAt.add(t / 4);
      }
    }
    // 1, 2, 4, 8, 16, then 30 s each time, each ±20 % (jitter).
    for (var i = 1; i < attemptsAt.length; i++) {
      final gap = attemptsAt[i] - attemptsAt[i - 1];
      final expected = min(1 << (i - 1), 30);
      expect(
        gap,
        inInclusiveRange(expected * 0.8 - 0.25, expected * 1.2 + 0.25),
      );
    }
    expect(attemptsAt.length, greaterThan(6));

    h.server.reachable = true;
    await tester.pump(const Duration(seconds: 37));
    expect(h.client.status.value, RealtimeStatus.online);
    await h.finish(tester);
  });

  testWidgets('a refused token (4401): refresh it, then reconnect', (
    tester,
  ) async {
    final h = Harness();
    h.server.refuseTokens.add('access-1');
    h.client.start();
    await tester.pump();
    expect(h.server.last.closeCode, 4401);
    expect(h.client.status.value, RealtimeStatus.connecting);

    await tester.pump(const Duration(seconds: 2));
    expect(h.refreshes, 1);
    expect(h.server.tokens, ['access-1', 'access-2']);
    expect(h.client.status.value, RealtimeStatus.online);
    await h.finish(tester);
  });

  testWidgets('signed out: the client stops instead of retrying', (
    tester,
  ) async {
    final h = Harness()..signedOut = true;
    h.client.start();
    await tester.pump(const Duration(seconds: 5));
    expect(h.server.connections, isEmpty);
    expect(h.client.status.value, RealtimeStatus.offline);
    await h.finish(tester);
  });

  testWidgets('pings every 20 s; two missed pongs mean a dead connection', (
    tester,
  ) async {
    final h = await connected(tester);
    await tester.pump(const Duration(seconds: 20));
    expect(h.server.last.sentOfType('ping'), hasLength(1));
    expect(h.server.connections, hasLength(1));

    h.server.answerPings = false;
    await tester.pump(const Duration(seconds: 20)); // unanswered 1
    await tester.pump(const Duration(seconds: 20)); // unanswered 2
    await tester.pump(const Duration(seconds: 20)); // gives up
    expect(h.server.connections.first.closed, isTrue);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(h.server.connections, hasLength(2));
    await h.finish(tester);
  });

  testWidgets('requests: ack data, refusals by code, offline fails fast', (
    tester,
  ) async {
    final h = await connected(tester);
    await expectLater(
      h.client.request('fly_away'),
      throwsA(
        isA<RealtimeException>().having((e) => e.code, 'code', 'unknown_type'),
      ),
    );

    final hello = h.client.request(
      'subscribe',
      data: {'channel': 'user/123456789'},
    );
    await tester.pump();
    expect(await hello, {'channel': 'user/123456789'});

    await h.client.stop();
    await expectLater(
      h.client.request('subscribe'),
      throwsA(
        isA<RealtimeException>().having((e) => e.code, 'code', 'disconnected'),
      ),
    );
    await h.finish(tester);
  });

  testWidgets('a request with no answer times out', (tester) async {
    final h = await connected(tester);
    h.server.answerPings = false;
    final future = h.client.request('ping');
    final expectation = expectLater(
      future,
      throwsA(
        isA<RealtimeException>().having((e) => e.code, 'code', 'timeout'),
      ),
    );
    await tester.pump(const Duration(seconds: 11));
    await expectation;
    await h.finish(tester);
  });

  testWidgets('Home balances follow the server live', (tester) async {
    final server = FakeRealtimeServer();
    await tester.binding.setSurfaceSize(const Size(480, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      testApp(
        repository: FakeRoomRepository(),
        sockets: FakeSockets(),
        wallet: FakeWalletRepository(balance: const Balances(gold: 1250)),
        realtime: server,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    Finder inChips(String text) => find.descendant(
      of: find.byType(BalanceChips),
      matching: find.text(text),
    );
    expect(inChips('1,250'), findsOneWidget);
    final channel = 'user/${server.last.channels.single.split('/').last}';
    expect(server.last.channels, {channel});

    // A reward claimed on another phone.
    server.push(channel, 'balances_changed', {
      'balances': {'gold': 1400, 'diamond': 3},
    });
    await tester.pumpAndSettle();
    expect(inChips('1,400'), findsOneWidget);
    expect(inChips('3'), findsOneWidget);
  });
}
