import 'dart:async';
import 'dart:convert';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/features/appointments/appointment_dental_chart.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_owner_line.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// One visit's **one** draft, for as long as the app session lasts.
///
/// A visit is not a panel: it is a session — a draft, a Save, an identity and a
/// close — that a patient panel may carry beside itself (plan §0). Every window
/// of the visit edits this draft, so two windows cannot disagree; and the
/// registry (`appointmentSessions`) guarantees one session per stored visit, so
/// two *openers* cannot disagree either.
///
/// The session is not a `Panel` and never becomes one: it owns no screen, no
/// dock and no header. What it owns is the record.
final class AppointmentSession implements HostedRecordSession {
  AppointmentSession._({
    required this.item,
    required this.chart,
    required Map<String, dynamic> baseline,
    void Function()? onDispose,
  })  : _baseline = _detached(baseline),
        _onDispose = onDispose;

  /// The session for [appointment] — the visit as it is stored **now**.
  ///
  /// The draft is taken from the store rather than from the caller's copy: a
  /// caller may hold a record it read before a sync moved it, and the one thing
  /// a fresh draft must not do is open over yesterday's version. The caller's
  /// record is the fallback for a visit that is not stored at all.
  factory AppointmentSession(
    Appointment appointment, {
    void Function()? onDispose,
  }) {
    final stored = appointments.get(appointment.id);
    final asOpened = _detached(stored?.toJson() ?? appointment.toJson());
    final draft = Appointment.fromJson(_detached(asOpened));
    late final AppointmentSession session;
    final chart = appointmentDentalChart(
      draft,
      // The chart writes the draft's teeth; its own Save is the visit's Save, so
      // a chart opened on its own writes this visit and nothing else.
      onSave: () => session.save(),
    );
    session = AppointmentSession._(
      item: draft,
      chart: chart,
      baseline: asOpened,
      onDispose: onDispose,
    );
    chart.setBaseline(
      teeth: draft.teeth,
      extraNotes: draft.teethExtraNotes,
    );
    return session;
  }

  /// The visit's draft: the one thing every window of this visit edits.
  final Appointment item;

  /// The visit's chart, owned here so a chart opened on its own writes this
  /// draft rather than a second copy of the visit, and so a save re-baselines it
  /// with everything else.
  final DentalChartSession chart;

  /// Called when this session is dropped for good — the registry forgets it.
  final void Function()? _onDispose;

  /// The windows this visit offers, built once: they edit [item], so a window
  /// rebuilt on every read would be a second editor of the same draft.
  @override
  late final List<PanelWindow> windows = appointmentSessionWindows(this);

  /// The visit as it was last written — the `asOpened` side of the delta write.
  ///
  /// Held as detached JSON rather than as a map of the draft's own sub-maps:
  /// `toJson` hands out live maps, and a baseline that shared them would follow
  /// every edit and never report one.
  Map<String, dynamic> _baseline;

  @override
  final ObservableState<bool> inProgress = ObservableState(false);

  @override
  final ObservableState<bool> hasUnsavedChanges = ObservableState(false);

  final Completer<void> _result = Completer<void>();

  String? _savedId;
  bool _disposed = false;

  /// The visit's id — the one record this session is about.
  @override
  String get itemId => item.id;

  /// The visit's stable scope, for windows and for work adopted from them.
  String get scope => 'appointment:${item.id}';

  /// Whose visit this is, and where it stands — what a band and an owner line
  /// say. Read on build, so a rescheduled visit relabels at once.
  @override
  String get displayTitle => appointmentOwnerLine(item);

  /// The record's kind, for the layout preferences: `appointment/attached`.
  @override
  String get singularName => 'appointment';

  /// The glyph that marks a visit wherever it is drawn.
  @override
  String get unicodeSymbol => '📅';

  /// The colour a visit's windows are drawn in, so a patient's windows and the
  /// visit's are told apart at a glance.
  @override
  Color? get accent => PanelAccents.appointment;

  /// The key the visit's Save wears: it names the record it writes.
  @override
  String get saveLabel => 'saveVisit';

  /// `Visit · 24/10/2026` — the band's own line. The panel already names the
  /// patient, so the band spends its line on the day the visit is for.
  @override
  String get bandLabel =>
      txt('visitOf').replaceAll('{date}', DF.allNumbers(item.date));

