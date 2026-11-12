import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/shared/dental_chart/dental_chart_body.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:fluent_ui/fluent_ui.dart';

const String kDentalChartWindowId = 'dentalChart';

const double kDentalChartWindowWidth = 960.0;

/// Below this the arches and legend no longer fit and the chart scrolls.
const double kDentalChartBodyMinHeight = 520.0;

/// The height a visit's chart asks for, near [kDentalChartBodyMinHeight] because
/// a 125%-scaled laptop window is only ~600 logical pixels tall.
const double kDentalChartWindowMinHeight = 560.0;

/// How tall a visit's chart may grow: enough for the arches and a long post-op note.
const double kDentalChartWindowMaxHeight = 940.0;

/// The patient's chart is the initial exam; the window says so.
const String kDentalChartTitleKey = 'initialExamChart';

/// The patient's dock keeps the chart's familiar name.
const String kDentalChartDockTitleKey = 'dentalChart';

/// A visit edits that visit's treatments, so it needs its own title key.
const String kTreatmentsTitleKey = 'appointmentOperativeDetails';

/// The chart as a window. Its name comes from the session, not the caller, so a
/// record's chart and a visit's chart cannot be mislabelled.
PanelWindow dentalChartWindow(
  DentalChartSession session, {
  String? saveLabel,
  List<Widget> actions = const <Widget>[],
  List<Widget> footerActions = const <Widget>[],
  Widget? footer,
  bool overlayFooter = false,
  double minHeight = kDentalChartBodyMinHeight,
  double maxHeight = 720,
}) =>
    PanelWindow(
      id: kDentalChartWindowId,
      title: session.titleKey,
      dockTitle: session.dockTitleKey,
      icon: FluentIcons.teeth,
      subtitle: () => session.subtitle(),
      // Wider than the panel: the arches need the room.
      matchesPanelWidth: false,
      preferredWidth: kDentalChartWindowWidth,
      maxHeight: maxHeight,
      // Below this the arches and legend no longer fit and the window scrolls.
      minHeight: minHeight,
      // The chart writes the record's teeth, so it carries the record's Save.
      editsRecord: true,
      saveLabel: saveLabel,
      padding: 8,
      replacementGroup: kDentalChartWindowId,
      headerActions: actions,
      footerActions: footerActions,
      scrollable: !overlayFooter,
      body: DentalChartBody(
        key: ObjectKey(session),
        session: session,
        overlay: overlayFooter ? footer ?? session.footer?.call(session) : null,
      ),
      footer: overlayFooter ? null : footer ?? session.footer?.call(session),
    );

/// Shows [session]'s chart standalone. Callers must guard unsaved work: this
/// never discards another record's draft.
void showDentalChartWindow(
  DentalChartSession session, {
  Future<void> Function()? onOpenRecord,
  List<Widget> actions = const <Widget>[],
}) {
  WindowsManager.showStandalone(
    dentalChartWindow(session, actions: actions),
    scope: session.id,
    // `save` rather than the write it wraps: a saved chart is a clean one.
    onSave: session.save,
    hasChanges: () => session.hasChanges,
    // A panel of the same record takes the teeth with it when it opens.
    transfer: session.mergeInto,
    onOpenRecord: onOpenRecord,
  );
}
