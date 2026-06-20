import 'dart:async';
import 'dart:math';

import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Card;
import 'package:intl/intl.dart' as intl;
import 'package:table_calendar/table_calendar.dart';
import '../../utils/colors_without_yellow.dart';
import 'appointments_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Calendar Timeline View (Google‑Calendar‑style time grid)
// ─────────────────────────────────────────────────────────────────────────────

/// Self-contained time-grid view that positions appointments by duration.
class CalendarTimelineView extends StatefulWidget {
  final List<Appointment> items;
  final bool showPayments;
  final DateTime selectedDate;
  final void Function(Appointment item) onSelect;
  final void Function(Appointment item) onSetTime;
  final void Function(DateTime date) onAddNew;

  const CalendarTimelineView({
    super.key,
    required this.items,
    required this.showPayments,
    required this.selectedDate,
    required this.onSelect,
    required this.onSetTime,
    required this.onAddNew,
  });

  @override
  State<CalendarTimelineView> createState() => _CalendarTimelineViewState();
}

class _CalendarTimelineViewState extends State<CalendarTimelineView> {
  // ─── Constants ─────────────────────────────────────────────────────────
  static const _startHour = 0;
  static const _endHour = 25;
  static const _hourHeight = 250.0;
  static const _emptyHourHeight = 16.0;
  static const _timeGutterW = 52.0;
  static const _minCardW = 270.0;
  static const _autoScrollThreshold = 60.0;
  static const _autoScrollMaxSpeed = 15.0;

  // ─── Scroll / drag state ───────────────────────────────────────────────
  final _vertCtrl = ScrollController();
  final _gutterVertCtrl = ScrollController();
  final _horizCtrl = ScrollController();

  bool _dragging = false;
  Appointment? _dragItem;
  double? _dragTop, _dragH;
  double _grabOffY = 0;
  final _snapMins = 15;
  String? _frontAppId;
  final _hiddenOperators = <String>{};
  double _dragGridWCached = 0;
  Timer? _nowTimer;

  @override
  void initState() {
    super.initState();
    _vertCtrl.addListener(_syncGutterV);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
    _startNowTimer();
  }

