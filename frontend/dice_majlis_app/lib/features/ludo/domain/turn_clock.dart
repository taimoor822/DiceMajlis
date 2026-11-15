/// Countdown for the current turn.
///
/// The server sends *seconds left* rather than a timestamp, so a phone whose
/// clock is wrong still counts down correctly. The server owns the real timer:
/// this is display only.
class TurnClock {
  TurnClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _endsAt;

  /// From the server's `warning_seconds`; the countdown turns urgent below it.
  int warningSeconds = 10;

  void start(int? secondsLeft, {int? warningSeconds}) {
    if (warningSeconds != null) this.warningSeconds = warningSeconds;
    _endsAt = secondsLeft == null
        ? null
        : _now().add(Duration(seconds: secondsLeft));
  }

  void stop() => _endsAt = null;

  bool get isRunning => _endsAt != null;

  /// Whole seconds left (rounded up, never negative), or null with no timer.
  int? get secondsLeft {
    final endsAt = _endsAt;
    if (endsAt == null) return null;
    final ms = endsAt.difference(_now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  bool get isWarning {
    final left = secondsLeft;
    return left != null && left <= warningSeconds;
  }
}
