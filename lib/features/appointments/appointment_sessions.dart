import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_session.dart';

/// The app's identity map for visits: one id, one session, one draft.
///
/// Two openers asking for the same visit get the same session — so two windows,
/// a calendar drag and an open pre-op form all edit one draft instead of racing
/// each other (plan §2.2, I2). The map lives for the app session and is cleared
/// on logout; a session is only dropped early when the panel that owns it says
/// so (`Panel.disposeSession`), never because a window closed.
final class AppointmentSessions {
  final Map<String, AppointmentSession> _sessions = <String, AppointmentSession>{};

  /// Emits whenever the set of live sessions changes — what a panel's attach and
  /// detach are observed through.
  final ObservableState<int> revision = ObservableState(0);

  /// The one session for [appointment], created from the store if this is the
  /// first time it is opened.
  ///
  /// A caller that already holds a draft — a panel attaching the visit it has
  /// open — must use [get] rather than this: creating is for opening a record,
  /// and it never replaces a session that still holds work.
  AppointmentSession getOrCreate(Appointment appointment) {
    final existing = _sessions[appointment.id];
    if (existing != null && !existing.isDisposed) return existing;
    late final AppointmentSession created;
    created = AppointmentSession(
      appointment,
      // Dropped by its owner (`Panel.disposeSession`) rather than by the
      // registry: the identity map is the registry's, and a session that is
      // finished is no longer a session anyone can attach.
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

  /// The live sessions whose draft differs from the store — the visits a close
  /// prompt has to name, whether or not their windows are on screen.
  List<AppointmentSession> get dirty =>
      [for (final session in _sessions.values) if (session.hasPendingEdits) session];

  /// Drops [id]'s session and its draft: the panel that owned it is finished
  /// with it. Disposing is not saving, and it does not prompt — the caller has
  /// already asked.
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
