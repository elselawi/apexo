/// What the app does when a session begins or ends — published by [login]
/// rather than performed by it.
///
/// Authenticating a clinic is a service's work; closing panels, resetting the
/// route stack and showing the changelog are the app's. The service announces
/// the event and the composition root registers what runs, so a service never
/// imports a widget, a panel, a window or a feature to tear them down.
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
