import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_session.dart';

/// One session, and so one draft, per visit id: every opener gets the same one.
/// Dropped only by the panel that owns it, never by a closed window.
final class AppointmentSessions {
  final Map<String, AppointmentSession> _sessions = <String, AppointmentSession>{};

  /// Emits whenever a session is added or dropped.
  final ObservableState<int> revision = ObservableState(0);

  /// The one session for [appointment], created on first open. A caller that
  /// already holds a draft must use [get]: an existing session is never replaced.
  AppointmentSession getOrCreate(Appointment appointment) {
    final existing = _sessions[appointment.id];
    if (existing != null && !existing.isDisposed) return existing;
    late final AppointmentSession created;
    created = AppointmentSession(
      appointment,
      onDispose: () {
        if (identical(_sessions[appointment.id], created)) {
          _sessions.remove(appointment.id);
          revision(revision() + 1);
        }
      },
    );
    _sessions[appointment.id] = created;
    revision(revision() + 1);
    return created;
  }

  /// The session open for [id], if any.
  AppointmentSession? get(String id) => _sessions[id];

  bool isOpen(String id) => _sessions.containsKey(id);

  /// Every live session, in the order they were opened.
  List<AppointmentSession> get live =>
      List<AppointmentSession>.unmodifiable(_sessions.values);

  /// Sessions with unsaved work, on screen or not — what the close prompt names.
  List<AppointmentSession> get dirty =>
      [for (final session in _sessions.values) if (session.hasPendingEdits) session];

  /// Drops [id]'s session: no save and no prompt — the caller has already asked.
  void dispose(String id) {
    final session = _sessions.remove(id);
    if (session == null) return;
    session.dispose();
    revision(revision() + 1);
  }

  /// Forced teardown — logout. No prompt: there is no screen left to ask on.
  void clear() {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      session.dispose();
    }
    revision(revision() + 1);
  }
}

/// The app's one registry of visit sessions.
final appointmentSessions = AppointmentSessions();