  /// The appointment's whole form, drawn inside the band: when, how long, whose
  /// and what was planned, without a window or a row slot of its own; then the
  /// visit's operative details as the band's own dock, which opens the chart
  /// those fields live at the foot of, so they are reachable without leaving the
  /// patient.
  ///
  /// The labwork order and the gallery are not dock chips: they hang off the band
  /// as attachments, and the post-op card inside the chart offers them again.
  @override
  Widget? get bandContent => Column(
        key: ValueKey('visit-form-${item.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppointmentBandDetails(
            item,
            key: ValueKey('visit-fields-${item.id}'),
            onEdited: refreshDirty,
          ),
          AppointmentBandDock(session: this),
        ],
      );

  /// Whether the visit is finished, read from the draft so the band flips at
  /// once — no save needed to see it (plan §8.1).
  @override
  bool get isDone => item.isDone;

  /// The band's own toggle, applied to the one draft through the same door every
  /// other local change uses (plan §8.1).
  @override
  void markDone(bool done) {
    item.isDone = done;
    refreshDirty();
  }

  @override
  bool get canArchive => login.perm(Perm.appointments).full;

  @override
  Future<void> setArchived(bool archived) async {
    if (!canArchive) throw StateError('Visit archive permission is required');
    if (archived) {
      appointments.archive(item.id);
    } else {
      appointments.unarchive(item.id);
    }
    item.archived = archived;
    // The archive write is the record's, not the draft's: only that field is
    // acknowledged, so unsaved text survives a restore.
    markFieldsSaved(const ['archived']);
  }

  /// A visit is created by the dialog that stores it, so a session is never a
  /// new record — but a session opened over a visit that is no longer stored is
  /// the one case where nothing can be written, and it says so.
  @override
  bool get isNew => appointments.get(item.id) == null;

  @override
  bool get isArchived =>
      item.archived == true || appointments.get(item.id)?.archived == true;

  /// The visit has a Save: it is the visit's own write, never the patient's.
  @override
  bool get showBottomControls => true;

  /// Whether the draft differs from what was last written — the visit's fields
  /// **and** its teeth, because the chart edits the same draft.
  @override
  bool get hasPendingEdits => _encode(item.toJson()) != _encode(_baseline);

  @override
  Future<void> get result => _result.future;

  /// The id this session last wrote, or null while it has written nothing.
  @override
  String? get savedId => _savedId;

  @override
  void refreshDirty() {
    final dirty = hasPendingEdits;
    if (hasUnsavedChanges() != dirty) hasUnsavedChanges(dirty);
  }

  /// Writes the **delta** of this draft against the visit as it is stored now.
  ///
  /// The store is re-read first: a sync, a calendar drag or another window may
  /// have written the visit since this session opened, and writing the whole
  /// draft back would undo that. Only the fields the user changed are written
  /// (see [mergeAppointmentJson]) — a stale draft can no longer revert a field
  /// it never touched.
  @override
  Future<void> save() async {
    if (inProgress()) return;
    inProgress(true);
    try {
      final stored = appointments.get(item.id);
      final json = stored == null
          ? _detached(item.toJson())
          : mergeAppointmentJson(
              item,
              asOpened: _baseline,
              into: stored.toJson(),
            );
      appointments.set(appointments.modeling(json));
      _savedId = item.id;
      markSaved();
    } finally {
      inProgress(false);
    }
  }

  /// Re-baselines the whole draft: a write that went through [save].
  @override
  void markSaved() {
    _baseline = _detached(item.toJson());
    chart.markSaved();
    refreshDirty();
  }

  /// Re-baselines only [fields]: a write that landed outside [save] — the
  /// gallery's photos, for instance — without acknowledging the rest of the
  /// draft.
  @override
  void markFieldsSaved(Iterable<String> fields) {
    final current = item.toJson();
    for (final field in fields) {
      if (current.containsKey(field)) {
        _baseline[field] = current[field];
      } else {
        _baseline.remove(field);
      }
    }
    _baseline = _detached(_baseline);
    refreshDirty();
  }

  /// Applies [mutate] to the draft and stores **exactly the fields it changed**,
  /// acknowledging those fields and nothing else.
  ///
  /// What a control outside the visit's windows needs (the visits list's
  /// checkbox, a calendar drag, a labwork toggle): the control reads the record
  /// from the store, so a change held only in the draft is a change the user
  /// cannot see — and one that is dropped if the panel closes before the visit's
  /// Save. The draft still takes the change, because the windows beside the
  /// control are editing that draft and must agree with it.
  ///
  /// Only the mutated fields are written: whatever else the draft holds unsaved —
  /// typed notes, teeth — is neither stored nor acknowledged, so it stays the
  /// user's until the visit's own Save.
  void writeThrough(void Function(Appointment appointment) mutate) {
    final before = _detached(item.toJson());
    mutate(item);
    final current = item.toJson();
    final changed = <String>[
      for (final key in {...before.keys, ...current.keys})
        if (_encode(before[key]) != _encode(current[key])) key,
    ];
    if (changed.isEmpty) return;
    final stored = appointments.get(item.id);
    // A visit that is not stored has nothing to write into: the draft is the
    // only copy, so it stays dirty rather than pretending to be written.
    if (stored == null) return;
    appointments.set(appointments.modeling(
      mergeAppointmentJson(item, asOpened: before, into: stored.toJson()),
    ));
    markFieldsSaved(changed);
  }

  /// Finishes this session for good: the registry dropped it, so nothing can
  /// attach it again. The draft is not written — disposing is not saving.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose?.call();
    if (!_result.isCompleted) _result.complete();
  }

  bool get isDisposed => _disposed;
}

/// [draft]'s work, written over [into] — the visit as it is stored now.
///
/// Only the fields that differ from [asOpened] are written: another window of
/// the same visit, a calendar drag or a sync may have saved the rest while this
/// draft was open, and writing the whole draft back would undo it. A field back
/// at the model's default is absent from `toJson`, so writing that back means
/// dropping the key.
///
/// The round-trips through JSON are not ceremony: `toJson` hands out the draft's
/// own maps, so the answer is detached from [draft] — it can be stored, or handed
/// to a panel as its item, without the two sharing state.
///
/// Called from exactly one place: [AppointmentSession.save].
Map<String, dynamic> mergeAppointmentJson(
  Appointment draft, {
  required Map<String, dynamic> asOpened,
  required Map<String, dynamic> into,
}) {
  final merged = _detached(into);
  final current = draft.toJson();
  for (final key in {...asOpened.keys, ...current.keys}) {
    if (_encode(current[key]) == _encode(asOpened[key])) continue;
    if (current.containsKey(key)) {
      merged[key] = current[key];
    } else {
      merged.remove(key);
    }
  }
  return _detached(merged);
}

/// A deep copy of [json], so nothing handed back shares a map with the draft it
/// came from.
Map<String, dynamic> _detached(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

/// Whether two JSON values are equal, in a way a draft can be compared to a
/// stored copy by: key order is not a difference, and neither is the order the
/// encoder happens to walk.
String _encode(Object? json) => jsonEncode(_canonical(json));

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = [for (final key in value.keys) key.toString()]..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _canonical(item)];
  }
  return value;
}
