import 'dart:async';
import 'dart:math' as math;

import 'package:apexo/app/app_context.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_session.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/follow_up_scope_dot.dart';
import 'package:apexo/features/appointments/new_appointment_dialog.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show DF, currency, globalSettings;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/shared/dental_chart/dental_chart_body.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:apexo/ui/workspace/unsaved_dot.dart';
import 'package:apexo/ui/workspace/window_close_button.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/window_origin.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/utils/color_based_on_payment.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Pauses the ring that radiates from the record the chart has open.
///
/// The ring repeats for as long as the record stays open, which never lets a
/// widget test settle; [pumpApexoApp] turns it off unless a test asks for it.
@visibleForTesting
bool debugPauseScopeRipple = false;

DentalChartSession? _sessionIn(Widget body) =>
    body is DentalChartBody ? body.session : null;

/// The app's context, when there is one: a test drives these openers with no app
/// shell, and asking an uninitialized global would throw.
BuildContext? get _appContextForPrompt {
  try {
    return bContext;
  } catch (_) {
    return null;
  }
}

/// The chart a record's session owns, if the kind has one at all.
DentalChartSession? _chartOf(HostedRecordSession session) =>
    session is AppointmentSession ? session.chart : null;

/// The chart of the record [scope] names, whether it is a patient's panel, a
/// visit attached to one, or a chart standing on its own.
DentalChartSession? panelDentalChart(String scope) {
  for (final panel in PanelsManager.active()) {
    // A visit's chart belongs to the visit's session, and the panel that carries
    // the visit is the panel that draws it (plan §4.3).
    final attached = panel.attached;
    if (attached != null &&
        '${attached.singularName}:${attached.itemId}' == scope) {
      return _chartOf(attached);
    }
    if ('${panel.singularName}:${panel.itemId}' != scope) continue;
    for (final window in panel.floatingWindows) {
      if (window.id == kDentalChartWindowId) return _sessionIn(window.body);
    }
  }
  return null;
}

/// A borrowed editor already writes its panel's draft, so returning it to that
/// panel is not a discard or a second adoption of the same work.
void closeBorrowedDentalChart(String scope) {
  final hosted = panelDentalChart(scope);
  if (hosted == null) return;
  for (final floating in WindowsManager.open()) {
    if (floating.scope == scope &&
        identical(_sessionIn(floating.window.body), hosted)) {
      WindowsManager.close(floating);
    }
  }
}

DentalChartSession? get _visibleChart {
  for (final floating in WindowsManager.open().reversed) {
    if (floating.window.id == kDentalChartWindowId) {
      return _sessionIn(floating.window.body);
    }
  }
  final panel = PanelsManager.active().lastOrNull;
  if (panel == null) return null;
  final attached = panel.attached;
  if (attached != null) {
    // One chart on screen: while a visit is attached its chart *is* the chart,
    // and a patient chart the row is not drawing is not the one the user sees.
    return panel.workspace.isOpen(kDentalChartWindowId, slot: kAttachedSlot)
        ? _chartOf(attached)
        : null;
  }
  if (!panel.workspace.isOpen(kDentalChartWindowId)) return null;
  return panelDentalChart('${panel.singularName}:${panel.itemId}');
}

/// The chart whose work leaving would throw away: one standing on its own, or
/// the chart a panel draws for its own record.
///
/// A visit's chart is deliberately absent. The visit keeps its draft — teeth,
/// operative details and the band's fields alike — when another visit takes the
/// row, so leaving it is not a discard and must not ask; the band already says
/// which visits still hold work (see [AppointmentSession.hasPendingEdits]).
DentalChartSession? get _discardableChart {
  for (final floating in WindowsManager.open().reversed) {
    if (floating.window.id == kDentalChartWindowId) {
      return _sessionIn(floating.window.body);
    }
  }
  final panel = PanelsManager.active().lastOrNull;
  if (panel == null || panel.attached != null) return null;
  if (!panel.workspace.isOpen(kDentalChartWindowId)) return null;
  return panelDentalChart('${panel.singularName}:${panel.itemId}');
}

/// Logical tab direction: plan, then visits from newest to oldest.
int dentalChartNavigationDirection(String targetScope) {
  final source = _visibleChart?.id;
  if (source == null || source == targetScope) return 0;
  String? patientId(String scope) => scope.startsWith('patient:')
      ? scope.substring('patient:'.length)
      : appointments.get(scope.substring('appointment:'.length))?.patientID;
  if (patientId(source) != patientId(targetScope)) return 0;
  if (source.startsWith('patient:')) return 1;
  if (targetScope.startsWith('patient:')) return -1;
  final from = appointments.get(source.substring('appointment:'.length));
  final to = appointments.get(targetScope.substring('appointment:'.length));
  if (from == null || to == null) return 0;
  final byDate = from.date.compareTo(to.date);
  return (byDate == 0 ? to.id.compareTo(from.id) : byDate).sign;
}

bool _closingCharts = false;

/// All entry points (including history and the dock) use the same dirty guard.
/// Hidden panels keep their drafts; only a chart that is not held by a record
/// that outlives it — see [_discardableChart] — is reset.
Future<bool> closeOpenDentalChartWindows({
  required String exceptScope,
  BuildContext? context,
  int direction = 0,
}) async {
  if (_closingCharts) return false;
  _closingCharts = true;
  try {
    final floating = WindowsManager.open()
        .where((w) =>
            w.window.id == kDentalChartWindowId && w.scope != exceptScope)
        .toList();
    final visible = _discardableChart;
    final dirty = <DentalChartSession>{
      for (final window in floating)
        if (_sessionIn(window.window.body) case final session?)
          if (session.hasChanges) session,
      if (visible != null && visible.id != exceptScope && visible.hasChanges)
        visible,
    };
    if (dirty.isNotEmpty ||
        floating.any((w) => w.hasChanges?.call() ?? false)) {
      // No context means nobody to ask — a test, or a caller with no screen.
      // Then the answer is no: work is never discarded silently.
      final promptContext = context ?? _appContextForPrompt;
      if (promptContext == null ||
          !promptContext.mounted ||
          !await confirmDiscardFloatingWindow(promptContext)) {
        return false;
      }
      if (!promptContext.mounted) return false;
      for (final session in dirty) {
        session.discardChanges();
      }
    }
    for (final window in floating) {
      _sessionIn(window.window.body)?.navigationDirection = -direction;
      WindowsManager.close(window);
    }
    for (final panel in PanelsManager.active()) {
      final scope = '${panel.singularName}:${panel.itemId}';
      if (scope != exceptScope) {
        panelDentalChart(scope)?.navigationDirection = -direction;
        panel.workspace.hide(kDentalChartWindowId);
      }
      // A visit's chart is a window of the visit, so leaving it means taking it
      // out of the visit's slot — the draft it edits stays in the session.
      final attached = panel.attached;
      if (attached != null &&
          '${attached.singularName}:${attached.itemId}' != exceptScope) {
        _chartOf(attached)?.navigationDirection = -direction;
        panel.workspace.hide(kDentalChartWindowId, slot: kAttachedSlot);
      }
    }
    return true;
  } finally {
    _closingCharts = false;
  }
}

/// Opens the dental chart for the visit [id] from a tooth's history.
void openAppointmentChartFromHistory(String id) {
  final appointment = appointments.get(id);
  if (appointment == null) return;
  WindowOrigin.clear();
  unawaited(openAppointmentDentalChart(appointment));
}

