import 'package:dice_majlis_app/features/ludo/domain/turn_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late TurnClock clock;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    clock = TurnClock(now: () => now);
  });

  test('no timer until the server sends one', () {
    expect(clock.isRunning, isFalse);
    expect(clock.secondsLeft, isNull);
    expect(clock.isWarning, isFalse);
  });

  test('counts down from the server value and rounds up', () {
    clock.start(30);
    expect(clock.secondsLeft, 30);
    now = now.add(const Duration(milliseconds: 1500));
    expect(clock.secondsLeft, 29);
    now = now.add(const Duration(seconds: 40));
    expect(clock.secondsLeft, 0);
  });

  test('turns urgent at the warning threshold', () {
    clock.start(30, warningSeconds: 10);
    now = now.add(const Duration(seconds: 19));
    expect(clock.isWarning, isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(clock.isWarning, isTrue);
  });

  test('restarting replaces the old countdown; stop clears it', () {
    clock.start(5);
    now = now.add(const Duration(seconds: 4));
    clock.start(30);
    expect(clock.secondsLeft, 30);
    clock.stop();
    expect(clock.secondsLeft, isNull);
  });

  test('a null seconds_left (game over) stops the clock', () {
    clock.start(30);
    clock.start(null);
    expect(clock.isRunning, isFalse);
  });
}
