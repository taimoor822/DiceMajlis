// Account XP (step 2.1): the level follows the server live.

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/features/profile/domain/xp_gain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

void main() {
  test('an XP message is read, or ignored when it is broken', () {
    final gain = XpGain.fromJson({
      'amount': 20,
      'reason': 'game',
      'room_code': 'QX7P2M',
      'level_up': false,
      'level': 1,
      'xp': 20,
      'level_xp': 0,
      'next_level_xp': 100,
    })!;
    expect(
      (gain.amount, gain.roomCode, gain.levelUp, gain.nextLevelXp),
      (20, 'QX7P2M', false, 100),
    );
    expect(XpGain.fromJson({'amount': '20', 'level': 1, 'xp': 20}), isNull);
  });

  testWidgets('XP from the server updates the level everywhere', (
    tester,
  ) async {
    final server = FakeRealtimeServer();
    await tester.pumpWidget(
      testApp(
        repository: FakeRoomRepository(),
        sockets: FakeSockets(),
        realtime: server,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DiceMajlisApp)),
    );
    final account = container.read(accountProvider)!;
    final channel = 'user/${account.playerId}';
    expect(server.last.channels, contains(channel));

    server.push(channel, 'xp_gained', {
      'amount': 50,
      'reason': 'game',
      'reference_type': 'game',
      'reference_id': '12',
      'room_code': 'QX7P2M',
      'level_up': true,
      'level': 3,
      'xp': 320,
      'level_xp': 300,
      'next_level_xp': 600,
    });
    await tester.pumpAndSettle();

    final now = container.read(accountProvider)!;
    expect(
      (now.level, now.xp, now.levelXp, now.nextLevelXp),
      (3, 320, 300, 600),
    );
    expect(now.displayName, account.displayName); // the rest is kept
    expect(container.read(xpGainsProvider)['QX7P2M']?.amount, 50);
  });
}