  void _startNowTimer() {
    _nowTimer?.cancel();
    _nowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant CalendarTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _resetScroll();
    }
  }

  void _resetScroll() {
    if (_vertCtrl.hasClients) _vertCtrl.jumpTo(0);
    if (_gutterVertCtrl.hasClients) _gutterVertCtrl.jumpTo(0);
    if (_horizCtrl.hasClients) _horizCtrl.jumpTo(0);
    if (isSameDay(DateTime.now(), widget.selectedDate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
    }
  }

  void _syncGutterV() {
    if (_gutterVertCtrl.hasClients &&
        _gutterVertCtrl.offset != _vertCtrl.offset) {
      _gutterVertCtrl.jumpTo(_vertCtrl.offset);
    }
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    _vertCtrl.removeListener(_syncGutterV);
    _vertCtrl.dispose();
    _gutterVertCtrl.dispose();
    _horizCtrl.dispose();
    super.dispose();
  }

  void _scrollToNow() {
    final y = _timeToY(DateTime.now()) - 150;
    if (y > 0 && _vertCtrl.hasClients) _vertCtrl.jumpTo(y);
    if (y > 0 && _gutterVertCtrl.hasClients) _gutterVertCtrl.jumpTo(y);
  }

  // ─── Variable-height slot system ──────────────────────────────────────
  List<double> _slotTops = [];
  List<double> _slotHeights = [];
  double _totalH = 0;

  void _computeSlotHeights(List<Appointment> visibleApps) {
    _slotHeights = List.filled(_endHour - _startHour + 1, _emptyHourHeight);
    for (final a in visibleApps) {
      final startH = a.date.hour.clamp(_startHour, _endHour);
      final endH = (a.endDate.hour + (a.endDate.minute > 0 ? 1 : 0))
          .clamp(_startHour, _endHour);
      for (int h = startH; h < endH; h++) {
        _slotHeights[h - _startHour] = _hourHeight;
      }
    }
    _slotTops = [];
    var y = 0.0;
    for (final h in _slotHeights) {
      _slotTops.add(y);
      y += h;
    }
    _slotTops.add(y);
    _totalH = y;
  }

  // ─── Time helpers ──────────────────────────────────────────────────────
  double _timeToY(DateTime t) {
    if (_slotTops.isEmpty) {
      return (t.hour + t.minute / 60.0 - _startHour) * _hourHeight;
    }
    final idx = (t.hour - _startHour).clamp(0, _slotHeights.length - 1);
    final frac = t.minute / 60.0;
    return _slotTops[idx] + _slotHeights[idx] * frac;
  }

  double _durToH(int minutes) {
    if (_slotHeights.isEmpty) return (minutes / 60.0) * _hourHeight;
    final activeHeights = _slotHeights.where((h) => h == _hourHeight).toList();
    final avgH = activeHeights.isEmpty
        ? _hourHeight
        : activeHeights.reduce((a, b) => a + b) / activeHeights.length;
    return (minutes / 60.0) * avgH;
  }

  DateTime _yToTime(double y) {
    if (_slotTops.isEmpty) {
      final tm = (_startHour * 60 + (y / _hourHeight) * 60).round();
      final sn = (tm / _snapMins).round() * _snapMins;
      return DateTime(widget.selectedDate.year, widget.selectedDate.month,
          widget.selectedDate.day, sn ~/ 60, sn % 60);
    }
    for (int i = 0; i < _slotTops.length - 1; i++) {
      if (y >= _slotTops[i] && y < _slotTops[i + 1]) {
        final frac = (y - _slotTops[i]) / _slotHeights[i];
        final totalMins = ((_startHour + i) * 60 + frac * 60).round();
        final sn = (totalMins / _snapMins).round() * _snapMins;
        return DateTime(
            widget.selectedDate.year,
            widget.selectedDate.month,
            widget.selectedDate.day,
            (sn ~/ 60).clamp(0, 23),
            (sn % 60).clamp(0, 59));
      }
    }
    final tm = (_endHour * 60 - 1);
    return DateTime(widget.selectedDate.year, widget.selectedDate.month,
        widget.selectedDate.day, tm ~/ 60, tm % 60);
  }

  // ─── Chairs ────────────────────────────────────────────────────────────
  List<ChairInfo> get _chairs {
    final ops = accounts.operators;
    if (ops.isEmpty) {
      return [
        const ChairInfo(id: "__un__", name: "Unassigned", color: Colors.grey)
      ];
    }

    final lastWeekDay = widget.selectedDate.subtract(const Duration(days: 7));
    final counts = <String, int>{};
    for (final a in widget.items) {
      if (!_isSameDay(a.date, lastWeekDay)) continue;
      if (a.operatorsIDs.isEmpty) continue;
      final op = a.operatorsIDs.first;
      counts[op] = (counts[op] ?? 0) + 1;
    }

    final sorted = [...ops]..sort((a, b) {
        final ca = counts[a.id] ?? 0;
        final cb = counts[b.id] ?? 0;
        if (ca != cb) return cb.compareTo(ca);
        return ops.indexOf(a).compareTo(ops.indexOf(b));
      });

    return [
      ...sorted.map((op) => ChairInfo(
            id: op.id,
            name: accounts.name(op),
            color: colorsWithoutYellow[
                ops.indexOf(op) % colorsWithoutYellow.length],
          )),
      const ChairInfo(id: "__un__", name: "Unassigned", color: Colors.grey),
    ];
  }

  double _gridX(double gridW) => locale.isRtl ? 0.0 : _timeGutterW;
  double _gridW(double gridW) => gridW - _timeGutterW;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.day == b.day && a.month == b.month && a.year == b.year;

  // ─── Overlap layout ────────────────────────────────────────────────────
  ({Map<String, int> columns, Map<String, int> groupSizes}) _layoutApps(
      List<Appointment> apps) {
    final columns = <String, int>{};
    final groupSizes = <String, int>{};
    if (apps.isEmpty) return (columns: columns, groupSizes: groupSizes);

    final sorted = List<Appointment>.from(apps)
      ..sort((a, b) {
        final comp = a.date.compareTo(b.date);
        if (comp != 0) return comp;
        return b.duration.compareTo(a.duration);
      });

    final List<List<Appointment>> clusters = [];
    List<Appointment> currentCluster = [];
    DateTime? clusterEnd;

    for (final app in sorted) {
      if (clusterEnd == null || !app.date.isBefore(clusterEnd)) {
        if (currentCluster.isNotEmpty) clusters.add(currentCluster);
        currentCluster = [app];
        clusterEnd = app.endDate;
      } else {
        currentCluster.add(app);
        if (app.endDate.isAfter(clusterEnd)) clusterEnd = app.endDate;
      }
    }
    if (currentCluster.isNotEmpty) clusters.add(currentCluster);

    for (final cluster in clusters) {
      final List<DateTime> columnsEndTimes = [];
      for (final app in cluster) {
        int assignedCol = -1;
        for (int i = 0; i < columnsEndTimes.length; i++) {
          if (!app.date.isBefore(columnsEndTimes[i])) {
            assignedCol = i;
            break;
          }
        }
        if (assignedCol == -1) {
          columnsEndTimes.add(app.endDate);
          assignedCol = columnsEndTimes.length - 1;
        } else {
          columnsEndTimes[assignedCol] = app.endDate;
        }
        columns[app.id] = assignedCol;
      }
      final totalClusterCols = columnsEndTimes.length;
      for (final app in cluster) {
        groupSizes[app.id] = totalClusterCols;
      }
    }
    return (columns: columns, groupSizes: groupSizes);
  }

  // ─── Filter ────────────────────────────────────────────────────────────
  List<Appointment> _visibleApps() {
    return widget.items.where((a) {
      if (a.operatorsIDs.isEmpty) return true;
      final op = a.operatorsIDs.first;
      return !_hiddenOperators.contains(op);
    }).toList();
  }

  // ─── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final visibleApps = _visibleApps();

    final layout = _layoutApps(visibleApps);
    final maxOverlap = layout.groupSizes.values.isEmpty
        ? 1
        : layout.groupSizes.values.reduce(max).clamp(1, 20);

    _computeSlotHeights(visibleApps);
    final totalH = _totalH;

    final availW = MediaQuery.of(context).size.width - _timeGutterW - 16;
    final neededW = max(availW, maxOverlap * _minCardW);
    final gridW = _timeGutterW + neededW;
    final needsHorizScroll = neededW > availW;

    _dragGridWCached = gridW;

    final now = DateTime.now();
    final showNow = _isSameDay(now, widget.selectedDate);
    final nowY = _timeToY(now);
    final gx = _gridX(gridW);
    final gw = _gridW(gridW);
    final stroke = FluentTheme.of(context).resources.surfaceStrokeColorDefault;
    final rtl = locale.isRtl;
    final bg = FluentTheme.of(context).resources.solidBackgroundFillColorBase;

    final timeGutter = _buildTimeGutter(totalH, rtl);

    return Stack(children: [
      _buildScrollableArea(neededW, gridW, totalH, gx, gw, stroke, showNow,
          nowY, visibleApps, layout, needsHorizScroll),
      _buildGutterOverlay(rtl, bg.withAlpha(100), timeGutter),
    ]);
  }

  // ─── Time gutter ───────────────────────────────────────────────────────
  Widget _buildTimeGutter(double totalH, bool rtl) {
    final loc = locale.s.$code;
    final hourLabels = <Widget>[];
    for (int h = _startHour; h <= _endHour; h++) {
      final i = h - _startHour;
      final slotH = _slotHeights.isEmpty ? _hourHeight : _slotHeights[i];
      final y = _slotTops.isEmpty ? i * _hourHeight : _slotTops[i];
      final label = h == 0
          ? ""
          : intl.DateFormat('h a', loc).format(DateTime(2020, 1, 1, h));
      hourLabels.add(Positioned(
        left: 0,
        top: y - 10,
        width: _timeGutterW - 8,
        height: 20,
        child: Align(
          alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
          child: Text(label,
              style: TextStyle(
                  fontSize: slotH > _emptyHourHeight ? 16 : 13,
                  fontWeight: FontWeight.w500,
                  color: FluentTheme.of(context).inactiveColor)),
        ),
      ));
      if (h > 0) {
        if (slotH > _emptyHourHeight) {
          final quarterH = slotH / 4;
          for (final q in [15, 30, 45]) {
            final qy = y + quarterH * (q / 15);
            hourLabels.add(Positioned(
              left: 0,
              top: qy - 8,
              width: _timeGutterW - 8,
              height: 16,
              child: Align(
                alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
                child: Text(
                  intl.DateFormat('mm', loc)
                      .format(DateTime(2020, 1, 1, h - 1, q)),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: FluentTheme.of(context)
                          .inactiveColor
                          .withValues(alpha: 0.5)),
                ),
              ),
            ));
          }
        }
      }
    }
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(end: 8),
        controller: _gutterVertCtrl,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: _timeGutterW,
          height: totalH,
          child: Stack(children: hourLabels),
        ),
      ),
    );
  }

  Widget _buildGutterOverlay(bool rtl, Color bg, Widget timeGutter) {
    return Positioned(
      left: rtl ? null : 0,
      right: rtl ? 0 : null,
      top: 0,
      bottom: 0,
      width: _timeGutterW,
      child: ClipRect(
        child: Stack(children: [
          Container(color: bg),
          timeGutter,
          Positioned(
            top: 0,
            bottom: 0,
            right: rtl ? null : 0,
            left: rtl ? 0 : null,
            width: 8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: rtl ? Alignment.centerLeft : Alignment.centerRight,
                    end: rtl ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [
                      Colors.black.withValues(alpha: 0.06),
                      Colors.transparent
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildScrollableArea(
      double colW,
      double gridW,
      double totalH,
      double gx,
      double gw,
      Color stroke,
      bool showNow,
      double nowY,
      List<Appointment> visibleApps,
      ({Map<String, int> columns, Map<String, int> groupSizes}) layout,
      bool needsHorizScroll) {
    final content = SizedBox(
      width: gridW,
      height: totalH,
      child: Stack(children: [
        ..._buildGridLines(gx, gw, stroke),
        if (showNow && nowY >= 0 && nowY <= totalH) _buildNowLine(gx, gw, nowY),
        ..._buildBlocks(gridW, visibleApps, layout),
        if (_dragging && _dragItem != null) _buildDragPrev(),
      ]),
    );
    final scrollable = needsHorizScroll
        ? SingleChildScrollView(
            controller: _vertCtrl,
            child: SingleChildScrollView(
              controller: _horizCtrl,
              scrollDirection: Axis.horizontal,
              child: content,
            ),
          )
        : SingleChildScrollView(
            controller: _vertCtrl,
            child: SingleChildScrollView(
              controller: _horizCtrl,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: content,
            ),
          );
    return GestureDetector(
      onTapUp: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final y = box.globalToLocal(d.globalPosition).dy + _vertCtrl.offset;
        if (y < 0 || y > _totalH) return;
        widget.onAddNew(_yToTime(y));
      },
      child: scrollable,
    );
  }

  List<Widget> _buildGridLines(double gx, double gw, Color stroke) {
    if (_slotTops.isEmpty) {
      return [
        for (int i = 0; i <= _endHour - _startHour; i++)
          Positioned(
              left: gx,
              top: i * _hourHeight - 0.5,
              width: gw,
              height: 1,
              child: Container(color: stroke.withValues(alpha: 0.4))),
        for (int i = 0; i < _endHour - _startHour; i++)
          Positioned(
              left: gx,
              top: (i + 0.5) * _hourHeight,
              width: gw,
              height: 1,
              child: CustomPaint(
                  painter: _DashedLinePainter(
                      color: stroke.withValues(alpha: 0.2)))),
      ];
    }
    return [
      for (int i = 0; i <= _endHour - _startHour; i++)
        Positioned(
            left: gx,
            top: _slotTops[i] - 0.5,
            width: gw,
            height: 1,
            child: Container(color: stroke.withValues(alpha: 0.2))),
      for (int i = 0; i < _endHour - _startHour; i++)
        if (_slotHeights[i] == _hourHeight)
          Positioned(
              left: gx,
              top: _slotTops[i] + _slotHeights[i] / 2,
              width: gw,
              height: 1,
              child: CustomPaint(
                  painter: _DashedLinePainter(
                      color: stroke.withValues(alpha: 0.3)))),
    ];
  }

  Widget _buildNowLine(double gx, double gw, double nowY) {
    final rtl = locale.isRtl;
    return Positioned(
      left: gx,
      top: nowY - 1,
      width: gw,
      child: Row(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Color(0xFFE53E3E), shape: BoxShape.circle)),
          Expanded(child: Container(height: 2, color: const Color(0xFFE53E3E))),
        ],
      ),
    );
  }

  List<Widget> _buildBlocks(double gridW, List<Appointment> apps,
      ({Map<String, int> columns, Map<String, int> groupSizes}) layout) {
    if (apps.isEmpty) return [];

    final displayApps = List<Appointment>.from(apps);
    if (_frontAppId != null) {
      displayApps.sort((a, b) =>
          (a.id == _frontAppId ? 1 : 0).compareTo(b.id == _frontAppId ? 1 : 0));
    }

    final wids = <Widget>[];
    for (final app in displayApps) {
      final sc = layout.columns[app.id] ?? 0;
      const cardW = _minCardW - 4;

      final l = locale.isRtl
          ? gridW - _timeGutterW - (sc + 1) * (cardW + 2) + 2
          : _timeGutterW + 2 + sc * (cardW + 2);
      final t = _timeToY(app.date);
      final h = _durToH(app.duration);

      final opColor = app.operatorsIDs.isEmpty
          ? Colors.grey
          : _chairs
              .firstWhere(
                (c) => c.id == app.operatorsIDs.first,
                orElse: () =>
                    const ChairInfo(id: "", name: "", color: Colors.grey),
              )
              .color;

      wids.add(Positioned(
        left: l,
        top: t,
        width: cardW,
        height: h,
        child: TimelineChip(
          item: app,
          color: opColor,
          showPayments: widget.showPayments,
          onTap: () {
            setState(() => _frontAppId = app.id);
            widget.onSelect(app);
          },
          onLongPressStart: (d) => _onDragStart(app, d),
          onLongPressMove: (d) => _onDragUpdate(d),
          onLongPressEnd: _onDragEnd,
        ),
      ));
    }
    return wids;
  }

  // ─── Drag ──────────────────────────────────────────────────────────────
  void _onDragStart(Appointment app, LongPressStartDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    final lp = box?.globalToLocal(d.globalPosition) ?? Offset.zero;
    final appTop = _timeToY(app.date);
    const hdrOff = 45 + 40 + 2; // title bar + header + padding
    final gy = lp.dy - hdrOff + _vertCtrl.offset;
    _grabOffY = gy - appTop;
    setState(() {
      _dragging = true;
      _dragItem = app;
      _dragTop = appTop;
      _dragH = _durToH(app.duration);
    });
  }

  void _onDragUpdate(LongPressMoveUpdateDetails d) {
    if (!_dragging || _dragItem == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final lcl = box.globalToLocal(d.globalPosition);
    const hdrOff = 45 + 40 + 2;
    final ry = lcl.dy - hdrOff + _vertCtrl.offset;
    final tt = _yToTime(ry - _grabOffY);

    // ── Auto-scroll when dragging near top/bottom edges ──────────────────
    if (_vertCtrl.hasClients) {
      final viewportH = box.size.height - hdrOff;
      final viewportY = lcl.dy - hdrOff; // position relative to viewport top
      final maxScroll = _vertCtrl.position.maxScrollExtent;
      double scrollDelta = 0;
      if (viewportY < _autoScrollThreshold && _vertCtrl.offset > 0) {
        final fraction =
            1.0 - (viewportY / _autoScrollThreshold).clamp(0.0, 1.0);
        scrollDelta = -_autoScrollMaxSpeed * fraction;
      } else if (viewportY > viewportH - _autoScrollThreshold &&
          _vertCtrl.offset < maxScroll) {
        final fraction = 1.0 -
            ((viewportH - viewportY) / _autoScrollThreshold).clamp(0.0, 1.0);
        scrollDelta = _autoScrollMaxSpeed * fraction;
      }
      if (scrollDelta != 0) {
        _vertCtrl.jumpTo((_vertCtrl.offset + scrollDelta).clamp(0, maxScroll));
      }
    }

    setState(() {
      _dragTop = _timeToY(tt).clamp(0.0, _totalH - (_dragH ?? 60));
      _dragH = _durToH(_dragItem!.duration);
    });
  }

  void _onDragEnd() {
    if (_dragItem == null) {
      setState(() {
        _dragging = false;
        _dragItem = null;
      });
      return;
    }
    final app = _dragItem!;
    final tt = _dragTop != null ? _yToTime(_dragTop!) : app.date;
    if (!_isSameDay(app.date, tt) ||
        app.date.hour != tt.hour ||
        app.date.minute != tt.minute) {
      app.date = DateTime(tt.year, tt.month, tt.day, tt.hour, tt.minute);
      appointments.set(app);
      widget.onSetTime(app);
    }
    setState(() {
      _dragging = false;
      _dragItem = null;
      _dragTop = null;
    });
  }

  Widget _buildDragPrev() {
    final a = _dragItem!;
    final targetTime = _dragTop != null ? _yToTime(_dragTop!) : a.date;
    final opColor = a.operatorsIDs.isEmpty
        ? Colors.grey
        : _chairs
            .firstWhere((c) => c.id == a.operatorsIDs.first,
                orElse: () =>
                    const ChairInfo(id: "", name: "", color: Colors.grey))
            .color;
    final totalH = _totalH;
    return Positioned(
      left: _gridX(_dragGridWCached),
      top: (_dragTop ?? 0).clamp(0.0, totalH - (_dragH ?? 60)),
      width: _dragGridWCached - _timeGutterW - 4,
      height: _dragH ?? 60,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: opColor.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: opColor, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(2, 6))
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    intl.DateFormat("h:mm a", locale.s.$code)
                        .format(targetTime),
                    style: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFFFFFFFF),
                        fontWeight: FontWeight.w600)),
                Text(a.title,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFFFFFF),
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline chip (appointment card in the time grid)
// ─────────────────────────────────────────────────────────────────────────────

class TimelineChip extends StatefulWidget {
  final Appointment item;
  final Color color;
  final bool showPayments;
  final VoidCallback onTap;
  final void Function(LongPressStartDetails) onLongPressStart;
  final void Function(LongPressMoveUpdateDetails) onLongPressMove;
  final VoidCallback onLongPressEnd;

  const TimelineChip({
    super.key,
    required this.item,
    required this.color,
    required this.showPayments,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
  });

  @override
  State<TimelineChip> createState() => _TimelineChipState();
}

class _TimelineChipState extends State<TimelineChip> {
  final _durationFlyout = FlyoutController();
  final _operatorsFlyout = FlyoutController();

  @override
  void dispose() {
    _durationFlyout.dispose();
    _operatorsFlyout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double titleWidth = widget.showPayments ? 100 : 130;
    final String note = widget.item.postOpNotes.isEmpty
        ? widget.item.preOpNotes
        : widget.item.postOpNotes;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: widget.onLongPressStart,
      onLongPressMoveUpdate: widget.onLongPressMove,
      onLongPressEnd: (_) => widget.onLongPressEnd(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.color.withValues(alpha: 0.10),
                widget.color.withValues(alpha: 0.04),
              ],
            ),
            border: BorderDirectional(
              start: BorderSide(color: widget.color, width: 4),
              bottom: BorderSide(
                  color: widget.color.withValues(alpha: 0.15), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              routes
                      .panels()
                      .where((p) => p.item.id == widget.item.id)
                      .isNotEmpty
                  ? _buildBringToFrontButton()
                  : _buildDoneCheckBox(context),
              const Divider(direction: Axis.vertical),
              Flexible(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(
                            width: titleWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FluentTheme.of(context)
                                      .typography
                                      .bodyStrong
                                      ?.copyWith(fontSize: 15),
                                ),
                                if (note.isNotEmpty)
                                  Tooltip(
                                    message: note,
                                    child: Text(
                                      note,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: FluentTheme.of(context)
                                              .inactiveColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                              ],
                            ),
                          ),
                          Column(
                            spacing: 2,
                            children: [
                              _cyclePill(),
                              Row(
                                spacing: 2,
                                children: [
                                  if (widget.showPayments &&
                                      widget.item.paid > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 0),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: MoneyDisplay(
                                          "💵 ${widget.item.paid.toStringAsFixed(0)} ${globalSettings.currency}",
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: FluentTheme.of(context)
                                                  .inactiveColor)),
                                    )
                                  else
                                    _buildOperatorsPill()
                                  // else ...[
                                  //   if ((widget.item.patient?.phonesString ??
                                  //           '')
                                  //       .isNotEmpty)
                                  //     PhoneNumberButton(
                                  //         phoneNumbers:
                                  //             widget.item.patient!.phone),
                                  //   if ((widget.item.patient?.allAppointments ??
                                  //               [])
                                  //           .length >
                                  //       1)
                                  //     AppointmentsHistoryFlyout(
                                  //       patient: widget.item.patient!,
                                  //       exclude: widget.item,
                                  //     ),
                                  // ],
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Transform _buildDoneCheckBox(BuildContext context) {
    return Transform.scale(
      scale: 1.1,
      child: Checkbox(
        style: CheckboxThemeData(
          icon: WindowsIcons.completed,
          checkedIconColor: const WidgetStatePropertyAll(Colors.white),
          uncheckedIconColor: WidgetStatePropertyAll(
              FluentTheme.of(context).inactiveColor.withValues(alpha: 0.4)),
        ),
        checked: widget.item.isDone,
        onChanged: (checked) {
          widget.item.isDone = checked == true;
          appointments.set(widget.item);
        },
      ),
    );
  }

  static const _durations = [15, 30, 45, 60, 90, 120];

  Widget _cyclePill() {
    return FlyoutTarget(
      controller: _durationFlyout,
      child: GestureDetector(
        onTap: () => _durationFlyout.showFlyout(
          builder: (ctx) => MenuFlyout(
            items: [
              MenuFlyoutItem(
                text: Text(txt("duration"),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
                leading: Icon(FluentIcons.clock,
                    size: 14, color: FluentTheme.of(ctx).inactiveColor),
                onPressed: null,
              ),
              ..._durations.map((d) {
                final sel = d == widget.item.duration;
                return MenuFlyoutItem(
                  selected: sel,
                  leading: sel
                      ? Icon(FluentIcons.accept, size: 14, color: widget.color)
                      : null,
                  text: Text("$d ${txt("minutes")}"),
                  onPressed: () {
                    widget.item.duration = d;
                    appointments.set(widget.item);
                    _durationFlyout.close();
                    setState(() {});
                  },
                );
              }),
            ],
          ),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: FluentTheme.of(context).shadowColor.withOpacity(0.2),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                )
              ],
            ),
            child: Row(
              spacing: 5,
              children: [
                const Icon(
                  FluentIcons.skype_circle_clock,
                  color: Colors.white,
                  size: 11,
                ),
                Text(
                  "${widget.item.duration} ${txt("min")}",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOperatorsPill() {
    final selectedIds = widget.item.operatorsIDs.toSet();
    final ops = accounts.operators;
    final display = ops.where((o) => selectedIds.contains(o.id)).toList();
    final label = display.isEmpty
        ? widget.item.subtitleLine2
        : display.map((o) => accounts.name(o)).join(", ");
    return FlyoutTarget(
      controller: _operatorsFlyout,
      child: GestureDetector(
        onTap: () {
          if (_operatorsFlyout.isOpen) {
            _operatorsFlyout.close();
          } else {
            _operatorsFlyout.showFlyout(
              builder: (ctx) => _buildOperatorsFlyoutContent(ctx, ops),
            );
          }
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            width: 50,
            child: Txt(
              label.isEmpty ? txt("unassigned") : label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                decorationStyle: TextDecorationStyle.wavy,
                decoration: TextDecoration.underline,
                color: selectedIds.isNotEmpty ? widget.color : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOperatorsFlyoutContent(BuildContext ctx, List ops) {
    return StatefulBuilder(
      builder: (ctx, flyoutSetState) {
        final selectedIds = widget.item.operatorsIDs.toSet();
        return Container(
          constraints: const BoxConstraints(maxHeight: 300, maxWidth: 220),
          decoration: BoxDecoration(
            color: FluentTheme.of(ctx).resources.solidBackgroundFillColorBase,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Row(children: [
                  Icon(FluentIcons.people,
                      size: 14, color: FluentTheme.of(ctx).inactiveColor),
                  const SizedBox(width: 8),
                  Text(txt("selectDoctors"),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
              ),
              const Divider(size: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: ops.map((op) {
                    final checked = selectedIds.contains(op.id);
                    void toggle() {
                      if (checked) {
                        widget.item.operatorsIDs.remove(op.id);
                      } else {
                        widget.item.operatorsIDs.add(op.id);
                      }
                      appointments.set(widget.item);
                      flyoutSetState(() {});
                      setState(() {});
                    }

                    return GestureDetector(
                      onTap: toggle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(children: [
                          Checkbox(
                            checked: checked,
                            onChanged: (_) => toggle(),
                          ),
                          const SizedBox(width: 8),
                          Text(accounts.name(op),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: checked
                                      ? FontWeight.w600
                                      : FontWeight.normal)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconButton _buildBringToFrontButton() {
    return IconButton(
        icon: const Icon(FluentIcons.open_in_new_tab),
        onPressed: () {
          final index =
              routes.panels().indexWhere((p) => p.item.id == widget.item.id);
          if (index == -1) return;
          routes.bringPanelToFront(index);
        });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chair info (operator column metadata)
// ─────────────────────────────────────────────────────────────────────────────

class ChairInfo {
  final String id;
  final String name;
  final Color color;
  const ChairInfo({required this.id, required this.name, required this.color});
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 5.0;
    const gapWidth = 5.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + dashWidth).clamp(0, size.width), size.height / 2),
        paint,
      );
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
