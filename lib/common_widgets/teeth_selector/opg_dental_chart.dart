import 'dart:async';
import 'dart:math' as math;

import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_state_wheel.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/app_flyout_controller.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart';

part 'opg_geometry.dart';
part 'opg_tooth_column.dart';
part 'opg_painters.dart';
part 'opg_tooth_painter.dart';
part 'opg_tooth_geometry.dart';

/// Minimum width for the panoramic chart; narrower viewports fall back to the
/// compact arch.
const double kOpgViewportMinWidth = 900.0;

Color _neutralHistoryColor(bool darkMode) =>
    darkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

const List<Color> _lightArchWellColors = [
  Color(0xFFEDF2F8),
  Color(0xFFF7FAFC),
  Color(0xFFE5ECF4),
  Color(0xFFF7FAFC),
  Color(0xFFEDF2F8),
];

const List<Color> _darkArchWellColors = [
  Color(0xFF0A1018),
  Color(0xFF111A27),
  Color(0xFF090E15),
  Color(0xFF111A27),
  Color(0xFF0A1018),
];

// the base wash's low saturation is boosted so the tint's hue shows, then
// clamped so it stays pale.
double _wellTintSaturation(HSLColor wash, bool darkMode) =>
    (wash.saturation * (darkMode ? 2.0 : 1.9)).clamp(0.0, 1.0).toDouble();

// recolours base to tint's hue, keeping its lightness and alpha so the wash
// stays a pale radiograph.
Color _tintedWell(Color base, Color? tint, bool darkMode) {
  if (tint == null) return base;
  final wash = HSLColor.fromColor(base);
  return HSLColor.fromAHSL(
    wash.alpha,
    HSLColor.fromColor(tint).hue,
    _wellTintSaturation(wash, darkMode),
    wash.lightness,
  ).toColor();
}

/// The wash the arch sits in, coloured by the kind of record the chart edits.
LinearGradient _archWellGradient(bool darkMode, Color? tint) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        for (final color
            in darkMode ? _darkArchWellColors : _lightArchWellColors)
          _tintedWell(color, tint, darkMode),
      ],
      stops: const [0.0, 0.36, 0.5, 0.64, 1.0],
    );

/// FDI order, patient's right to left (18..11 then 21..28).
const List<String> kOpgUpperPermanent = [
  '18', '17', '16', '15', '14', '13', '12', '11', //
  '21', '22', '23', '24', '25', '26', '27', '28', //
];

/// FDI order, patient's right to left (48..41 then 31..38).
const List<String> kOpgLowerPermanent = [
  '48', '47', '46', '45', '44', '43', '42', '41', //
  '31', '32', '33', '34', '35', '36', '37', '38', //
];

/// FDI order, patient's right to left (55..51 then 61..65).
const List<String> kOpgUpperPrimary = [
  '55', '54', '53', '52', '51', //
  '61', '62', '63', '64', '65', //
];

/// FDI order, patient's right to left (85..81 then 71..75).
const List<String> kOpgLowerPrimary = [
  '85', '84', '83', '82', '81', //
  '71', '72', '73', '74', '75', //
];

class OpgDentalChart extends StatefulWidget {
  const OpgDentalChart({
    super.key,
    required this.currentNotes,
    required this.oldNotes,
    required this.extraNotes,
    required this.leftString,
    required this.rightString,
    required this.notation,
    required this.onNote,
    required this.type,
    required this.showPermanent,
    required this.showPrimary,
    required this.onShowPermanentChanged,
    required this.onShowPrimaryChanged,
    this.isCompactArch = false,
    this.fillCompactHeight = false,
    this.onExtraNote,
    this.textStyle,
    this.history = const [],
    this.historyTitle = 'toothHistory',
    this.onOpenAppointment,
    this.tint,
  });

  final Map<String, String> currentNotes;
  final Map<String, String> oldNotes;
  final Map<String, String> extraNotes;
  final String leftString;
  final String rightString;
  final String Function(String isoString) notation;
  final void Function(String tooth, String? note) onNote;
  final void Function(String tooth, String extraNote)? onExtraNote;
  final StateType type;
  final bool showPermanent;
  final bool showPrimary;
  final ValueChanged<bool> onShowPermanentChanged;
  final ValueChanged<bool> onShowPrimaryChanged;
  final bool isCompactArch;
  final bool fillCompactHeight;
  final TextStyle? textStyle;
  final List<ToothHistory> history;
  final String historyTitle;
  final ValueChanged<String>? onOpenAppointment;

