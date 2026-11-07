import 'dart:async';

import 'package:pocketbase/pocketbase.dart';

enum NotificationSessionKind { staff, patient }

/// A login token is not proof that stores and permissions are ready;
/// activation publishes this phase at its end.
enum NotificationSessionPhase { restoring, active, absent }

/// Immutable snapshot of a session. An async continuation that mutates state
/// must re-check [NotificationSessionCoordinator.isCurrent] after every await.
class NotificationSessionSnapshot {
  const NotificationSessionSnapshot({
    required this.generation,
    required this.kind,
    required this.server,
    required this.accountId,
    required this.authToken,
    required this.email,
    this.pocketBase,
    this.clinicKey,
  });

  final int generation;
  final NotificationSessionKind kind;
  final String server;
  final String accountId;

  /// Staff auth token for relay-key resolution; empty for a patient session.
  final String authToken;

  /// The staff email captured alongside [authToken]. Empty for a patient.
  final String email;

  /// Null for a patient session, which carries [clinicKey] from its link instead.
  final PocketBase? pocketBase;

  /// The patient link's relay key, when this is a patient session.
  final String? clinicKey;

  bool get isPatient => kind == NotificationSessionKind.patient;

  bool get isUsable => server.isNotEmpty && accountId.isNotEmpty;
}

/// Does not wait on `login.ready` inside an activation, since that would wait
/// on itself; login and patient services publish the boundary when ready.
class NotificationSessionCoordinator {
  NotificationSessionCoordinator({
    this.waitTimeout = const Duration(seconds: 60),
  });

  /// Upper bound for a click waiting on a session, so a blocked restore cannot
  /// leave a Dart waiter pending.
  final Duration waitTimeout;

  final List<void Function()> _listeners = [];
  final List<_SessionWaiter> _waiters = [];

  NotificationSessionPhase _phase = NotificationSessionPhase.restoring;
  NotificationSessionSnapshot? _active;
  int _generation = 0;
  bool _disposed = false;

  NotificationSessionPhase get phase => _phase;

  /// Monotonic counter; a delayed "no session" resolution must not overwrite a
  /// newer activation.
  int get revision => _generation;

  NotificationSessionSnapshot? get active => _active;

  /// Invalidates the previous snapshot immediately but leaves waiters pending;
  /// the new activation publishes or marks the state absent.
  void beginRestoring() {
    if (_disposed) return;
    _generation++;
    _phase = NotificationSessionPhase.restoring;
    _active = null;
    _notifyListeners();
  }

  NotificationSessionSnapshot publishStaff({
    required String server,
    required String accountId,
    required PocketBase? pocketBase,
    required String authToken,
    required String email,
  }) {
    return _publish(NotificationSessionSnapshot(
      generation: ++_generation,
      kind: NotificationSessionKind.staff,
      server: server,
      accountId: accountId,
      authToken: authToken,
      email: email,
      pocketBase: pocketBase,
    ));
  }

  NotificationSessionSnapshot publishPatient({
    required String server,
    required String accountId,
    required String clinicKey,
  }) {
    return _publish(NotificationSessionSnapshot(
      generation: ++_generation,
      kind: NotificationSessionKind.patient,
      server: server,
      accountId: accountId,
      authToken: '',
      email: '',
      clinicKey: clinicKey,
    ));
  }

  NotificationSessionSnapshot _publish(NotificationSessionSnapshot snapshot) {
    if (_disposed) return snapshot;
    _active = snapshot;
    _phase = NotificationSessionPhase.active;
    final waiters = List<_SessionWaiter>.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.complete(snapshot);
    }
    _notifyListeners();
    return snapshot;
  }

  void markAbsent() {
    if (_disposed) return;
    _generation++;
    _phase = NotificationSessionPhase.absent;
    _active = null;
    final waiters = List<_SessionWaiter>.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.complete(null);
    }
    _notifyListeners();
  }

  /// Alias used by logout paths: the current session is no longer usable.
  void invalidate() => markAbsent();

  Future<NotificationSessionSnapshot?> waitForUsableSession({
    Duration? timeout,
  }) async {
    if (_disposed) return null;
    if (_phase == NotificationSessionPhase.active) return _active;
    if (_phase == NotificationSessionPhase.absent) return null;

    final waiter = _SessionWaiter();
    _waiters.add(waiter);
    final effectiveTimeout = timeout ?? waitTimeout;
    if (effectiveTimeout > Duration.zero) {
      waiter.timer = Timer(effectiveTimeout, () {
        if (!_waiters.remove(waiter)) return;
        waiter.complete(null);
      });
    }
    return waiter.future;
  }

  /// Whether [snapshot] still describes the current active session.
  bool isCurrent(NotificationSessionSnapshot snapshot) {
    final active = _active;
    return !_disposed &&
        _phase == NotificationSessionPhase.active &&
        active != null &&
        active.generation == snapshot.generation &&
        active.kind == snapshot.kind &&
        active.server == snapshot.server &&
        active.accountId == snapshot.accountId;
  }

  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in List<void Function()>.of(_listeners)) {
      try {
        listener();
      } catch (_) {
        // A throwing listener must not break the transition or the waiters it feeds.
      }
    }
  }

  /// Test seam: forgets every waiter and listener.
  void resetForTesting() {
    _disposed = true;
    for (final waiter in List<_SessionWaiter>.of(_waiters)) {
      waiter.complete(null);
    }
    _waiters.clear();
    _listeners.clear();
    _active = null;
    _phase = NotificationSessionPhase.restoring;
    _generation++;
    _disposed = false;
  }
}

class _SessionWaiter {
  final Completer<NotificationSessionSnapshot?> _completer =
      Completer<NotificationSessionSnapshot?>();
  Timer? timer;

  Future<NotificationSessionSnapshot?> get future => _completer.future;

  void complete(NotificationSessionSnapshot? value) {
    timer?.cancel();
    timer = null;
    if (!_completer.isCompleted) _completer.complete(value);
  }
}

/// The app's single notification-session coordinator.
final NotificationSessionCoordinator notificationSessions =
    NotificationSessionCoordinator();
