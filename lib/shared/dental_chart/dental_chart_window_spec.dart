import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/shared/dental_chart/dental_chart_body.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The id the chart has wherever it is named: the panel's window, the enum each
/// record type offers, and the opener that shows it on its own.
const String kDentalChartWindowId = 'dentalChart';

/// The width the chart asks for. It is wider than a panel because the arches
/// need the room; a floating window never takes more than the screen has.
const double kDentalChartWindowWidth = 960.0;

/// What the chart is called on a **record's** panel: the patient's own teeth,
/// everything recorded on them and what is planned for them.
const String kDentalChartTitleKey = 'dentalChart';

/// What the same chart is called on a **visit's** panel, where it edits the
/// treatments given at that visit rather than the record's own teeth — the same
/// window, at a different scope, so it must not carry the same name.
const String kTreatmentsTitleKey = 'treatments';

/// The dental chart as a window.
///
/// Inside a panel it edits the panel's own copy and saves with the panel, so it
/// has no Save or Close of its own. Opened with no panel behind it
/// (`openPatientDentalChart`), the same window is shown by [WindowsManager] and
/// carries exactly the buttons a panel would have provided.
///
/// The name comes from the session ([DentalChartSession.titleKey]) rather than
/// from the caller: the session is the one thing that knows whether these teeth
/// are a record's or a visit's, so no host can label the chart as the wrong one.
PanelWindow dentalChartWindow(DentalChartSession session) => PanelWindow(
      id: kDentalChartWindowId,
      title: session.titleKey,
      icon: FluentIcons.teeth,
      subtitle: () => session.subtitle(),
      // Wider than the panel: the arches need the room, and the window is not a
      // column of the panel but the chart itself.
      matchesPanelWidth: false,
      preferredWidth: kDentalChartWindowWidth,
      maxHeight: 720,
      // The chart draws to whatever height it is given, but below this the
      // arches and the legend no longer fit and the window starts to scroll.
      // The grid will not put it in a shorter row.
      minHeight: 520,
      // The chart writes the record's teeth, so it carries the record's Save.
      editsRecord: true,
      padding: 8,
      body: DentalChartBody(session: session),
      footer: session.footer?.call(session),
    );

/// Shows [session]'s chart on its own — the window a panel would have held, with
/// the Save and Close a panel would have offered.
///
/// The chart of another record opens beside the ones already up rather than
/// replacing them: a window keeps its draft until it is saved or closed.
void showDentalChartWindow(
  DentalChartSession session, {
  Future<void> Function()? onOpenRecord,
}) {
  WindowsManager.showStandalone(
    dentalChartWindow(session),
    scope: session.id,
    // `save` rather than the write it wraps: a saved chart is a clean one.
    onSave: session.save,
    hasChanges: () => session.hasChanges,
    // A panel of the same record takes the teeth with it when it opens.
    transfer: session.mergeInto,
    onOpenRecord: onOpenRecord,
  );
}