/// A fixed-height scope strip above the arches: the plan stays pinned while
/// appointments are laid out along a horizontal timeline where the first dot is
/// the first appointment, the last dot is the last appointment, and the
/// distances between dots reflect the time duration between appointments.
///
/// Hovering any dot displays a rich clinical preview card (date, interval,
/// treatments, notes, prescriptions, labwork, doctors, price and payment
/// status). When the number of visits fits within the bar, no scrolling is
/// needed; when the number of visits grows too large, the timeline scrolls and
/// displays a smooth edge transparency fade indicating additional visits.
/// Drag anywhere on the track to preview the nearest visit with selection
/// haptics; release to open it through the usual unsaved-work guard. Holding
/// near an edge scrolls through longer histories. Arrow keys and Home/End
/// preview visits, Enter opens the preview, and Escape cancels. Accessibility
/// adjustment actions select visits directly.
class VisitScopeBar extends StatefulWidget {
  const VisitScopeBar({
    super.key,
    required this.patient,
    required this.session,
    this.currentAppointment,
  });

  final Patient patient;
  final DentalChartSession session;
  final Appointment? currentAppointment;

  @override
  State<VisitScopeBar> createState() => _VisitScopeBarState();
}

class _VisitScopeBarState extends State<VisitScopeBar> {
  final _scroll = ScrollController();
  final _visitKeys = <String, GlobalKey>{};
  bool _switching = false;
  String? _revealed;
  double? _width;
  String? _hoveredVisitId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScrollChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    if (mounted) setState(() {});
  }

  /// Appointments ordered chronologically from first (oldest) to last (newest).
  List<Appointment> _visitsFor(Patient currentPatient) {
    final byId = <String, Appointment>{
      for (final visit in currentPatient.allAppointments) visit.id: visit,
    };
    final current = widget.currentAppointment;
    if (current != null) byId[current.id] = current;
    return byId.values.toList()
      ..sort((a, b) {
        final date = a.date.compareTo(b.date);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
  }

  Future<void> _selectScope(
      String targetScope, Future<void> Function() open) async {
    if (_switching || widget.session.id == targetScope) return;
    setState(() {
      _switching = true;
      _hoveredVisitId = null;
    });
    try {
      WindowOrigin.clear();
      await open();
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// Starts a visit for this patient and puts it in the chart.
  ///
  /// The new visit is the one the user came for, so it becomes the selected
  /// scope: the same call an opener makes from the calendar, with the patient
  /// and the day already known (the design brief). Only the day is carried
  /// over — a new visit at the current visit's exact hour would be a second
  /// booking of the same slot.
  Future<void> _addVisit(BuildContext context) async {
    final current = widget.currentAppointment?.date;
    final created = await addAppointment(
      context,
      day: current == null
          ? null
          : DateTime(current.year, current.month, current.day),
      patientID: widget.patient.id,
    );
    if (created == null || !mounted) return;
    await openAppointment(created, AppointmentWindow.dentalChart);
  }

  void _revealSelected(List<Appointment> visits, double width) {
    final signature =
        '${widget.session.id}:${visits.map((v) => v.id).join(',')}';
    if (_revealed == signature && _width == width) return;
    _revealed = signature;
    _width = width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = widget.currentAppointment?.id;
      final tabContext = _visitKeys[id]?.currentContext;
      if (tabContext == null) return;
      // Only the timeline strip scrolls, never the chart's outer vertical scroller.
      final position =
          Scrollable.of(tabContext, axis: Axis.horizontal).position;
      position.ensureVisible(tabContext.findRenderObject()!, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [
        patients.observableMap.stream,
        appointments.observableMap.stream,
        globalSettings.observableMap.stream,
        locale.selected.stream,
      ],
      builder: (context, _) {
        final patient = patients.get(widget.patient.id) ?? widget.patient;
        final visits = _visitsFor(patient);
        _visitKeys.removeWhere((id, _) => !visits.any((v) => v.id == id));
        for (final visit in visits) {
          _visitKeys.putIfAbsent(visit.id, () => GlobalKey());
        }
        final planScope = 'patient:${patient.id}';
        final index = visits
            .indexWhere((v) => 'appointment:${v.id}' == widget.session.id);
        void openVisit(int i) {
          final visit = visits[i];
          // One control for the selection: the same call the Visits list makes,
          // so the chart's scope bar and the list can never disagree (§4.8).
          // The context lets the dirty guard ask over the chart being left.
          unawaited(_selectScope(
              'appointment:${visit.id}',
              () => selectVisit(patient.id, visit.id,
                  focus: kDentalChartWindowId, context: context)));
        }

        final theme = FluentTheme.of(context);
        // The one promise on this bar that is not a visit yet: the day the
        // patient was asked to come back, drawn past the newest dot.
        final followUp = followUpsEnabled ? patientFollowUpDay(patient.id) : null;
        // With no visits there is no timeline beside it, so the button can
        // afford its whole name instead of the short "new".
        final addLabel = visits.isEmpty ? txt('addAppointment') : txt('new');
        return SizedBox(
          height: 40,
          child: LayoutBuilder(builder: (context, constraints) {
            _revealSelected(visits, constraints.maxWidth);
            return Row(
              children: [
                SizedBox(
                  width: (constraints.maxWidth * 0.3).clamp(70.0, 156.0),
                  child: _InitialExamStop(
                    key: ValueKey('scope-$planScope'),
                    label: txt('initialExam'),
                    selected: widget.session.id == planScope,
                    onPressed: _switching
                        ? null
                        : () => unawaited(_selectScope(
                            planScope,
                            () => showPatientChart(patient.id,
                                context: context))),
                  ),
                ),
                if (visits.isEmpty)
                  const Expanded(
                    child: _InitialExamTrack(
                        key: ValueKey('scope-empty-track'), fade: true),
                  )
                else ...[
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, timelineConstraints) {
                        final viewportWidth = timelineConstraints.maxWidth;
                        final layout = computeTimelineLayout(
                          visits: visits,
                          viewportWidth: viewportWidth,
                        );
                        final maxExtent =
                            math.max(0.0, layout.trackWidth - viewportWidth);
                        final offset = _scroll.hasClients
                            ? _scroll.offset.clamp(0.0, maxExtent)
                            : 0.0;
                        // With `reverse: true`, offset 0 is anchored at the
                        // trailing (newest) end and maxExtent is at the leading
                        // (oldest) start.
                        final canScrollStart =
                            layout.overflows && offset < maxExtent - 1.0;
                        final canScrollEnd = layout.overflows && offset > 1.0;

                        return _VisitTimelineSlider(
                          key: ValueKey(patient.id),
                          visits: visits,
                          layout: layout,
                          selectedIndex: index,
                          hoveredVisitId: _hoveredVisitId,
                          visitKeys: _visitKeys,
                          switching: _switching,
                          scroll: _scroll,
                          fadeStart: canScrollStart,
                          fadeEnd: canScrollEnd,
                          onSelectVisit: openVisit,
                          onHoverVisit: (visitId) {
                            if (_hoveredVisitId != visitId) {
                              setState(() => _hoveredVisitId = visitId);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
                // The follow-up sits at the leading end of the bar — past the
                // newest visit, where the patient's history stops and their
                // future starts. It is not a visit: it is larger, it wears the
                // phone, and it opens contact details rather than a chart.
                if (followUp != null)
                  FollowUpScopeDot(
                    key: WK.chartFollowUpDot,
                    patient: patient,
                    date: followUp,
                    onBook: login.perm(Perm.appointments).some
                        ? () async {
                            final created = await addAppointment(
                              context,
                              day: followUpBookingDay(followUp),
                              patientID: patient.id,
                              initialPreOpNotes: patient.followUpNote,
                            );
                            if (created == null || !mounted) return;
                            await openAppointment(
                                created, AppointmentWindow.dentalChart);
                          }
                        : null,
                  ),
                // A visit is started from the record it belongs to: one button
                // beside the visits it will join, not a trip back to the calendar
                // and a new dialog with the patient typed in again. The space
                // the chronological arrows used to take now carries its word.
                if (login.perm(Perm.appointments).some)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: Tooltip(
                      message: txt('addAppointment'),
                      child: ConstrainedBox(
                        // A long locale on a narrow window ellipsizes instead of
                        // pushing the initial exam or the timeline off the bar.
                        constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.6),
                        child: Button(
                          key: WK.chartAddAppointment,
                          style: ButtonStyle(
                            padding: const WidgetStatePropertyAll(
                                EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8)),
                            textStyle: WidgetStatePropertyAll(
                                theme.typography.caption?.copyWith(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          onPressed:
                              _switching ? null : () => _addVisit(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FluentIcons.add, size: 12),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Txt(addLabel,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        );
      },
    );
  }
}

/// Geometry of the horizontal appointment timeline.
final class TimelineLayout {
  const TimelineLayout({
    required this.trackWidth,
    required this.positions,
    required this.overflows,
  });

  /// Total width of the timeline canvas. Equals `viewportWidth` unless the
  /// number of visits exceeds what fits at minimum dot spacing.
  final double trackWidth;

  /// Horizontal center coordinate of each visit dot (from start edge), ordered
  /// chronologically from first appointment (`0`) to last appointment (`N-1`).
  final List<double> positions;

  /// True only when the number of visits is too large to fit without scrolling.
  final bool overflows;
}

/// Computes duration-proportional horizontal positions for [visits] (sorted
/// oldest-first).
///
/// The first dot sits at the start of the horizontal line and the last dot sits
/// at the end of the line. Intervals between consecutive dots are scaled in
/// proportion to the time duration between those appointments, while preserving
/// a minimum collision-free gap so same-day or back-to-back appointments stay
/// distinct and clickable.
TimelineLayout computeTimelineLayout({
  required List<Appointment> visits,
  required double viewportWidth,
}) {
  const edgeInset = 18.0;
  const minDotSpacing = 26.0;
  final safeViewport = math.max(viewportWidth, 2 * edgeInset);

  if (visits.isEmpty) {
    return TimelineLayout(
      trackWidth: safeViewport,
      positions: const [],
      overflows: false,
    );
  }

  if (visits.length == 1) {
    return TimelineLayout(
      trackWidth: safeViewport,
      positions: [safeViewport / 2],
      overflows: false,
    );
  }

  final n = visits.length;
  final intervals = n - 1;
  final deltas = <double>[
    for (var i = 0; i < intervals; i++)
      math.max(
        0.0,
        visits[i + 1].date.difference(visits[i].date).inMinutes.toDouble(),
      ),
  ];

  final sumLinear = deltas.fold<double>(0.0, (a, b) => a + b);
  final sumSqrt = deltas.fold<double>(0.0, (a, b) => a + math.sqrt(b));

  final weights = <double>[
    if (sumLinear <= 0)
      for (var i = 0; i < intervals; i++) 1.0 / intervals
    else
      for (final d in deltas)
        0.70 * (d / sumLinear) + 0.30 * (math.sqrt(d) / sumSqrt),
  ];

  final effectiveEdge = math.min(edgeInset, safeViewport * 0.18);
  final minRequiredWidth = 2 * effectiveEdge + intervals * minDotSpacing;
  final overflows = minRequiredWidth > safeViewport + 0.5;

  final double trackWidth;
  final List<double> gaps;

  if (!overflows) {
    trackWidth = safeViewport;
    final usableSpan = math.max(0.0, trackWidth - 2 * effectiveEdge);
    if (intervals == 1) {
      gaps = [usableSpan];
    } else {
      final floorGap =
          math.min(minDotSpacing * 0.65, usableSpan / (intervals * 1.6));
      final proportionalPool = math.max(0.0, usableSpan - intervals * floorGap);
      gaps = [
        for (final w in weights) floorGap + proportionalPool * w,
      ];
    }
  } else {
    final extraPool = intervals * 12.0;
    gaps = [
      for (final w in weights) minDotSpacing + extraPool * w,
    ];
    trackWidth = 2 * effectiveEdge + gaps.fold<double>(0.0, (a, b) => a + b);
  }

  final positions = <double>[effectiveEdge];
  var cursor = effectiveEdge;
  for (var i = 0; i < gaps.length; i++) {
    cursor += gaps[i];
    positions.add(cursor);
  }
  if (!overflows && positions.length >= 2) {
    positions[positions.length - 1] = trackWidth - effectiveEdge;
  }

  return TimelineLayout(
    trackWidth: trackWidth,
    positions: positions,
    overflows: overflows,
  );
}

/// Applies a horizontal transparency gradient mask at the start and/or end
/// edges when the timeline overflows and has more visits to scroll to.
class _EdgeTransparencyFade extends StatelessWidget {
  const _EdgeTransparencyFade({
    super.key,
    required this.fadeStart,
    required this.fadeEnd,
    required this.child,
  });

  final bool fadeStart;
  final bool fadeEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!fadeStart && !fadeEnd) return child;
    final direction = Directionality.of(context);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final width = bounds.width;
        final stop = width > 0 ? (28.0 / width).clamp(0.04, 0.22) : 0.12;
        return LinearGradient(
          begin: AlignmentDirectional.centerStart.resolve(direction),
          end: AlignmentDirectional.centerEnd.resolve(direction),
          colors: [
            fadeStart ? Colors.transparent : Colors.white,
            Colors.white,
            Colors.white,
            fadeEnd ? Colors.transparent : Colors.white,
          ],
          stops: [
            0.0,
            fadeStart ? stop : 0.0,
            fadeEnd ? 1.0 - stop : 1.0,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

/// Scrubbing previews a snapped visit without opening charts or prompting for
/// unsaved work until release. The existing dots double as the slider thumb.
class _VisitTimelineSlider extends StatefulWidget {
  const _VisitTimelineSlider({
    super.key,
    required this.visits,
    required this.layout,
    required this.selectedIndex,
    required this.hoveredVisitId,
    required this.visitKeys,
    required this.switching,
    required this.scroll,
    required this.fadeStart,
    required this.fadeEnd,
    required this.onSelectVisit,
    required this.onHoverVisit,
  });

  final List<Appointment> visits;
  final TimelineLayout layout;
  final int selectedIndex;
  final String? hoveredVisitId;
  final Map<String, GlobalKey> visitKeys;
  final bool switching;
  final ScrollController scroll;
  final bool fadeStart;
  final bool fadeEnd;
  final ValueChanged<int> onSelectVisit;
  final ValueChanged<String?> onHoverVisit;

  @override
  State<_VisitTimelineSlider> createState() => _VisitTimelineSliderState();
}

class _VisitTimelineSliderState extends State<_VisitTimelineSlider> {
  final _canvasKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _focus = FocusNode();
  Timer? _edgeScroll;
  Offset? _pointer;
  String? _previewId;

  bool get _scrubbing => _pointer != null;
  int get _previewIndex => _previewId == null
      ? widget.selectedIndex
      : widget.visits.indexWhere((v) => v.id == _previewId);

  @override
  void didUpdateWidget(covariant _VisitTimelineSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_previewId != null &&
        (widget.switching ||
            widget.selectedIndex != oldWidget.selectedIndex ||
            _previewIndex < 0)) {
      _edgeScroll?.cancel();
      _pointer = null;
      _previewId = null;
    }
  }

  @override
  void dispose() {
    _edgeScroll?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _previewAt(Offset position) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || widget.visits.isEmpty) return;
    final localX = box.globalToLocal(position).dx;
    final x = Directionality.of(context) == TextDirection.rtl
        ? box.size.width - localX
        : localX;
    var nearest = 0;
    for (var i = 1; i < widget.layout.positions.length; i++) {
      if ((widget.layout.positions[i] - x).abs() <
          (widget.layout.positions[nearest] - x).abs()) {
        nearest = i;
      }
    }
    _preview(nearest);
  }

  void _preview(int index) {
    final id = widget.visits[index].id;
    if (id == _previewId) return;
    final changed = index != _previewIndex;
    setState(() => _previewId = id);
    if (changed) unawaited(HapticFeedback.selectionClick());
  }

  void _keyboardPreview(int index) {
    if (widget.switching || _scrubbing || widget.visits.isEmpty) return;
    final target = index.clamp(0, widget.visits.length - 1);
    widget.onHoverVisit(null);
    _preview(target);
    final dotContext =
        widget.visitKeys[widget.visits[target].id]?.currentContext;
    if (dotContext != null) {
      Scrollable.of(dotContext, axis: Axis.horizontal)
          .position
          .ensureVisible(dotContext.findRenderObject()!, alignment: 0.5);
    }
  }

  void _start(DragStartDetails details) {
    _focus.requestFocus();
    widget.onHoverVisit(null);
    setState(() => _pointer = details.globalPosition);
    _previewAt(details.globalPosition);
    _edgeScroll?.cancel();
    if (widget.layout.overflows) {
      _edgeScroll = Timer.periodic(
          const Duration(milliseconds: 16), (_) => _scrollAtEdge());
    }
  }

  void _scrollAtEdge() {
    final pointer = _pointer;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (pointer == null || box == null || !widget.scroll.hasClients) return;
    final x = box.globalToLocal(pointer).dx;
    // Hold near either edge to reach visits beyond the viewport. Reverse scroll
    // anchors the newest end; RTL reverses its physical direction once more.
    final edge = math.min(28.0, box.size.width / 3);
    if (edge <= 0) return;
    final velocity = x < edge
        ? -((edge - x) / edge).clamp(0.0, 1.0)
        : x > box.size.width - edge
            ? ((x - box.size.width + edge) / edge).clamp(0.0, 1.0)
            : 0.0;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final scroll = widget.scroll;
    final target = (scroll.offset + velocity * (rtl ? 7.0 : -7.0))
        .clamp(0.0, scroll.position.maxScrollExtent);
    if (target == scroll.offset) return;
    scroll.jumpTo(target);
    _previewAt(pointer);
  }

  void _finish({bool commit = false}) {
    final index = _previewId == null ? -1 : _previewIndex;
    _edgeScroll?.cancel();
    _edgeScroll = null;
    setState(() {
      _pointer = null;
      _previewId = null;
    });
    widget.onHoverVisit(null);
    if (commit && !widget.switching && index >= 0) {
      widget.onSelectVisit(index);
    }
  }

  void _step(int index) {
    if (widget.switching || _scrubbing || widget.visits.isEmpty) return;
    widget.onSelectVisit(index.clamp(0, widget.visits.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final selected = _previewIndex;
    return Focus(
      focusNode: _focus,
      onFocusChange: (focused) {
        if (mounted && !focused && _previewId != null) _finish();
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.escape && _previewId != null) {
          _finish();
        } else if (key == LogicalKeyboardKey.enter && _previewId != null) {
          _finish(commit: true);
        } else if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          final forward = (key == LogicalKeyboardKey.arrowRight) != rtl;
          _keyboardPreview(selected < 0
              ? widget.visits.length - 1
              : selected + (forward ? 1 : -1));
        } else if (key == LogicalKeyboardKey.home) {
          _keyboardPreview(0);
        } else if (key == LogicalKeyboardKey.end) {
          _keyboardPreview(widget.visits.length - 1);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Semantics(
        slider: true,
        value: selected >= 0
            ? DF.full(widget.visits[selected].date)
            : txt('initialExam'),
        increasedValue: selected < widget.visits.length - 1
            ? DF.full(widget
                .visits[selected < 0 ? widget.visits.length - 1 : selected + 1]
                .date)
            : null,
        decreasedValue: selected != 0
            ? DF.full(widget
                .visits[selected < 0 ? widget.visits.length - 1 : selected - 1]
                .date)
            : null,
        onIncrease: !widget.switching && selected < widget.visits.length - 1
            ? () =>
                _step(selected < 0 ? widget.visits.length - 1 : selected + 1)
            : null,
        onDecrease: !widget.switching && selected != 0
            ? () =>
                _step(selected < 0 ? widget.visits.length - 1 : selected - 1)
            : null,
        child: GestureDetector(
          key: _viewportKey,
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: widget.switching ? null : _start,
          onHorizontalDragUpdate: widget.switching
              ? null
              : (details) {
                  if (!_scrubbing) return;
                  _pointer = details.globalPosition;
                  _previewAt(details.globalPosition);
                },
          onHorizontalDragEnd: (_) {
            if (_scrubbing) _finish(commit: true);
          },
          onHorizontalDragCancel: () {
            if (_scrubbing) _finish();
          },
          onTapUp: widget.switching
              ? null
              : (details) {
                  _previewAt(details.globalPosition);
                  _finish(commit: true);
                },
          child: Listener(
            // An accepted DragGestureRecognizer reports pointer cancellation as
            // onEnd, so clear the preview before it can commit the selection.
            onPointerCancel: (_) {
              if (_scrubbing) _finish();
            },
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent ||
                  !widget.scroll.hasClients ||
                  _scrubbing) {
                return;
              }
              final delta = event.scrollDelta.dx != 0
                  ? event.scrollDelta.dx
                  : event.scrollDelta.dy;
              final scroll = widget.scroll;
              final target = (scroll.offset + delta)
                  .clamp(0.0, scroll.position.maxScrollExtent);
              if (target == scroll.offset) return;
              GestureBinding.instance.pointerSignalResolver.register(event,
                  (_) {
                scroll.jumpTo(target);
              });
            },
            child: _EdgeTransparencyFade(
              key: const ValueKey('scope-timeline-fade'),
              fadeStart: widget.fadeStart,
              fadeEnd: widget.fadeEnd,
              child: SingleChildScrollView(
                key: const ValueKey('scope-visit-scroll'),
                controller: widget.scroll,
                reverse: true,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  key: _canvasKey,
                  child: _VisitTimelineCanvas(
                    visits: widget.visits,
                    layout: widget.layout,
                    selectedIndex: selected,
                    hoveredVisitId: _previewId ?? widget.hoveredVisitId,
                    visitKeys: widget.visitKeys,
                    switching: widget.switching,
                    scrubbing: _previewId != null || _scrubbing,
                    onSelectVisit: (index) {
                      if (_previewId != null) _finish();
                      widget.onSelectVisit(index);
                    },
                    onHoverVisit: widget.onHoverVisit,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the horizontal time line, interval duration badges, compact endpoint
/// date labels, and clickable appointment dots.
class _VisitTimelineCanvas extends StatelessWidget {
  const _VisitTimelineCanvas({
    required this.visits,
    required this.layout,
    required this.selectedIndex,
    required this.hoveredVisitId,
    required this.visitKeys,
    required this.switching,
    required this.onSelectVisit,
    required this.onHoverVisit,
    required this.scrubbing,
  });

  final List<Appointment> visits;
  final TimelineLayout layout;
  final int selectedIndex;
  final String? hoveredVisitId;
  final Map<String, GlobalKey> visitKeys;
  final bool switching;
  final bool scrubbing;
  final ValueChanged<int> onSelectVisit;
  final ValueChanged<String?> onHoverVisit;

  static const double _trackY = 14.0;
  static const double _hitWidth = 26.0;

  /// Picks which dot indices can display a micro-date label underneath without
  /// overlapping adjacent labels. Always prioritizes the selected visit, then
  /// the first and last visits.
  Set<int> _visibleDateIndices() {
    if (visits.isEmpty) return const {};
    const minLabelDistance = 58.0;
    final chosen = <int>{};

    bool canPlace(int candidate) {
      final x = layout.positions[candidate];
      for (final existing in chosen) {
        if ((layout.positions[existing] - x).abs() < minLabelDistance) {
          return false;
        }
      }
      return true;
    }

    if (selectedIndex >= 0 && selectedIndex < visits.length) {
      chosen.add(selectedIndex);
    }
    if (canPlace(0)) chosen.add(0);
    if (canPlace(visits.length - 1)) chosen.add(visits.length - 1);
    for (var i = 1; i < visits.length - 1; i++) {
      if (canPlace(i)) chosen.add(i);
    }
    return chosen;
  }

  String _compactIntervalLabel(DateTime from, DateTime to) {
    final days = to.difference(from).inDays.abs();
    if (days == 0) {
      final hours = to.difference(from).inHours.abs();
      return hours > 0
          ? '$hours${txt('timelineHourUnit')}'
          : '<1${txt('timelineDayUnit')}';
    }
    if (days >= 365) {
      final years = (days / 365).floor();
      return '$years${txt('timelineYearUnit')}';
    }
    if (days >= 60) {
      final months = (days / 30).round();
      return '$months${txt('timelineMonthUnit')}';
    }
    if (days >= 14 && days % 7 == 0) {
      return '${days ~/ 7}${txt('timelineWeekUnit')}';
    }
    return '$days${txt('timelineDayUnit')}';
  }

  /// The widest a dot reaches either side of its position — the selected dot at
  /// 15 px — plus the air a label needs before it starts touching one.
  static const double _dotClearance = 10.0;

  /// The duration between two visits, drawn above its segment.
  ///
  /// How much room a label needs is **measured**, not assumed: "3m" takes about
  /// 14 px, so a segment less than half the old fixed 68 px still says it —
  /// while "12m" keeps asking for the room it really needs. The label sits
  /// between the two dots, far enough from each that a dot drawn at its largest
  /// never runs into it.
  List<Widget> _intervalLabels(
    Color color,
    TextDirection direction,
    TextScaler textScaler,
  ) {
    final style = TextStyle(
      fontSize: 8.5,
      height: 1.0,
      fontWeight: FontWeight.w600,
      color: color,
    );
    final labels = <Widget>[];
    for (var i = 0; i < visits.length - 1; i++) {
      final start = layout.positions[i];
      final end = layout.positions[i + 1];
      final gap = end - start;
      // Too tight for any label at all: measuring would only confirm it.
      if (gap < 2 * _dotClearance + 8) {
        continue;
      }
      final label = _compactIntervalLabel(visits[i].date, visits[i + 1].date);
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        maxLines: 1,
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      final width = painter.width + 2 * _dotClearance;
      painter.dispose();
      if (gap < width) continue;
      labels.add(PositionedDirectional(
        start: (start + end) / 2 - width / 2,
        top: 0,
        width: width,
        height: 11,
        child: IgnorePointer(
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textScaler: textScaler,
              style: style,
            ),
          ),
        ),
      ));
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final direction = Directionality.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final labeledIndices = _visibleDateIndices();
    final hoveredIndex = hoveredVisitId == null
        ? -1
        : visits.indexWhere((v) => v.id == hoveredVisitId);

    return SizedBox(
      width: layout.trackWidth,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('scope-timeline-track'),
                painter: _TimelineTrackPainter(
                  positions: layout.positions,
                  visits: visits,
                  selectedIndex: selectedIndex,
                  hoveredIndex: hoveredIndex,
                  trackY: _trackY,
                  accent: PanelAccents.appointment,
                  inactiveColor: theme.resources.controlStrokeColorDefault,
                  darkMode: darkMode,
                  textDirection: direction,
                ),
              ),
            ),
          ),
          // Interval duration micro-labels, on every segment that can hold one
          ..._intervalLabels(
            theme.inactiveColor.withValues(alpha: 0.72),
            direction,
            MediaQuery.textScalerOf(context),
          ),
          // Non-overlapping compact date captions under key dots
          for (final i in labeledIndices)
            PositionedDirectional(
              start: (layout.positions[i] - 32.0)
                  .clamp(0.0, math.max(0.0, layout.trackWidth - 64.0)),
              top: 25,
              width: 64,
              height: 14,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    DF.allNumbers(visits[i].date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: i == selectedIndex || i == hoveredIndex
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == selectedIndex
                          ? PanelAccents.appointment
                          : i == hoveredIndex
                              ? theme.typography.body?.color
                              : theme.inactiveColor.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),
          // Clickable appointment dots on the horizontal line
          for (var i = 0; i < visits.length; i++)
            PositionedDirectional(
              key: visitKeys[visits[i].id],
              start: layout.positions[i] - _hitWidth / 2,
              top: 0,
              width: _hitWidth,
              height: 40,
              child: _TimelineAppointmentDot(
                key: ValueKey('scope-appointment:${visits[i].id}'),
                visit: visits[i],
                previousVisit: i > 0 ? visits[i - 1] : null,
                visitNumber: i + 1,
                totalVisits: visits.length,
                isFirst: i == 0,
                isNewest: i == visits.length - 1,
                selected: selectedIndex == i,
                hovered: hoveredVisitId == visits[i].id,
                scrubbing: scrubbing,
                trackY: _trackY,
                onPressed: switching ? null : () => onSelectVisit(i),
                onHoverChanged: (isHovered) {
                  if (isHovered) {
                    onHoverVisit(visits[i].id);
                  } else if (hoveredVisitId == visits[i].id) {
                    onHoverVisit(null);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the horizontal time line connecting the first appointment dot to the
/// last appointment dot, using solid segments for completed/past history and
/// dashed segments for upcoming scheduled visits.
class _TimelineTrackPainter extends CustomPainter {
  const _TimelineTrackPainter({
    required this.positions,
    required this.visits,
    required this.selectedIndex,
    required this.hoveredIndex,
    required this.trackY,
    required this.accent,
    required this.inactiveColor,
    required this.darkMode,
    required this.textDirection,
  });

  final List<double> positions;
  final List<Appointment> visits;
  final int selectedIndex;
  final int hoveredIndex;
  final double trackY;
  final Color accent;
  final Color inactiveColor;
  final bool darkMode;
  final TextDirection textDirection;

  double _resolveX(double startX, double width) =>
      textDirection == TextDirection.rtl ? width - startX : startX;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;

    final baseTrackPaint = Paint()
      ..color = inactiveColor.withValues(alpha: darkMode ? 0.35 : 0.28)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    if (positions.length == 1) {
      final center = _resolveX(positions.first, size.width);
      canvas.drawLine(
        Offset(_resolveX(0, size.width), trackY),
        Offset(_resolveX(size.width - 10, size.width), trackY),
        baseTrackPaint,
      );
      canvas.drawLine(
        Offset(math.max(10, center - 28), trackY),
        Offset(math.min(size.width - 10, center + 28), trackY),
        Paint()
          ..color = accent.withValues(alpha: 0.65)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    canvas.drawLine(
      Offset(_resolveX(0, size.width), trackY),
      Offset(_resolveX(positions.first, size.width), trackY),
      baseTrackPaint,
    );

    final now = DateTime.now();
    for (var i = 0; i < positions.length - 1; i++) {
      final x1 = _resolveX(positions[i], size.width);
      final x2 = _resolveX(positions[i + 1], size.width);
      final nextVisit = visits[i + 1];
      final isFutureSegment = !nextVisit.isDone && nextVisit.date.isAfter(now);
      final isHighlighted = i == selectedIndex ||
          i + 1 == selectedIndex ||
          i == hoveredIndex ||
          i + 1 == hoveredIndex;

      final segmentColor = isHighlighted
          ? accent.withValues(alpha: darkMode ? 0.90 : 0.80)
          : isFutureSegment
              ? accent.withValues(alpha: darkMode ? 0.42 : 0.36)
              : accent.withValues(alpha: darkMode ? 0.62 : 0.52);

      final paint = Paint()
        ..color = segmentColor
        ..strokeWidth = isHighlighted ? 2.6 : 2.0
        ..strokeCap = StrokeCap.round;

      if (isFutureSegment) {
        _drawDashedLine(
          canvas,
          Offset(x1, trackY),
          Offset(x2, trackY),
          paint,
        );
      } else {
        canvas.drawLine(Offset(x1, trackY), Offset(x2, trackY), paint);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final total = (p2 - p1).distance;
    if (total <= 0) return;
    final dir = (p2 - p1) / total;
    const dash = 4.0;
    const gap = 3.0;
    var dist = 0.0;
    while (dist < total) {
      final end = math.min(dist + dash, total);
      canvas.drawLine(p1 + dir * dist, p1 + dir * end, paint);
      dist += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_TimelineTrackPainter oldDelegate) =>
      oldDelegate.positions != positions ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.hoveredIndex != hoveredIndex ||
      oldDelegate.darkMode != darkMode ||
      oldDelegate.textDirection != textDirection;
}

/// One clickable appointment dot on the horizontal timeline, with an anchored
/// rich hover card.
class _TimelineAppointmentDot extends StatefulWidget {
  const _TimelineAppointmentDot({
    super.key,
    required this.visit,
    required this.previousVisit,
    required this.visitNumber,
    required this.totalVisits,
    required this.isFirst,
    required this.isNewest,
    required this.selected,
    required this.hovered,
    required this.scrubbing,
    required this.trackY,
    required this.onPressed,
    required this.onHoverChanged,
  });

  final Appointment visit;
  final Appointment? previousVisit;
  final int visitNumber;
  final int totalVisits;
  final bool isFirst;
  final bool isNewest;
  final bool selected;
  final bool hovered;
  final bool scrubbing;
  final double trackY;
  final VoidCallback? onPressed;
  final ValueChanged<bool> onHoverChanged;

  @override
  State<_TimelineAppointmentDot> createState() =>
      _TimelineAppointmentDotState();
}

class _TimelineAppointmentDotState extends State<_TimelineAppointmentDot> {
  final OverlayPortalController _portalController = OverlayPortalController();

  /// How far the open visit's ring travels past its edge — enough to be seen,
  /// short of reaching the neighbouring dot.
  static const double _rippleSpread = 8.0;

  @override
  void initState() {
    super.initState();
    if (widget.hovered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.hovered && !_portalController.isShowing) {
          _portalController.show();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TimelineAppointmentDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hovered != oldWidget.hovered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.hovered && !_portalController.isShowing) {
          _portalController.show();
        } else if (!widget.hovered && _portalController.isShowing) {
          _portalController.hide();
        }
      });
    }
  }

  void _handleHover(bool isHovered) {
    if (widget.scrubbing) return;
    if (isHovered && !_portalController.isShowing) {
      _portalController.show();
    } else if (!isHovered && _portalController.isShowing) {
      _portalController.hide();
    }
    widget.onHoverChanged(isHovered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final visit = widget.visit;
    final session = appointmentSessions.get(visit.id);
    final isDirty = session?.hasPendingEdits ?? false;

    final Color dotColor =
        visit.isMissed ? Colors.red : PanelAccents.appointment;

    final double size = widget.selected
        ? 15.0
        : widget.hovered
            ? 13.5
            : (widget.isFirst || widget.isNewest)
                ? 11.5
                : 10.0;

    final dateLabel = DF.allNumbers(visit.date);
    final semanticsLabel =
        widget.isNewest ? '$dateLabel · ${txt('newestVisit')}' : dateLabel;

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (overlayContext) => _buildHoverOverlay(
        overlayContext,
        isDirty: isDirty,
      ),
      child: Semantics(
        selected: widget.selected,
        button: true,
        label: semanticsLabel,
        child: MouseRegion(
          cursor: widget.onPressed != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => _handleHover(true),
          onExit: (_) => _handleHover(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The open visit radiates: a slow ring grows out of it so the
                // bar says which visit the chart shows without being read.
                if (widget.selected)
                  Positioned(
                    top: widget.trackY - (size + 2 * _rippleSpread) / 2,
                    left: (_VisitTimelineCanvas._hitWidth -
                            (size + 2 * _rippleSpread)) /
                        2,
                    width: size + 2 * _rippleSpread,
                    height: size + 2 * _rippleSpread,
                    child: _OpenScopeRipple(
                      key: ValueKey('scope-appointment-ripple:${visit.id}'),
                      color: dotColor,
                      spread: _rippleSpread,
                    ),
                  ),
                // Hover keeps a soft pad behind the dot. The open visit has
                // nothing fixed: its ring is what marks it.
                if (widget.hovered)
                  Positioned(
                    top: widget.trackY - (size + 7) / 2,
                    left: (_VisitTimelineCanvas._hitWidth - (size + 7)) / 2,
                    width: size + 7,
                    height: size + 7,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            dotColor.withValues(alpha: darkMode ? 0.18 : 0.12),
                      ),
                    ),
                  ),
                // Main dot on the horizontal timeline
                Positioned(
                  top: widget.trackY - size / 2,
                  left: (_VisitTimelineCanvas._hitWidth - size) / 2,
                  width: size,
                  height: size,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected || visit.isDone
                          ? dotColor
                          : visit.isMissed
                              ? Colors.red.withValues(alpha: 0.20)
                              : theme.cardColor,
                      border: Border.all(
                        color: widget.selected
                            ? (darkMode ? Colors.white : theme.cardColor)
                            : dotColor,
                        width: widget.selected ? 2.0 : 2.2,
                      ),
                      boxShadow: [
                        if (widget.selected || widget.hovered)
                          BoxShadow(
                            color: dotColor.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 1.5),
                          ),
                      ],
                    ),
                    child: widget.selected
                        ? Center(
                            child: Container(
                              width: 4.5,
                              height: 4.5,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                // Unsaved draft indicator dot
                if (isDirty)
                  Positioned(
                    top: widget.trackY - size / 2 - 2,
                    right: (_VisitTimelineCanvas._hitWidth - size) / 2 - 2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.orange,
                        border: Border.all(color: theme.cardColor, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHoverOverlay(
    BuildContext overlayContext, {
    required bool isDirty,
  }) {
    final dotBox = context.findRenderObject() as RenderBox?;
    final overlayBox = Overlay.maybeOf(overlayContext)
        ?.context
        .findRenderObject() as RenderBox?;
    if (dotBox == null ||
        !dotBox.attached ||
        overlayBox == null ||
        !overlayBox.attached) {
      return const SizedBox.shrink();
    }

    final dotTopLeft = dotBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final dotCenterX = dotTopLeft.dx + dotBox.size.width / 2;
    final dotBottomY = dotTopLeft.dy + widget.trackY + 12;
    final overlaySize = overlayBox.size;

    const cardWidth = 300.0;
    final left = (dotCenterX - cardWidth / 2)
        .clamp(
          8.0,
          math.max(8.0, overlaySize.width - cardWidth - 8.0),
        )
        .toDouble();
    final tailOffset =
        (dotCenterX - left).clamp(18.0, cardWidth - 18.0).toDouble();
    final top = math.min(
      dotBottomY,
      math.max(8.0, overlaySize.height - 290.0),
    );

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: IgnorePointer(
        child: _TimelineVisitHoverCard(
          key: ValueKey('scope-hover-card-${widget.visit.id}'),
          visit: widget.visit,
          previousVisit: widget.previousVisit,
          visitNumber: widget.visitNumber,
          totalVisits: widget.totalVisits,
          isNewest: widget.isNewest,
          isDirty: isDirty,
          tailCenterX: tailOffset,
        ),
      ),
    );
  }
}

/// Rich clinical preview card displayed when hovering over an appointment dot
/// on the dental chart's horizontal timeline.
class _TimelineVisitHoverCard extends StatelessWidget {
  const _TimelineVisitHoverCard({
    super.key,
    required this.visit,
    required this.previousVisit,
    required this.visitNumber,
    required this.totalVisits,
    required this.isNewest,
    required this.isDirty,
    required this.tailCenterX,
  });

  final Appointment visit;
  final Appointment? previousVisit;
  final int visitNumber;
  final int totalVisits;
  final bool isNewest;
  final bool isDirty;
  final double tailCenterX;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    const accent = PanelAccents.appointment;
    final borderColor = accent.withValues(alpha: darkMode ? 0.55 : 0.38);
    final cardBg = theme.menuColor;

    final statusColor = visit.isDone
        ? Colors.green
        : visit.isMissed
            ? Colors.red
            : accent;
    final statusLabel = visit.isDone
        ? txt('completed')
        : visit.isMissed
            ? txt('missed')
            : txt('pending');
    final statusIcon = visit.isDone
        ? FluentIcons.check_mark
        : visit.isMissed
            ? FluentIcons.event_date_missed12
            : FluentIcons.clock;

    final toothIsos = {
      ...visit.teeth.keys,
      ...visit.teethExtraNotes.keys,
    }.toList()
      ..sort();

    final canSeePostOp = canViewPostOp(visit);
    final canSeeMoney = login.perm(Perm.revenue).read ||
        visit.userIsOperator ||
        visit.operatorsIDs.isEmpty;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: darkMode ? 0.45 : 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: darkMode ? 0.16 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header: Visit # + Status pill + Newest badge + Duration
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Txt(
                        '${txt('appointment')} #$visitNumber/$totalVisits',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 9, color: statusColor),
                          const SizedBox(width: 3),
                          Txt(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isNewest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.resources.subtleFillColorSecondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Txt(
                          txt('newestVisit'),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: theme.inactiveColor,
                          ),
                        ),
                      ),
                    if (isDirty) const UnsavedDot(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.clock,
                            size: 10, color: theme.inactiveColor),
                        const SizedBox(width: 3),
                        Txt(
                          '${visit.duration} ${txt('minutes')}',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.inactiveColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 2. Date & elapsed duration since previous visit
                Txt(
                  DF.full(visit.date),
                  style: theme.typography.bodyStrong?.copyWith(fontSize: 12.5),
                ),
                if (previousVisit != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(WindowsIcons.history,
                          size: 10, color: theme.inactiveColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Txt(
                          '${txt('after')} ${Patient.formatDuration(previousVisit!.date, visit.date)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                            color: theme.inactiveColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // 3. Scrollable clinical details with vertical transparency fade
                if (toothIsos.isNotEmpty ||
                    (canSeePostOp && visit.postOpNotes.isNotEmpty) ||
                    visit.preOpNotes.isNotEmpty ||
                    visit.operatorsIDs.isNotEmpty ||
                    (canSeePostOp && visit.prescriptions.isNotEmpty) ||
                    visit.hasLabwork ||
                    visit.viewableImgs.isNotEmpty ||
                    visit.viewableDcmImgs.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Divider(),
                  ),
                  _VerticalScrollFadeBox(
                    key: ValueKey('hover-card-scroll-${visit.id}'),
                    maxHeight: 165,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (toothIsos.isNotEmpty) ...[
                          _hoverSectionRow(
                            context,
                            icon: FluentIcons.teeth,
                            title: txt('treatments'),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final iso in toothIsos)
                                  _HoverTreatmentChip(
                                    iso: iso,
                                    treatment: visit.teeth[iso],
                                    extraNote: visit.teethExtraNotes[iso],
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (canSeePostOp && visit.postOpNotes.isNotEmpty) ...[
                          if (toothIsos.isNotEmpty) const SizedBox(height: 5),
                          _hoverSectionRow(
                            context,
                            icon: WindowsIcons.quick_note,
                            title: txt('post-opNotes'),
                            child: Txt(
                              visit.postOpNotes,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                        if (visit.preOpNotes.isNotEmpty) ...[
                          if (toothIsos.isNotEmpty ||
                              (canSeePostOp && visit.postOpNotes.isNotEmpty))
                            const SizedBox(height: 5),
                          _hoverSectionRow(
                            context,
                            icon: WindowsIcons.quick_note,
                            title: txt('pre-opNotes'),
                            child: Txt(
                              visit.preOpNotes,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                        if (visit.operatorsNames.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _hoverSectionRow(
                            context,
                            icon: FluentIcons.medical,
                            title: txt('doctors'),
                            child: Txt(
                              visit.operatorsNames,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                        if (canSeePostOp && visit.prescriptions.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _hoverSectionRow(
                            context,
                            icon: FluentIcons.pill,
                            title: txt('prescription'),
                            child: Txt(
                              visit.prescriptions.join(', '),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                        if (visit.hasLabwork) ...[
                          const SizedBox(height: 5),
                          _hoverSectionRow(
                            context,
                            icon: FluentIcons.manufacturing,
                            title: txt('labwork'),
                            child: Txt(
                              [
                                if (visit.labName.isNotEmpty) visit.labName,
                                visit.labworkStatus,
                                if (visit.labworkNotes.isNotEmpty)
                                  visit.labworkNotes,
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                        if (visit.viewableImgs.isNotEmpty ||
                            visit.viewableDcmImgs.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _hoverSectionRow(
                            context,
                            icon: FluentIcons.camera,
                            title: txt('photos'),
                            child: Txt(
                              [
                                if (visit.viewableImgs.isNotEmpty)
                                  '${txt('photos')}: ${visit.viewableImgs.length}',
                                if (visit.viewableDcmImgs.isNotEmpty)
                                  '${txt('dcm')}: ${visit.viewableDcmImgs.length}',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                // 4. Price & Payment Footer
                if (canSeeMoney) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Divider(),
                  ),
                  _buildMoneyRow(context, theme),
                ],
              ],
            ),
          ),
        ),
        // Upward-pointing tail anchored to the dot center
        Positioned(
          top: 0,
          left: tailCenterX - 7,
          child: CustomPaint(
            size: const Size(14, 7),
            painter: _HoverCardTailPainter(
              background: cardBg,
              border: borderColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _hoverSectionRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final theme = FluentTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 12, color: theme.inactiveColor),
        ),
        const SizedBox(width: 5),
        SizedBox(
          width: 68,
          child: Txt(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: theme.inactiveColor,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildMoneyRow(BuildContext context, FluentThemeData theme) {
    final payColor = colorBasedOnPayments(visit.paid, visit.price) ??
        (visit.fullPaid && visit.price > 0
            ? Colors.green
            : theme.inactiveColor);

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(FluentIcons.money, size: 13, color: payColor),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Txt(
              '${txt('price')}: ',
              style: TextStyle(fontSize: 10.5, color: theme.inactiveColor),
            ),
            MoneyDisplay(
              '${visit.price.toStringAsFixed(2)} ${currency()}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Txt(
              '${txt('paid')}: ',
              style: TextStyle(fontSize: 10.5, color: theme.inactiveColor),
            ),
            MoneyDisplay(
              '${visit.paid.toStringAsFixed(2)} ${currency()}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (visit.price != visit.paid)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: payColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Txt(
              '${txt(visit.overPaid ? 'overpaid' : 'underpaid')} ${visit.paymentDifference.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: payColor,
              ),
            ),
          )
        else if (visit.price > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Txt(
              txt('fullyPaid'),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: Colors.green,
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact treatment badge inside the rich hover card showing the tooth notation,
/// treatment icon/color, localized treatment name, and any tooth note.
class _HoverTreatmentChip extends StatelessWidget {
  const _HoverTreatmentChip({
    required this.iso,
    this.treatment,
    this.extraNote,
  });

  final String iso;
  final String? treatment;
  final String? extraNote;

  @override
  Widget build(BuildContext context) {
    final hasTx = treatment != null && treatment!.isNotEmpty;
    final color =
        hasTx ? labelToColor(treatment!) : FluentTheme.of(context).accentColor;
    final icon = hasTx ? labelToIcon(treatment!) : FluentIcons.teeth;
    final note = extraNote?.trim() ?? '';

    return Container(
      constraints: const BoxConstraints(maxWidth: 185),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 12, color: color),
          DentalNotation(iso: iso, withTooltip: false, color: color),
          if (hasTx)
            Txt(
              txt(treatment!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (note.isNotEmpty)
            Txt(
              '($note)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: FluentTheme.of(context).inactiveColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// A bounded vertical container that does not scroll unless its content exceeds
/// [maxHeight], in which case it scrolls and applies a top/bottom transparency
/// fade indicating there is more content to scroll to.
class _VerticalScrollFadeBox extends StatefulWidget {
  const _VerticalScrollFadeBox({
    super.key,
    required this.maxHeight,
    required this.child,
  });

  final double maxHeight;
  final Widget child;

  @override
  State<_VerticalScrollFadeBox> createState() => _VerticalScrollFadeBoxState();
}

class _VerticalScrollFadeBoxState extends State<_VerticalScrollFadeBox> {
  final ScrollController _controller = ScrollController();
  bool _fadeTop = false;
  bool _fadeBottom = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncFade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFade());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFade);
    _controller.dispose();
    super.dispose();
  }

  void _syncFade() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final top = pos.maxScrollExtent > 1.0 && pos.pixels > 1.0;
    final bottom =
        pos.maxScrollExtent > 1.0 && pos.pixels < pos.maxScrollExtent - 1.0;
    if (top != _fadeTop || bottom != _fadeBottom) {
      setState(() {
        _fadeTop = top;
        _fadeBottom = bottom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _syncFade();
        return false;
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            if (!_fadeTop && !_fadeBottom) {
              return const LinearGradient(
                colors: [Colors.white, Colors.white],
              ).createShader(bounds);
            }
            final h = bounds.height;
            final stop = h > 0 ? (20.0 / h).clamp(0.05, 0.22) : 0.12;
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _fadeTop ? Colors.transparent : Colors.white,
                Colors.white,
                Colors.white,
                _fadeBottom ? Colors.transparent : Colors.white,
              ],
              stops: [
                0.0,
                _fadeTop ? stop : 0.0,
                _fadeBottom ? 1.0 - stop : 1.0,
                1.0,
              ],
            ).createShader(bounds);
          },
          child: SingleChildScrollView(
            controller: _controller,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _HoverCardTailPainter extends CustomPainter {
  const _HoverCardTailPainter({
    required this.background,
    required this.border,
  });

  final Color background;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = background);

    final edge = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(
      edge,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_HoverCardTailPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.border != border;
}

/// A ring that keeps growing out of the record the chart has open, so the bar
/// says which visit is on screen at a glance instead of on close reading.
///
/// The ring only carries attention: with reduced motion, or while the record is
/// not the open one, nothing is drawn and the record keeps its static
/// highlight.
class _OpenScopeRipple extends StatefulWidget {
  const _OpenScopeRipple({
    super.key,
    required this.color,
    required this.spread,
    this.borderRadius,
  });

  final Color color;

  /// How far a ring travels past the marker's own edge. The widget has to be
  /// laid out `2 * spread` larger than the marker on both axes.
  final double spread;

  /// The marker's corner radius, or `null` for the round timeline dots.
  final double? borderRadius;

  @override
  State<_OpenScopeRipple> createState() => _OpenScopeRippleState();
}

class _OpenScopeRippleState extends State<_OpenScopeRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is a dependency, so a change in it lands here; a controller
    // left running would repaint the bar for nothing. TickerMode silences the
    // ticker on its own.
    _followMotion();
  }

  @override
  void didUpdateWidget(covariant _OpenScopeRipple oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followMotion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _followMotion() {
    final run = !debugPauseScopeRipple &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (run == _running) return;
    _running = run;
    if (run) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) return const SizedBox.shrink();
    // The ring is the only thing that changes every frame: its own layer keeps
    // the timeline's text and track out of the repaint.
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          willChange: true,
          painter: _OpenScopeRipplePainter(
            animation: _controller,
            color: widget.color,
            spread: widget.spread,
            borderRadius: widget.borderRadius,
          ),
        ),
      ),
    );
  }
}

/// Paints the rings of [_OpenScopeRipple]. Repainting from the animation keeps
/// the timeline's widgets out of the loop: only this layer is redrawn.
class _OpenScopeRipplePainter extends CustomPainter {
  _OpenScopeRipplePainter({
    required this.animation,
    required this.color,
    required this.spread,
    required this.borderRadius,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final double spread;
  final double? borderRadius;

  /// Two rings half a cycle apart read as one wave that never restarts.
  static const int _rings = 2;

  static const double _peakAlpha = 0.52;

  @override
  void paint(Canvas canvas, Size size) {
    if (spread <= 0 || size.isEmpty) return;
    final marker = Rect.fromLTWH(
      spread,
      spread,
      size.width - 2 * spread,
      size.height - 2 * spread,
    );
    if (marker.isEmpty) return;
    for (var ring = 0; ring < _rings; ring++) {
      final phase = (animation.value + ring / _rings) % 1.0;
      final grow = spread * Curves.easeOut.transform(phase);
      // Fading in and out over the travel keeps the ring from ever popping at
      // the marker's edge.
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 - 1.0 * phase
        ..color =
            color.withValues(alpha: _peakAlpha * math.sin(math.pi * phase));
      final outline = marker.inflate(grow);
      final radius = borderRadius;
      if (radius == null) {
        canvas.drawCircle(outline.center, outline.shortestSide / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(outline, Radius.circular(radius + grow)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OpenScopeRipplePainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.color != color ||
      oldDelegate.spread != spread ||
      oldDelegate.borderRadius != borderRadius;
}

/// The initial exam is the timeline's origin, even before a visit exists.
class _InitialExamStop extends StatelessWidget {
  const _InitialExamStop({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  /// How far the open panel's ring travels past the pill, kept small so it
  /// stays inside the bar's height.
  static const double _rippleSpread = 5.0;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    const accent = PanelAccents.patient;
    return Semantics(
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: HoverButton(
          onPressed: onPressed,
          builder: (context, states) {
            final highlighted =
                selected || states.isHovered || states.isFocused;
            return SizedBox(
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The same ring the open visit draws, once the chart is on
                  // the patient rather than on a visit.
                  if (selected)
                    const PositionedDirectional(
                      start: 4 - _InitialExamStop._rippleSpread,
                      end: 4 - _InitialExamStop._rippleSpread,
                      top: 2 - _InitialExamStop._rippleSpread,
                      height: 24 + 2 * _InitialExamStop._rippleSpread,
                      child: _OpenScopeRipple(
                        key: ValueKey('scope-initial-exam-ripple'),
                        color: accent,
                        spread: _InitialExamStop._rippleSpread,
                        borderRadius: 12,
                      ),
                    ),
                  const PositionedDirectional(
                    start: 0,
                    end: 0,
                    top: 0,
                    bottom: 0,
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      alignment: AlignmentDirectional.centerEnd,
                      child: _InitialExamTrack(),
                    ),
                  ),
                  PositionedDirectional(
                    start: 4,
                    end: 4,
                    top: 2,
                    height: 24,
                    child: AnimatedContainer(
                      key: const ValueKey('scope-initial-exam-marker'),
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: selected ? accent : theme.cardColor,
                        border: Border.all(
                          color:
                              accent.withValues(alpha: highlighted ? 1 : 0.6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          if (highlighted)
                            BoxShadow(
                              color: accent.withValues(alpha: 0.18),
                              spreadRadius: 2,
                            ),
                        ],
                      ),
                      child: Txt(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.caption?.copyWith(
                              fontSize: 10.5,
                              height: 1.1,
                              fontWeight: highlighted
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected ? Colors.white : accent)),
                    ),
                  ),
                  PositionedDirectional(
                    start: 2,
                    end: 2,
                    top: 27,
                    height: 12,
                    child: ExcludeSemantics(
                      child: Icon(WindowsIcons.zoom,
                          size: 10,
                          color: highlighted ? accent : theme.inactiveColor),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InitialExamTrack extends StatelessWidget {
  const _InitialExamTrack({super.key, this.fade = false});

  final bool fade;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = theme.resources.controlStrokeColorDefault
        .withValues(alpha: theme.brightness == Brightness.dark ? 0.35 : 0.28);
    return Stack(
      children: [
        PositionedDirectional(
          start: 0,
          end: 0,
          top: 13,
          height: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart
                    .resolve(Directionality.of(context)),
                end: AlignmentDirectional.centerEnd
                    .resolve(Directionality.of(context)),
                colors: [color, fade ? color.withValues(alpha: 0) : color],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
