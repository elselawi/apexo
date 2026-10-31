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

/// The chart's own height floor: the arches, the legend and the scope bar fit
/// above this, and below it the chart would have to scroll.
///
/// It is the *body's* floor. A chart that carries a footer — a visit's post-op
/// record sits under its chart — asks for [kDentalChartWindowMinHeight] to keep
/// the arches their room.
const double kDentalChartBodyMinHeight = 520.0;

/// The height a visit's chart asks for: the arches, plus a first look at the
/// post-op record pinned under them.
///
/// It is what the row is *told* the chart needs, so a screen that cannot give a
/// visit's chart this much does not offer it at all. It is deliberately close to
/// [kDentalChartBodyMinHeight] rather than the whole chart with a full post-op
/// record: a laptop window at 125 % scaling is about 600 logical pixels tall, and
/// a visit opened there must still show its own chart. A short post-op record
/// then scrolls inside itself, which is the card's own job.
const double kDentalChartWindowMinHeight = 560.0;

/// How tall a visit's chart may grow: enough for the arches and a long post-op
/// note, never a wall that only fits a whole screen.
const double kDentalChartWindowMaxHeight = 940.0;

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
///
/// [saveLabel] names the record the chart's Save writes, where it has one of its
/// own: a visit's chart says "Save visit", a patient's says "Save patient"
/// (plan §4.4).
///
/// [actions] are the buttons the chart draws beside its title — a visit's chart
/// puts the patient's whole list of visits there, so reaching the list does not
/// cost the chart its place in the row. [footer] replaces the session's own
/// footer, for a chart that carries more than teeth (a visit's post-op record).
/// [overlayFooter] floats that footer directly over the chart, without a
/// separate window-background strip around it.
/// [footerActions] are the record's own actions, drawn in the window's footer
/// beside its Save and Close — a visit's chart puts its delete there, because
/// the operative record it carries is what that delete is about.
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
      icon: FluentIcons.teeth,
      subtitle: () => session.subtitle(),
      // Wider than the panel: the arches need the room, and the window is not a
      // column of the panel but the chart itself.
      matchesPanelWidth: false,
      preferredWidth: kDentalChartWindowWidth,
      maxHeight: maxHeight,
      // The chart draws to whatever height it is given, but below this the
      // arches and the legend no longer fit and the window starts to scroll.
      // The grid will not put it in a shorter row.
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

/// Shows [session]'s chart on its own — the window a panel would have held, with
/// the Save and Close a panel would have offered.
///
/// Feature openers guard unsaved work before replacing another chart. The
/// low-level window factory itself never discards another record's draft.
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
