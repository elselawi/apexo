import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Everything the floating dental chart needs to edit one record's teeth.
///
/// The maps are the **live draft**: a panel hands in its editing copy, so the
/// chart writes exactly what the panel's Save persists, and a chart opened on
/// its own owns a copy and supplies [onSave] instead — which is what lets it
/// answer [hasChanges] for its Close confirmation.
final class DentalChartSession {
  DentalChartSession({
    required this.id,
    required this.titleKey,
    required this.subtitle,
    required this.type,
    required this.teeth,
    required this.extraNotes,
    required this.history,
    required this.oldNotes,
    required this.historyTitle,
    this.showPrimary = false,
    this.onOpenAppointment,
    this.footer,
    this.onSave,
  })  : _savedTeeth = Map.of(teeth),
        _savedExtraNotes = Map.of(extraNotes);

  /// What the chart edits, e.g. `patient:<id>` or `appointment:<id>`.
  final String id;

  /// The window's label as a localization key — "Dental Chart" on a record,
  /// "Treatments" on a visit, because what the same chart writes differs. The
  /// host draws it, so a language switch relabels the chart while it is open.
  final String titleKey;

  /// The window's second line — whose chart this is, read on build so a renamed
  /// patient stays current. The window's *title* is the chart itself; this is
  /// the line under it that says which record it belongs to.
  final String Function() subtitle;

  final StateType type;

  /// The teeth being edited, and their free-text notes.
  final Map<String, String> teeth;
  final Map<String, String> extraNotes;

  /// Records to show beside the teeth, and everything known about the chart
  /// that is not in [teeth]. Both are read on build, because they come from
  /// stores that change while the window is open.
  final List<ToothHistory> Function() history;
  final Map<String, String> Function() oldNotes;

  /// The heading of the history beside the teeth (`toothHistory` or
  /// `toothAppointmentNotes`).
  final String historyTitle;

  final bool showPrimary;

  /// Opens an appointment listed in the tooth history.
  final ValueChanged<String>? onOpenAppointment;

  /// A footer the owner adds under the chart (the dictation button). Built
  /// lazily, and handed the session so it can report edits back to it.
  final Widget Function(DentalChartSession session)? footer;

  /// The standalone half — null only when a panel owns the draft and saves it.
  final Future<void> Function()? onSave;

  /// Bumped on every edit, so whatever is drawing the chart redraws too.
  final ObservableState<int> revision = ObservableState(0);

  /// What the chart looked like when it opened, and after its last save: the
  /// baseline [hasChanges] is measured against.
  Map<String, String> _savedTeeth;
  Map<String, String> _savedExtraNotes;

  bool get hasChanges =>
      !mapEquals(_savedTeeth, teeth) ||
      !mapEquals(_savedExtraNotes, extraNotes);

  /// Says an edit landed in [teeth] or [extraNotes].
  void changed() => revision(revision() + 1);

  /// This chart's work, written over [stored] — the record as it is stored now.
  ///
  /// The same two fields [onSave] writes, so a panel that adopts it opens dirty
  /// on exactly the work this window holds, and a visit's chart and a patient's
  /// chart can be adopted by the same code.
  Map<String, dynamic> mergeInto(Map<String, dynamic> stored) => {
        ...stored,
        'teeth': Map<String, String>.from(teeth),
        'teethExtraNotes': Map<String, String>.from(extraNotes),
      };

  /// Persists a standalone chart, then re-baselines [hasChanges]. A failed save
  /// leaves the session dirty and is rethrown to the window.
  Future<void> save() async {
    final save = onSave;
    if (save == null) return;
    await save();
    _savedTeeth = Map.of(teeth);
    _savedExtraNotes = Map.of(extraNotes);
    changed();
  }
}
