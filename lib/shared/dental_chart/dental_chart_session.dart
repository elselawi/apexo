import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/reactive/observable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Edits one record's teeth; [teeth] and [extraNotes] are the live draft a
/// panel also saves, or the session's own copy when standalone with [onSave].
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
    this.header,
    this.footer,
    this.onSave,
  })  : _savedTeeth = Map.of(teeth),
        _savedExtraNotes = Map.of(extraNotes);

  /// What the chart edits, e.g. `patient:<id>` or `appointment:<id>`.
  final String id;

  /// Logical direction for the chart content's scope transition; chrome stays still.
  int navigationDirection = 0;

  /// Localization key for the window label; the host resolves it on build, so a
  /// language switch relabels an open chart.
  final String titleKey;

  /// The window's second line: whose chart this is, read on build so a rename
  /// stays current.
  final String Function() subtitle;

  final StateType type;

  /// The teeth being edited, and their free-text notes.
  final Map<String, String> teeth;
  final Map<String, String> extraNotes;

  /// Both read on build, because their stores change while the window is open.
  final List<ToothHistory> Function() history;
  final Map<String, String> Function() oldNotes;

  final String historyTitle;

  final bool showPrimary;

  /// Opens an appointment listed in the tooth history.
  final ValueChanged<String>? onOpenAppointment;

  final Widget Function(DentalChartSession session)? header;

  final Widget Function(DentalChartSession session)? footer;

  /// The standalone half — null only when a panel owns the draft and saves it.
  final Future<void> Function()? onSave;

  /// Bumped on every edit, so whatever is drawing the chart redraws too.
  final ObservableState<int> revision = ObservableState(0);

  /// Baseline for [hasChanges]: the draft as opened and after the last save.
  Map<String, String> _savedTeeth;
  Map<String, String> _savedExtraNotes;

  bool get hasChanges =>
      !mapEquals(_savedTeeth, teeth) ||
      !mapEquals(_savedExtraNotes, extraNotes);

  /// Says an edit landed in [teeth] or [extraNotes].
  void changed() => revision(revision() + 1);

  /// Writes this chart's work over [stored] using the same two fields [onSave]
  /// persists, so a panel can adopt it and open dirty.
  Map<String, dynamic> mergeInto(Map<String, dynamic> stored) => {
        ...stored,
        'teeth': Map<String, String>.from(teeth),
        'teethExtraNotes': Map<String, String>.from(extraNotes),
      };

  /// Re-baselines [hasChanges], e.g. when a panel adopts a standalone window's work.
  void setBaseline({
    required Map<String, String> teeth,
    required Map<String, String> extraNotes,
  }) {
    _savedTeeth = Map.of(teeth);
    _savedExtraNotes = Map.of(extraNotes);
  }

  /// Re-baselines [hasChanges] to the current [teeth] and [extraNotes].
  void markSaved() {
    _savedTeeth = Map.of(teeth);
    _savedExtraNotes = Map.of(extraNotes);
    changed();
  }

  /// Reverts [teeth] and [extraNotes] back to the last saved baseline.
  void discardChanges() {
    teeth
      ..clear()
      ..addAll(_savedTeeth);
    extraNotes
      ..clear()
      ..addAll(_savedExtraNotes);
    changed();
  }

  /// Saves a standalone chart, then re-baselines. A failed save leaves the
  /// session dirty and rethrows.
  Future<void> save() async {
    final save = onSave;
    if (save == null) return;
    await save();
    markSaved();
  }
}