  /// Record-kind colour (violet for a visit, blue for a plan); it tints the
  /// background only, never the teeth. Null keeps the neutral wash.
  final Color? tint;

  @override
  State<OpgDentalChart> createState() => _OpgDentalChartState();
}

class _OpgDentalChartState extends State<OpgDentalChart> {
  String? _hoveredIso;

  // Entries for [iso], newest first; a condition already shown by a newer entry
  // is dropped so the same treatment never repeats beside the tooth.
  List<_ToothHistoryEntry> _entriesForTooth(String iso) {
    final entries = <_ToothHistoryEntry>[];
    final seenConditions = <String>{};
    final seenSignatures = <String>{};

    void addIfUnique(_ToothHistoryEntry candidate) {
      final cond = candidate.condition?.trim() ?? '';
      final extra = candidate.extraNote?.trim() ?? '';
      if (cond.isEmpty && extra.isEmpty) return;

      final effectiveCond =
          (cond.isNotEmpty && seenConditions.contains(cond)) ? '' : cond;
      if (effectiveCond.isEmpty && extra.isEmpty) return;

      final signature = '$effectiveCond|$extra';
      if (!seenSignatures.add(signature)) return;

      if (cond.isNotEmpty) seenConditions.add(cond);
      entries.add(_ToothHistoryEntry(
        isCurrentDraft: candidate.isCurrentDraft,
        label: candidate.label,
        condition: effectiveCond.isEmpty ? null : effectiveCond,
        extraNote: extra.isEmpty ? null : extra,
        appointmentId: candidate.appointmentId,
        isBaseline: candidate.isBaseline,
      ));
    }

    final current = widget.currentNotes[iso];
    final currentExtra = widget.extraNotes[iso];
    if ((current != null && current.isNotEmpty) ||
        (currentExtra != null && currentExtra.isNotEmpty)) {
      addIfUnique(_ToothHistoryEntry(
        isCurrentDraft: true,
        label: txt(widget.type == StateType.state ? 'dentalNotes' : 'today'),
        condition: current,
        extraNote: currentExtra,
      ));
    }

    final matchedHistory = widget.history
        .where((record) =>
            record.teeth.containsKey(iso) ||
            record.notes[iso]?.isNotEmpty == true)
        .toList()
      ..sort((a, b) =>
          (b.date ?? DateTime(9999)).compareTo(a.date ?? DateTime(9999)));

    for (final record in matchedHistory) {
      addIfUnique(_ToothHistoryEntry(
        isCurrentDraft: false,
        label: record.label,
        condition: record.teeth[iso],
        extraNote: record.notes[iso],
        appointmentId: record.appointmentId,
        isBaseline: record.date == null,
      ));
    }

    final oldNote = widget.oldNotes[iso];
    if (matchedHistory.isEmpty && oldNote != null && oldNote.isNotEmpty) {
      addIfUnique(_ToothHistoryEntry(
        isCurrentDraft: false,
        label: txt('dentalNotes'),
        condition: oldNote,
        isBaseline: true,
      ));
    }

    return entries;
  }

