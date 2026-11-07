/// Session start/end callbacks: services publish them and the composition root
/// registers what runs, so no service imports UI to tear it down.
abstract final class SessionEvents {
  static final List<void Function()> _ended = <void Function()>[];
  static final List<void Function()> _started = <void Function()>[];

  /// Registers a callback for the end of a session. Runs in registration order.
  static void onEnded(void Function() callback) => _ended.add(callback);

  /// Registers a callback for a session that has just been established.
  static void onStarted(void Function() callback) => _started.add(callback);

  /// Announces the end of the session, before [login] returns.
  static void ended() {
    for (final callback in List<void Function()>.of(_ended)) {
      callback();
    }
  }

  /// Announces that the session is up: the first screen may now be shown.
  static void started() {
    for (final callback in List<void Function()>.of(_started)) {
      callback();
    }
  }
}
