import 'dart:async';

import 'package:pocketbase/pocketbase.dart';

/// Whether the notification session belongs to a staff account or a patient
/// portal link.
enum NotificationSessionKind { staff, patient }

/// The state of session restoration as far as notification work is concerned.
///
/// A nonempty login token is *not* proof that the stores and permissions are
/// ready. This coordinator is published only at the end of a successful
/// activation, so a push that arrives during startup waits for the real
/// boundary instead of running against a half-built session.
enum NotificationSessionPhase { restoring, active, absent }

/// An immutable, session-scoped set of values a notification job can use
/// without rereading mutable login globals.
///
/// [generation] increases on every state transition. Any asynchronous
/// continuation that wants to mutate current state must compare its snapshot
/// with [NotificationSessionCoordinator.isCurrent] after every await.
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

  /// The staff auth token captured for relay-key resolution. Empty for a
  /// patient session.
  final String authToken;

  /// The staff email captured alongside [authToken]. Empty for a patient.
  final String email;

  /// The PocketBase connection the staff session was activated with. Null for
  /// a patient session, which already carries [clinicKey] from its link.
  final PocketBase? pocketBase;

  /// The patient link's relay key, when this is a patient session.
  final String? clinicKey;

  bool get isPatient => kind == NotificationSessionKind.patient;

  bool get isUsable => server.isNotEmpty && accountId.isNotEmpty;
}

/// Owns the notification-session boundary: restoring, active or absent.
///
/// The service deliberately does not wait on `login.ready` from inside an
/// activation; that would wait on itself. Instead the login and patient-side
/// services publish the boundary after their activation work is complete, and
/// [invalidate] resolves every waiter as absent on logout or a failed restore.
class NotificationSessionCoordinator {
  NotificationSessionCoordinator({
    this.waitTimeout = const Duration(seconds: 60),
  });

  /// Upper bound for a push or toast click waiting for a session. A hidden
  /// process is already bounded natively; this keeps a malformed/blocked
  /// restore from leaving a Dart waiter pending forever.
  final Duration waitTimeout;

  final List<void Function()> _listeners = [];
  final List<_SessionWaiter> _waiters = [];

  NotificationSessionPhase _phase = NotificationSessionPhase.restoring;
  NotificationSessionSnapshot? _active;
  int _generation = 0;
  bool _disposed = false;

  NotificationSessionPhase get phase => _phase;

  /// Monotonic transition counter, used by callers that schedule a delayed
  /// "no session" resolution and must not overwrite a newer activation.
  int get revision => _generation;

  NotificationSessionSnapshot? get active => _active;

  /// Marks the beginning of a restore or a new activation. Any previous
  /// snapshot stops being current immediately, without resolving waiters: the
  /// new activation will either publish or mark the state absent.
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

  /// No stored session, a failed restore, or a logout. Waiters complete with
  /// null instead of hanging until a native deadline.
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

  /// Completes with the active snapshot, or null when the app is logged out,
  /// the restore failed, or [waitTimeout] elapsed.
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
        // A listener is an observer; it must not break the state transition
        // that another listener (or a waiter) depends on.
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