  // Operation layers for [iso], oldest first with the current draft last so it
  // paints on top; history uses the neutral tone.
  List<_ToothOperationLayer> _operationLayersForTooth(
      String iso, bool darkMode) {
    final layers = <_ToothOperationLayer>[];
    final seen = <String>{};
    final neutralColor = _neutralHistoryColor(darkMode);

    final chronologicalHistory = widget.history
        .where((r) => r.teeth[iso] != null && r.teeth[iso]!.trim().isNotEmpty)
        .toList()
      ..sort((a, b) =>
          (a.date ?? DateTime(1900)).compareTo(b.date ?? DateTime(1900)));

    for (final record in chronologicalHistory) {
      final op = record.teeth[iso]!.trim();
      if (seen.add(op)) {
        layers.add(_ToothOperationLayer(
          operation: op,
          color: neutralColor,
          isCurrentDraft: false,
        ));
      }
    }

    final oldNote = widget.oldNotes[iso]?.trim();
    if (oldNote != null && oldNote.isNotEmpty && seen.add(oldNote)) {
      layers.add(_ToothOperationLayer(
        operation: oldNote,
        color: neutralColor,
        isCurrentDraft: false,
      ));
    }

    final current = widget.currentNotes[iso]?.trim();
    if (current != null && current.isNotEmpty) {
      layers.removeWhere((l) => l.operation == current);
      layers.add(_ToothOperationLayer(
        operation: current,
        color: labelToColor(current),
        isCurrentDraft: true,
      ));
    }

    return layers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final mediaHeight = MediaQuery.sizeOf(context).height;
    final showInlineHistory = mediaHeight >= 500;

    final archWellBg = _tintedWell(
      darkMode ? const Color(0xFF0A0F16) : const Color(0xFFF3F6FA),
      widget.tint,
      darkMode,
    );
    final borderColor = darkMode
        ? const Color(0xFF233044)
        : theme.inactiveColor.withValues(alpha: 0.22);

    if (widget.isCompactArch) {
      return _buildCompactChart(
        context: context,
        darkMode: darkMode,
        wellBg: archWellBg,
        borderColor: borderColor,
      );
    }

    return Directionality(
      // OPG orientation: patient's right on viewer left, independent of text
      // direction.
      textDirection: TextDirection.ltr,
      child: Container(
        key: const ValueKey('opg-dental-chart'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(context, darkMode),
            const SizedBox(height: 8),
            if (widget.showPermanent)
              _buildArchWell(
                context: context,
                darkMode: darkMode,
                wellBg: archWellBg,
                borderColor: borderColor,
                upperIsos: kOpgUpperPermanent,
                lowerIsos: kOpgLowerPermanent,
                isPrimary: false,
                showInlineHistory: showInlineHistory,
              ),
            if (widget.showPermanent && widget.showPrimary)
              const SizedBox(height: 10),
            if (widget.showPrimary)
              _buildArchWell(
                context: context,
                darkMode: darkMode,
                wellBg: archWellBg,
                borderColor: borderColor,
                upperIsos: kOpgUpperPrimary,
                lowerIsos: kOpgLowerPrimary,
                isPrimary: true,
                showInlineHistory: showInlineHistory,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool darkMode) {
    final theme = FluentTheme.of(context);
    final pillColor = darkMode
        ? const Color(0xFF182232)
        : theme.inactiveBackgroundColor.withValues(alpha: 0.7);
    final labelStyle = (widget.textStyle ?? theme.typography.caption)!.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 0.6,
      color: darkMode ? const Color(0xFF8EA4C8) : theme.inactiveColor,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _orientationBadge(
          widget.rightString,
          'R',
          pillColor,
          labelStyle,
          compact: widget.isCompactArch,
        ),
        Flexible(
          child: Directionality(
            textDirection: locale.isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    checked: widget.showPermanent,
                    onChanged: (checked) =>
                        widget.onShowPermanentChanged(checked == true),
                    content: Txt(
                      txt('showPermanent'),
                      style: theme.typography.caption?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Checkbox(
                    checked: widget.showPrimary,
                    onChanged: (checked) =>
                        widget.onShowPrimaryChanged(checked == true),
                    content: Txt(
                      txt('showPrimary'),
                      style: theme.typography.caption?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _orientationBadge(
          widget.leftString,
          'L',
          pillColor,
          labelStyle,
          compact: widget.isCompactArch,
        ),
      ],
    );
  }

  Widget _orientationBadge(
    String text,
    String marker,
    Color bg,
    TextStyle style, {
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: style.color?.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              marker,
              style: style.copyWith(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
          if (!compact) Text(text, style: style),
        ],
      ),
    );
  }

  Widget _buildCompactChart({
    required BuildContext context,
    required bool darkMode,
    required Color wellBg,
    required Color borderColor,
  }) {
    final mediaHeight = MediaQuery.sizeOf(context).height;
    // the chart gets the viewport minus ~190px of chrome (or all of it when
    // filling the screen); 380 is the floor that keeps teeth legible.
    final room = math.max(
        380.0, widget.fillCompactHeight ? mediaHeight : mediaHeight - 190.0);

    final currentLegendNotes = <String>{
      ...widget.currentNotes.values.where((x) => x.isNotEmpty).map(
          (x) => txOptions.where((y) => y.label == x).isEmpty ? 'other' : x),
    };
    final historicalLegendNotes = <String>{
      ...[
        ...widget.oldNotes.values,
        for (final h in widget.history) ...h.teeth.values,
      ].where((x) => x.isNotEmpty).map(
          (x) => txOptions.where((y) => y.label == x).isEmpty ? 'other' : x),
    }..removeAll(currentLegendNotes);
    final hasLegend =
        currentLegendNotes.isNotEmpty || historicalLegendNotes.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        key: const ValueKey('opg-dental-chart'),
        width: double.infinity,
        height: room,
        decoration: BoxDecoration(
          color: wellBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor.withValues(alpha: 0.7)),
          gradient: _archWellGradient(darkMode, widget.tint),
        ),
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(context, darkMode),
            const SizedBox(height: 2),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _buildCompactCanvas(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  darkMode: darkMode,
                ),
              ),
            ),
            if (hasLegend) ...[
              const SizedBox(height: 4),
              Directionality(
                textDirection:
                    locale.isRtl ? TextDirection.rtl : TextDirection.ltr,
                child: Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final note in currentLegendNotes)
                      _buildLegendChip(
                        context,
                        note,
                        neutral: false,
                        darkMode: darkMode,
                        compact: true,
                      ),
                    for (final note in historicalLegendNotes)
                      _buildLegendChip(
                        context,
                        note,
                        neutral: true,
                        darkMode: darkMode,
                        compact: true,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // compact mode shows one dentition at a time: showPrimary is ignored, and
  // the primary arch is the inverse of showPermanent.
  Widget _buildCompactCanvas({
    required double width,
    required double height,
    required bool darkMode,
  }) {
    if (width <= 0 || height <= 0) return const SizedBox.shrink();

    final primary = !widget.showPermanent;
    final pair = _layoutCompactPair(
      width: width,
      band: Rect.fromLTWH(0, 0, width, height),
      upperIsos: primary ? kOpgUpperPrimary : kOpgUpperPermanent,
      lowerIsos: primary ? kOpgLowerPrimary : kOpgLowerPermanent,
      toothBand: (width * 0.048).clamp(12.0, 20.0),
      jawGap: 10.0,
      // a drawn crown is narrower than its normalized box, so cells are widened
      // past their arc share to close the interproximal gaps.
      toothFill: 1.12,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child:
                CustomPaint(painter: _CompactArchPainter(darkMode: darkMode)),
          ),
        ),
        ..._compactPairCells(pair, isPrimary: primary, darkMode: darkMode),
      ],
    );
  }

  List<Widget> _compactPairCells(
    _CompactPairLayout pair, {
    required bool isPrimary,
    required bool darkMode,
  }) {
    return [
      for (final seat in pair.upperSeats)
        _compactTooth(
          seat: seat,
          origin: pair.upperCenter,
          toothBand: pair.toothBand,
          isUpper: true,
          isPrimary: isPrimary,
          darkMode: darkMode,
        ),
      for (final seat in pair.lowerSeats)
        _compactTooth(
          seat: seat,
          origin: pair.lowerCenter,
          toothBand: pair.toothBand,
          isUpper: false,
          isPrimary: isPrimary,
          darkMode: darkMode,
        ),
    ];
  }

  Widget _compactTooth({
    required _ArchSeat seat,
    required Offset origin,
    required double toothBand,
    required bool isUpper,
    required bool isPrimary,
    required bool darkMode,
  }) {
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: origin + seat.center,
        width: seat.drawSpan,
        height: seat.length + toothBand * 1.1,
      ),
      child: _OpgToothColumn(
        key: ValueKey('opg-col-${seat.iso}'),
        compact: true,
        compactBand: toothBand,
        compactSpan: seat.span,
        compactWidth: seat.drawSpan,
        archRotation: seat.rotation,
        iso: seat.iso,
        isUpper: isUpper,
        isPrimary: isPrimary,
        drawingHeight: seat.length,
        currentNote: widget.currentNotes[seat.iso],
        oldNote: widget.oldNotes[seat.iso],
        extraNote: widget.extraNotes[seat.iso] ?? '',
        history: widget.history,
        historyTitle: widget.historyTitle,
        historyEntries: _entriesForTooth(seat.iso),
        operationLayers: _operationLayersForTooth(seat.iso, darkMode),
        notation: widget.notation,
        type: widget.type,
        onNote: widget.onNote,
        onExtraNote: widget.onExtraNote,
        onOpenAppointment: widget.onOpenAppointment,
        isHovered: _hoveredIso == seat.iso,
        onHoverChanged: (hovered) {
          setState(() {
            if (hovered) {
              _hoveredIso = seat.iso;
            } else if (_hoveredIso == seat.iso) {
              _hoveredIso = null;
            }
          });
        },
      ),
    );
  }

  Widget _buildLegendChip(
    BuildContext context,
    String note, {
    required bool neutral,
    required bool darkMode,
    bool compact = false,
  }) {
    final color = neutral ? _neutralHistoryColor(darkMode) : labelToColor(note);
    final icon = labelToIcon(note);
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 5,
        vertical: compact ? 2 : 3,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: compact ? 11 : 12),
          SizedBox(width: compact ? 3 : 4),
          Txt(
            txt(note),
            style: FluentTheme.of(context).typography.caption!.copyWith(
                  color: Colors.white,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchWell({
    required BuildContext context,
    required bool darkMode,
    required Color wellBg,
    required Color borderColor,
    required List<String> upperIsos,
    required List<String> lowerIsos,
    required bool isPrimary,
    required bool showInlineHistory,
  }) {
    final halfCount = upperIsos.length ~/ 2;
    final toothDrawingHeight = isPrimary ? 102.0 : 128.0;

    return Container(
      decoration: BoxDecoration(
        color: wellBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor.withValues(alpha: 0.7)),
        gradient: _archWellGradient(darkMode, widget.tint),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isPrimary ? 48 : 8,
        vertical: 8,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _OpgBackdropPainter(
                  darkMode: darkMode,
                  isPrimary: isPrimary,
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildJawRow(
                context: context,
                isos: upperIsos,
                halfCount: halfCount,
                isUpper: true,
                isPrimary: isPrimary,
                drawingHeight: toothDrawingHeight,
                showInlineHistory: showInlineHistory,
                darkMode: darkMode,
              ),
              _buildOcclusalPlaneDivider(context, darkMode, isPrimary),
              _buildJawRow(
                context: context,
                isos: lowerIsos,
                halfCount: halfCount,
                isUpper: false,
                isPrimary: isPrimary,
                drawingHeight: toothDrawingHeight,
                showInlineHistory: showInlineHistory,
                darkMode: darkMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOcclusalPlaneDivider(
    BuildContext context,
    bool darkMode,
    bool isPrimary,
  ) {
    final lineColor = darkMode
        ? const Color(0xFF334766).withValues(alpha: 0.75)
        : const Color(0xFF9EB0C7).withValues(alpha: 0.65);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 12,
        child: CustomPaint(
          size: const Size(double.infinity, 12),
          painter: _OcclusalCurvePainter(
            color: lineColor,
            isPrimary: isPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildJawRow({
    required BuildContext context,
    required List<String> isos,
    required int halfCount,
    required bool isUpper,
    required bool isPrimary,
    required double drawingHeight,
    required bool showInlineHistory,
    required bool darkMode,
  }) {
    final midColor = darkMode
        ? const Color(0xFF334766).withValues(alpha: 0.65)
        : const Color(0xFF9EB0C7).withValues(alpha: 0.55);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < isos.length; i++) ...[
            if (i == halfCount)
              Container(
                width: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                decoration: BoxDecoration(
                  color: midColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            Expanded(
              flex: _columnFlexForIso(isos[i]),
              child: _OpgToothColumn(
                key: ValueKey('opg-col-${isos[i]}'),
                iso: isos[i],
                isUpper: isUpper,
                isPrimary: isPrimary,
                drawingHeight: drawingHeight,
                currentNote: widget.currentNotes[isos[i]],
                oldNote: widget.oldNotes[isos[i]],
                extraNote: widget.extraNotes[isos[i]] ?? '',
                history: widget.history,
                historyTitle: widget.historyTitle,
                historyEntries: showInlineHistory
                    ? _entriesForTooth(isos[i])
                    : const <_ToothHistoryEntry>[],
                operationLayers: _operationLayersForTooth(isos[i], darkMode),
                notation: widget.notation,
                type: widget.type,
                onNote: widget.onNote,
                onExtraNote: widget.onExtraNote,
                onOpenAppointment: widget.onOpenAppointment,
                isHovered: _hoveredIso == isos[i],
                onHoverChanged: (hovered) {
                  setState(() {
                    if (hovered) {
                      _hoveredIso = isos[i];
                    } else if (_hoveredIso == isos[i]) {
                      _hoveredIso = null;
                    }
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _columnFlexForIso(String iso) => _toothWidthWeight(iso);
}

// mesiodistal width weight for [iso]: molars broadest, lower central incisor
// narrowest; sizes both a flat column and a compact tooth's share of the arc.
int _toothWidthWeight(String iso) {
  final q = int.parse(iso[0]);
  final pos = int.parse(iso[1]);
  if (q >= 5) {
    return switch (pos) {
      1 => 9,
      2 => 8,
      3 => 9,
      4 => 11,
      5 => 12,
      _ => 10,
    };
  }
  final isUpper = q == 1 || q == 2;
  return switch (pos) {
    1 => isUpper ? 10 : 8,
    2 => isUpper ? 8 : 9,
    3 => 9,
    4 => 10,
    5 => 10,
    6 => 13,
    7 => 12,
    8 => 11,
    _ => 10,
  };
}
