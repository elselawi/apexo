import 'dart:async';
import 'dart:math' as math;

import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_state_wheel.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart';

/// Minimum viewport width at which the OPG panoramic dental chart activates
/// and the panel widens to give the full 16-column dental arch comfortable
/// breathing room without blocking the underlying clinic screen. Narrower
/// viewports (phones, small tablets) get the compact elliptical arch instead.
const double kOpgViewportMinWidth = 1000.0;

/// Width of the side panel when a dental chart tab is active on a wide screen.
const double kOpgWidePanelWidth = 960.0;

/// Neutral silver-slate palette used for treatments/notes that came from
/// another appointment or record (not registered in the current draft).
Color _neutralHistoryColor(bool darkMode) =>
    darkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

/// The radiographic wash the arch sits in: brighter through the middle of the
/// mouth, where the jaws part, and cooler towards the bone at either end.
LinearGradient _archWellGradient(bool darkMode) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: darkMode
          ? const [
              Color(0xFF0A1018),
              Color(0xFF111A27),
              Color(0xFF090E15),
              Color(0xFF111A27),
              Color(0xFF0A1018),
            ]
          : const [
              Color(0xFFEDF2F8),
              Color(0xFFF7FAFC),
              Color(0xFFE5ECF4),
              Color(0xFFF7FAFC),
              Color(0xFFEDF2F8),
            ],
      stops: const [0.0, 0.36, 0.5, 0.64, 1.0],
    );

/// Upper permanent teeth in standard panoramic (OPG) order:
/// patient's right (18..11) to patient's left (21..28).
const List<String> kOpgUpperPermanent = [
  '18', '17', '16', '15', '14', '13', '12', '11', //
  '21', '22', '23', '24', '25', '26', '27', '28', //
];

/// Lower permanent teeth in standard panoramic (OPG) order:
/// patient's right (48..41) to patient's left (31..38).
const List<String> kOpgLowerPermanent = [
  '48', '47', '46', '45', '44', '43', '42', '41', //
  '31', '32', '33', '34', '35', '36', '37', '38', //
];

/// Upper primary (deciduous) teeth in panoramic order:
/// patient's right (55..51) to patient's left (61..65).
const List<String> kOpgUpperPrimary = [
  '55', '54', '53', '52', '51', //
  '61', '62', '63', '64', '65', //
];

/// Lower primary (deciduous) teeth in panoramic order:
/// patient's right (85..81) to patient's left (71..75).
const List<String> kOpgLowerPrimary = [
  '85', '84', '83', '82', '81', //
  '71', '72', '73', '74', '75', //
];

/// Panoramic (OPG-style) dental chart for wide screens (PCs and tablets).
///
/// Renders anatomically accurate labial/buccal silhouettes with roots, pulp
/// chambers, cusps, and occlusal/incisal contours for every tooth type,
/// layered clinical drawings for all treatment/state types (clipped cleanly to
/// the tooth's own crown/root contours so multiple operations overlap
/// harmoniously), flat shadow-free icons at the root apex (using a `Wrap` when
/// multiple treatments are applied), and 90°-rotated treatment labels tucked
/// beside each tooth.
///
/// Operations and notes from earlier appointments/records are rendered in a
/// neutral radiographic grey/silver palette so only treatments registered in
/// the current record carry vibrant colors.
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
    this.onExtraNote,
    this.textStyle,
    this.history = const [],
    this.historyTitle = 'toothHistory',
    this.onOpenAppointment,
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
  final TextStyle? textStyle;
  final List<ToothHistory> history;
  final String historyTitle;
  final ValueChanged<String>? onOpenAppointment;

  @override
  State<OpgDentalChart> createState() => _OpgDentalChartState();
}

class _OpgDentalChartState extends State<OpgDentalChart> {
  String? _hoveredIso;

  /// Collects all historical and current entries for [iso], ordered newest
  /// first for the beside-tooth rotated labels.
  ///
  /// Deduplicates entries whose displayed text (condition + extra note) is
  /// already shown by the current draft or a newer historical entry, so the
  /// same treatment/note is never repeated twice beside the tooth.
  List<_ToothHistoryEntry> _entriesForTooth(String iso) {
    final entries = <_ToothHistoryEntry>[];
    final seenConditions = <String>{};
    final seenSignatures = <String>{};

    void addIfUnique(_ToothHistoryEntry candidate) {
      final cond = candidate.condition?.trim() ?? '';
      final extra = candidate.extraNote?.trim() ?? '';
      if (cond.isEmpty && extra.isEmpty) return;

      // If this historical entry has the same condition as the current chart
      // (or a newer entry) and no distinct extra note, skip it altogether.
      // If it has the same condition AND a different extra note, keep only the
      // extra note so the treatment name isn't duplicated.
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

  /// Collects all operations/states recorded on [iso] in chronological order
  /// (oldest first, current draft last) so that multiple operations overlap
  /// naturally on the tooth drawing.
  ///
  /// Historical operations (from other appointments/records) lose their bright
  /// color and use a neutral radiographic tone, while the operation registered
  /// in the current draft retains its full color.
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

    final archWellBg =
        darkMode ? const Color(0xFF0A0F16) : const Color(0xFFF3F6FA);
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
      // Standard OPG radiographic orientation: Patient Right on viewer left,
      // Patient Left on viewer right, regardless of text directionality.
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

  /// Compact arch layout for phones and narrow panels
  /// (`< kOpgViewportMinWidth`): both jaws are drawn as facing anatomical
  /// arches — the two 16-tooth rows curve around the canines at the corners of
  /// the arch, spending vertical room instead of width — with roots pointing
  /// outward and crowns inward, the way an odontogram reads.
  ///
  /// One well holds the whole chart — the orientation markers, the switches,
  /// both arches and the colour key — so none of the width the panel gives is
  /// spent on padding, and the mouth is laid out in the space that is left.
  Widget _buildCompactChart({
    required BuildContext context,
    required bool darkMode,
    required Color wellBg,
    required Color borderColor,
  }) {
    final mediaHeight = MediaQuery.sizeOf(context).height;
    // Give the compact arch generous vertical room so teeth are large, crisp,
    // and clinical marks/icons/drawings are clearly visible, while still
    // fitting a phone viewport without scrolling.
    final room = math.max(380.0, mediaHeight - 190.0);

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
          gradient: _archWellGradient(darkMode),
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

  /// The mouth itself: one facing pair of arches, and only ever one dentition —
  /// a phone has room for the permanent teeth or the primary ones, not both, so
  /// the switches pick between them.
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
      // A drawn crown is narrower than its normalized [-1, 1] box, so drawing
      // each cell slightly wider than its arc share lets adjacent crowns make
      // realistic interproximal contact while leaving room for the ovoid/
      // pyramidal arch splay out to the panel edges.
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
        gradient: _archWellGradient(darkMode),
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

  /// Anatomical mesiodistal width weights so molars are naturally broader than
  /// premolars, canines, and incisors, and upper central incisors are broader
  /// than upper lateral incisors, while lower central incisors are the
  /// narrowest teeth in the mouth.
  int _columnFlexForIso(String iso) => _toothWidthWeight(iso);
}

/// Anatomical mesiodistal width weight of [iso]: molars are broader than
/// premolars, canines, and incisors, an upper central incisor is broader than
/// its lateral neighbour, and a lower central incisor is the narrowest tooth in
/// the mouth. Used both to size a column of the flat chart and to hand a tooth
/// its share of the compact arch's curve.
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

/// One tooth's seat on a compact arch: the point of the ellipse its centre sits
/// on (relative to the jaw's ellipse centre), the rotation that turns its root
/// outward, and the arc length its share of the curve spans — which is what
/// sizes the tooth.
class _ArchSeat {
  const _ArchSeat({
    required this.iso,
    required this.center,
    required this.rotation,
    required this.span,
    required this.drawSpan,
    required this.length,
  });

  final String iso;
  final Offset center;
  final double rotation;

  /// Arc length the tooth owns on the curve.
  final double span;

  /// Width the tooth is drawn at, which is its own share of the curve.
  final double drawSpan;

  /// Root-to-crown drawing height. Anterior teeth (incisors and canines) are
  /// elongated vertically to utilize the vertical room at the top and bottom
  /// of the arch.
  final double length;
}

/// Places [isos] along one jaw's arch, sizing them by their share of the curve
/// so a molar still reads wider than an incisor on a phone. The seats come back
/// relative to the jaw's centre.
///
/// The teeth stand on the anatomical ovoid/pyramidal arch line their *crowns*
/// trace:
/// - Central and lateral incisors (`pos 1, 2`) sit along the anterior segment
///   with a slight midline diastema/gap between the two centrals and extra
///   breathing room + gentle rotation on the laterals.
/// - Canines (`pos 3`) sit squarely at the corner bend of the arch.
/// - Premolars and molars (`pos 4..8`) diverge progressively outward toward the
///   wisdom teeth, forming a pyramid on the upper jaw (and an inverted pyramid
///   on the lower jaw) that reaches the left and right edges of the chart.
List<_ArchSeat> _seatsAlongArch({
  required List<String> isos,
  required bool isUpper,
  required double rx,
  required double ry,
  double toothFill = 1.0,
}) {
  final weights = [
    for (final iso in isos) _toothWidthWeight(iso).toDouble(),
  ];
  final total = weights.fold<double>(0, (sum, weight) => sum + weight);

  // Average tooth span estimate so the crown curve sits inside the outer arch
  // boundary by the radial distance from crown to root tip.
  final approxArc = _archArc(rx: rx, ry: ry);
  final avgDrawSpan = (approxArc / isos.length) * toothFill;
  final avgHalfLen = avgDrawSpan * 0.78;

  // Keep a small radial inset at the top/bottom (where incisors stand upright)
  // and a slightly smaller horizontal inset at the posterior ends (where tilted
  // wisdom teeth reach outward).
  final crownRx = math.max(12.0, rx - avgHalfLen * 0.62);
  final crownRy = math.max(12.0, ry - avgHalfLen * 0.85);

  Offset crownPoint(double progress) =>
      _archPointAt(progress, rx: crownRx, ry: crownRy);

  // Arc-length parameterization table so every tooth receives its exact
  // mesiodistal share of the arch curve.
  const steps = 240;
  final lengths = List<double>.filled(steps + 1, 0);
  var previous = crownPoint(0);
  for (var step = 1; step <= steps; step++) {
    final point = crownPoint(step / steps);
    lengths[step] = lengths[step - 1] + (point - previous).distance;
    previous = point;
  }
  final arc = lengths[steps];

  double progressForShare(double share) {
    final target = share.clamp(0.0, 1.0) * arc;
    var low = 0;
    var high = steps;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lengths[middle] < target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final index = low.clamp(1, steps);
    final segment = lengths[index] - lengths[index - 1];
    final within = segment == 0 ? 0.0 : (target - lengths[index - 1]) / segment;
    return (index - 1 + within) / steps;
  }

  // Anchor the canine (`pos 3`) at the exact midpoint of the arch corner, and
  // keep the four incisors (`pos 1, 2` on both sides) inside the anterior
  // segment with breathing room between the two centrals and between each
  // lateral and its neighbouring central.
  final cornerBounds = _archCornerShareBounds(rx: crownRx, ry: crownRy);
  final anteriorStartIdx = isos.indexWhere((iso) => iso.endsWith('2'));
  final canineIdx = isos.indexWhere((iso) => iso.endsWith('3'));

  double weightUpTo(int endExclusive) {
    var s = 0.0;
    for (var i = 0; i < endExclusive; i++) {
      s += weights[i];
    }
    return s / total;
  }

  final rightCanineMidRaw = canineIdx >= 0
      ? weightUpTo(canineIdx) + (weights[canineIdx] / total) * 0.5
      : 0.0;
  final rightAnteriorStartRaw =
      anteriorStartIdx > 0 ? weightUpTo(anteriorStartIdx) : 0.0;
  final targetCanineMid = cornerBounds.rightCornerMid;
  final targetAnteriorStart = cornerBounds.rightCornerEnd;

  // Leave a distinct midline gap between the left and right central incisors
  // (`0.491` vs `0.509`), and shift the lateral incisors slightly outward
  // toward the canine corner so they have breathing room away from the
  // centrals.
  const midlineHalfGap = 0.009;
  const anteriorEnd = 0.5 - midlineHalfGap;

  double remapShare(double rawShare, int pos) {
    if (anteriorStartIdx <= 0 || canineIdx < 0) return rawShare;

    final mirrored = rawShare > 0.5;
    final s = mirrored ? (1.0 - rawShare) : rawShare;
    double mapped;
    if (s <= rightCanineMidRaw) {
      mapped = rightCanineMidRaw <= 0
          ? s
          : (s / rightCanineMidRaw) * targetCanineMid;
    } else if (s <= rightAnteriorStartRaw) {
      final t = (s - rightCanineMidRaw) /
          math.max(1e-6, rightAnteriorStartRaw - rightCanineMidRaw);
      mapped = targetCanineMid + t * (targetAnteriorStart - targetCanineMid);
    } else {
      final t = (s - rightAnteriorStartRaw) /
          math.max(1e-6, 0.5 - rightAnteriorStartRaw);
      mapped = targetAnteriorStart + t * (anteriorEnd - targetAnteriorStart);
      if (pos == 2) {
        // Nudge the lateral incisor slightly away from the central incisor for
        // extra interproximal breathing room.
        mapped -= 0.0045;
      }
    }
    return mirrored ? (1.0 - mapped) : mapped;
  }

  final half = (isos.length - 1) / 2;
  final avgAnteriorShare = (weights[isos.length ~/ 2] +
          weights[(isos.length ~/ 2 - 1).clamp(0, isos.length - 1)]) /
      (2 * total);

  // Anterior teeth (`pos 1, 2, 3`) get a larger width & vertical length boost
  // so they stand out prominently and utilize the vertical room at the top and
  // bottom of each arch.
  double widthFactorForPos(int pos) => switch (pos) {
        1 => 1.15,
        2 => 1.14,
        3 => 1.10,
        _ => 1.0,
      };

  double lengthAspectForPos(int pos) => switch (pos) {
        1 => 1.72,
        2 => 1.68,
        3 => 1.62,
        4 => 1.50,
        _ => 1.44,
      };

  final avgAnteriorLength = arc *
      avgAnteriorShare *
      toothFill *
      widthFactorForPos(1) *
      lengthAspectForPos(1);

  final seats = <_ArchSeat>[];
  var walked = 0.0;
  for (var index = 0; index < isos.length; index++) {
    final iso = isos[index];
    final pos = int.parse(iso[1]);
    final share = weights[index] / total;
    final midShare = remapShare(walked + share / 2, pos);
    final progress = progressForShare(midShare);
    final crown = crownPoint(progress);
    final rotation = _fanTilt(
      iso,
      index,
      half,
      isUpper: isUpper,
    );
    final span = arc * share;
    final drawSpan = span * toothFill * widthFactorForPos(pos);
    final length = drawSpan * lengthAspectForPos(pos);
    final isIncisor = (index - half).abs() <= 1.6;
    final centerOffsetLen =
        isIncisor ? (length * 0.45 + avgAnteriorLength * 0.55) : length;
    // The tooth grows outward from its crown, which is the point on the curve.
    final axis = _toothAxis(rotation, isUpper: isUpper);
    seats.add(_ArchSeat(
      iso: iso,
      center: (isUpper ? crown : Offset(crown.dx, -crown.dy)) +
          axis * (centerOffsetLen / 2),
      rotation: rotation,
      span: span,
      drawSpan: drawSpan,
      length: length,
    ));
    walked += share;
  }
  return seats;
}

/// How much of the notation's own size a compact tooth can carry: scaled down
/// so Palmer / ISO / Universal labels never overlap on small phone screens.
double _notationScale(double band, double toothSpan) => math.min(
      (band / 24.0).clamp(0.46, 0.72),
      toothSpan <= 0 ? 0.65 : (toothSpan / 29.0).clamp(0.44, 0.72),
    );

/// The length of the curve an [rx]×[ry] arch runs, which is also the total
/// width of the teeth that stand on it.
double _archArc({required double rx, required double ry}) {
  const steps = 80;
  var length = 0.0;
  var previous = _archPointAt(0, rx: rx, ry: ry);
  for (var step = 1; step <= steps; step++) {
    final point = _archPointAt(step / steps, rx: rx, ry: ry);
    length += (point - previous).distance;
    previous = point;
  }
  return length;
}

/// How far a tooth leans off upright, in radians, and which way.
///
/// Uses explicit anatomical tooth angles by position (`1..8` / `1..5`) so that:
/// - Central incisors (`pos 1`) stand nearly vertical (`~2°`).
/// - Lateral incisors (`pos 2`) have only a gentle tilt (`~9°`), staying part
///   of the anterior front row rather than turning the corner.
/// - Canines (`pos 3`) sit right at the ~38° corner angle of the arch.
/// - First and second premolars (`pos 4, 5`) and molars (`pos 6, 7, 8`) open
///   progressively along the ovoid/pyramidal buccal slope (`~50°–60°`).
double _fanTilt(
  String iso,
  int index,
  double half, {
  required bool isUpper,
}) {
  if (half <= 0) return 0;
  final pos = int.parse(iso[1]);
  final isPrimary = int.parse(iso[0]) >= 5;

  final double lean = isPrimary
      ? switch (pos) {
          1 => 0.04, // ~2.3°
          2 => 0.24, // ~13.8°
          3 => 0.64, // ~36.7° (canine at the arch corner)
          4 => 0.86, // ~49.3°
          _ => 0.96, // ~55.0°
        }
      : switch (pos) {
          1 => 0.035, // ~2.0°  central incisor (upright)
          2 => 0.23, // ~13.2° lateral incisor (gentle flair away from central)
          3 => 0.66, // ~37.8° canine (cornerstone at the angle of the arch)
          4 => 0.84, // ~48.1° first premolar
          5 => 0.90, // ~51.6° second premolar
          6 => 0.94, // ~53.9° first molar
          7 => 0.97, // ~55.6° second molar
          _ => 1.00, // ~57.3° wisdom tooth / third molar
        };

  final side = index < half ? -1.0 : 1.0;
  return lean * side * (isUpper ? 1 : -1);
}

/// The direction a tooth's root points in when it is turned by [rotation].
Offset _toothAxis(double rotation, {required bool isUpper}) => isUpper
    ? Offset(math.sin(rotation), -math.cos(rotation))
    : Offset(-math.sin(rotation), math.cos(rotation));

/// Share of `rx` occupied by the anterior incisor segment (`12–11–21–22`).
/// Sized so the two central incisors have a clear midline space between them
/// and the lateral incisors have breathing room away from the centrals while
/// the canines remain on the arch corners.
const double _archFrontHalfShare = 0.295;

/// Radius of the canine corner bend as a fraction of the smaller half-axis.
const double _archCornerShare = 0.22;

/// Outward divergence angle (radians, `~27.5°` off vertical) of the posterior
/// buccal segments from the canine corner out to the wisdom teeth: each
/// successive tooth (`4 -> 5 -> 6 -> 7 -> 8`) sits progressively further apart
/// horizontally than the pair before it, forming a pyramid on the upper jaw and
/// an inverted pyramid on the lower jaw.
const double _archPosteriorSplay = 0.48;

/// Returns the arc-length fractions along `_archPointAt` where the right-side
/// canine corner midpoint and inner end sit, so `_seatsAlongArch` can lock the
/// canine (`pos 3`) onto the corner and keep the lateral incisor (`pos 2`) on
/// the anterior segment.
({double rightCornerMid, double rightCornerEnd}) _archCornerShareBounds({
  required double rx,
  required double ry,
}) {
  final geom = _archCurveMetrics(rx: rx, ry: ry);
  if (geom.total <= 0) {
    return (rightCornerMid: 0.30, rightCornerEnd: 0.35);
  }
  return (
    rightCornerMid: (geom.sideLen + geom.bendLen * 0.5) / geom.total,
    rightCornerEnd: (geom.sideLen + geom.bendLen * 0.92) / geom.total,
  );
}

({
  double frontHalf,
  double corner,
  double sweep,
  double cosS,
  double sinS,
  double rightCx,
  double rightCy,
  Offset rightCornerStart,
  Offset rightEnd,
  double sideLen,
  double bendLen,
  double frontLen,
  double total,
}) _archCurveMetrics({required double rx, required double ry}) {
  final frontHalf = rx * _archFrontHalfShare;
  final maxCorner = math.min(rx - frontHalf, ry) * 0.55;
  final double corner = (math.min(rx, ry) * _archCornerShare)
      .clamp(2.0, math.max(2.0, maxCorner));

  const sweep = (math.pi / 2) - _archPosteriorSplay;
  final cosS = math.cos(_archPosteriorSplay);
  final sinS = math.sin(_archPosteriorSplay);

  final rightCx = -frontHalf;
  final rightCy = -(ry - corner);

  final rightCornerStart = Offset(
    rightCx - corner * cosS,
    rightCy - corner * sinS,
  );
  final rightEnd = Offset(-rx, 0);

  final sideLen = (rightCornerStart - rightEnd).distance;
  final bendLen = sweep * corner;
  final frontLen = 2 * frontHalf;
  final total = 2 * sideLen + 2 * bendLen + frontLen;

  return (
    frontHalf: frontHalf,
    corner: corner,
    sweep: sweep,
    cosS: cosS,
    sinS: sinS,
    rightCx: rightCx,
    rightCy: rightCy,
    rightCornerStart: rightCornerStart,
    rightEnd: rightEnd,
    sideLen: sideLen,
    bendLen: bendLen,
    frontLen: frontLen,
    total: total,
  );
}

/// A point along one jaw's anatomical ovoid/pyramidal arch curve.
///
/// [progress] runs `0 → 1` from the patient's right third molar (`18`/`48`) to
/// their left (`28`/`38`), laid out in upper-jaw coordinates (`y = -ry` at the
/// anterior midline, `y = 0` at the posterior ends):
/// 1. Patient's right posterior buccal segment (`18 → 14`), sloping inward from
///    `-rx` toward the canine corner so `18–28` are widest apart, `17–27`
///    slightly narrower, `16–26` narrower still, `15–25` narrower, and `14–24`
///    narrower approaching the canine.
/// 2. Right canine corner arc (`13`/`43`), where the buccal slope bends into
///    the anterior segment.
/// 3. Gently curved anterior incisor segment (`12, 11, 21, 22`).
/// 4. Left canine corner arc (`23`/`33`).
/// 5. Patient's left posterior buccal segment (`24 → 28`), flaring outward to
///    `+rx`.
Offset _archPointAt(
  double progress, {
  required double rx,
  required double ry,
}) {
  final m = _archCurveMetrics(rx: rx, ry: ry);
  if (m.total <= 0) return Offset.zero;

  var left = progress.clamp(0.0, 1.0) * m.total;

  // 1. Patient's right posterior buccal segment (18..14 -> 13): gently bowed
  // ovoid curve from (-rx, 0) up and inward to rightCornerStart.
  if (left <= m.sideLen) {
    final t = m.sideLen == 0 ? 0.0 : (left / m.sideLen).clamp(0.0, 1.0);
    // Slight outward ovoid belly so the molars/premolars trace a natural dental
    // arch while monotonically widening from 14 out to 18.
    final linear = Offset.lerp(m.rightEnd, m.rightCornerStart, t)!;
    final belly = math.sin(t * math.pi) * (rx - m.frontHalf) * 0.08;
    return Offset(linear.dx - belly, linear.dy);
  }
  left -= m.sideLen;

  // 2. Right canine corner (13 / 43)
  if (left <= m.bendLen) {
    final theta = (math.pi + _archPosteriorSplay) + (left / m.corner);
    return Offset(
      m.rightCx + m.corner * math.cos(theta),
      m.rightCy + m.corner * math.sin(theta),
    );
  }
  left -= m.bendLen;

  // 3. Anterior incisor segment (12, 11, 21, 22)
  if (left <= m.frontLen) {
    final u = m.frontLen == 0 ? 0.5 : (left / m.frontLen).clamp(0.0, 1.0);
    // Subtle anterior arch curvature (1.5px crown dome at central incisors) so
    // the four incisors stay level while reading as a natural anterior curve.
    final dome = math.sin(u * math.pi) * 1.5;
    return Offset(-m.frontHalf + left, -ry - dome);
  }
  left -= m.frontLen;

  // 4. Left canine corner (23 / 33)
  if (left <= m.bendLen) {
    final theta = (3 * math.pi / 2) + (left / m.corner);
    return Offset(
      m.frontHalf + m.corner * math.cos(theta),
      m.rightCy + m.corner * math.sin(theta),
    );
  }
  left -= m.bendLen;

  // 5. Patient's left posterior buccal segment (24..28)
  final leftCornerEnd = Offset(
    m.frontHalf + m.corner * m.cosS,
    m.rightCy - m.corner * m.sinS,
  );
  final leftEnd = Offset(rx, 0);
  final t = m.sideLen == 0 ? 1.0 : (left / m.sideLen).clamp(0.0, 1.0);
  final linear = Offset.lerp(leftCornerEnd, leftEnd, t)!;
  final belly = math.sin(t * math.pi) * (rx - m.frontHalf) * 0.08;
  return Offset(linear.dx + belly, linear.dy);
}

/// The box the teeth of a jaw occupy, relative to that jaw's centre: matches
/// the exact rotated bounding box of each `_compactTooth` (`seat.length +
/// band * 1.1` tall by `seat.drawSpan` wide) so the arch fills the full
/// horizontal width right to `0..width` without overflowing.
({double left, double right, double top, double bottom}) _seatsExtent(
  List<_ArchSeat> seats,
  double band,
) {
  var left = double.infinity;
  var right = -double.infinity;
  var top = double.infinity;
  var bottom = -double.infinity;
  final pad = band * 0.55;
  for (final seat in seats) {
    final cos = math.cos(seat.rotation).abs();
    final sin = math.sin(seat.rotation).abs();
    final halfHeight =
        (seat.length / 2 + pad) * cos + (seat.drawSpan / 2) * sin;
    final halfWidth = (seat.length / 2 + pad) * sin + (seat.drawSpan / 2) * cos;
    left = math.min(left, seat.center.dx - halfWidth);
    right = math.max(right, seat.center.dx + halfWidth);
    top = math.min(top, seat.center.dy - halfHeight);
    bottom = math.max(bottom, seat.center.dy + halfHeight);
  }
  return (left: left, right: right, top: top, bottom: bottom);
}

/// Where one facing pair of compact arches sits, and the seats its teeth
/// stand on.
class _CompactPairLayout {
  const _CompactPairLayout({
    required this.toothBand,
    required this.upperCenter,
    required this.lowerCenter,
    required this.upperSeats,
    required this.lowerSeats,
  });

  /// Room each tooth keeps beyond its root tip (the apex icons) and beyond its
  /// crown (its notation).
  final double toothBand;
  final Offset upperCenter;
  final Offset lowerCenter;
  final List<_ArchSeat> upperSeats;
  final List<_ArchSeat> lowerSeats;
}

/// Lays one facing pair of jaws into [band], sizing the curve to the room it is
/// given: the teeth are only ever as big as the curve they stand on, so a
/// taller chart buys bigger teeth rather than more empty space in the middle of
/// the mouth. How they fan is [_seatsAlongArch]'s business; the fit here only
/// decides how large the mouth ends up.
_CompactPairLayout _layoutCompactPair({
  required double width,
  required Rect band,
  required List<String> upperIsos,
  required List<String> lowerIsos,
  required double toothBand,
  required double jawGap,
  double toothFill = 1.0,
}) {
  var rx = math.max(24.0, width / 2 - toothBand * 2);
  var ry = math.max(20.0, band.height / 5);
  late List<_ArchSeat> upperSeats;
  late List<_ArchSeat> lowerSeats;

  for (var pass = 0; pass < 8; pass++) {
    upperSeats = _seatsAlongArch(
      isos: upperIsos,
      isUpper: true,
      rx: rx,
      ry: ry,
      toothFill: toothFill,
    );
    lowerSeats = _seatsAlongArch(
      isos: lowerIsos,
      isUpper: false,
      rx: rx,
      ry: ry,
      toothFill: toothFill,
    );

    // The pair is as tall as its two jaws plus the daylight between them, and
    // the curve grows a little slower than that, so the step is damped.
    final upperExtent = _seatsExtent(upperSeats, toothBand);
    final lowerExtent = _seatsExtent(lowerSeats, toothBand);
    final needed = (upperExtent.bottom - upperExtent.top) +
        (lowerExtent.bottom - lowerExtent.top) +
        jawGap;
    ry = math.max(20.0, ry + (band.height - needed) / 2.2);

    // Stretch rx so the outermost posterior teeth reach the left and right
    // edges of the canvas.
    final widest = <double>[
      upperExtent.right.abs(),
      upperExtent.left.abs(),
      lowerExtent.right.abs(),
      lowerExtent.left.abs(),
    ].reduce(math.max);
    rx = math.max(24.0, rx + 0.92 * (width / 2 - 1 - widest));
  }

  final upperExtent = _seatsExtent(upperSeats, toothBand);
  final lowerExtent = _seatsExtent(lowerSeats, toothBand);
  return _CompactPairLayout(
    toothBand: toothBand,
    upperCenter: Offset(width / 2, band.top - upperExtent.top),
    lowerCenter: Offset(width / 2, band.bottom - lowerExtent.bottom),
    upperSeats: upperSeats,
    lowerSeats: lowerSeats,
  );
}

class _ToothHistoryEntry {
  const _ToothHistoryEntry({
    required this.isCurrentDraft,
    required this.label,
    this.condition,
    this.extraNote,
    this.appointmentId,
    this.isBaseline = false,
  });

  final bool isCurrentDraft;
  final String label;
  final String? condition;
  final String? extraNote;
  final String? appointmentId;
  final bool isBaseline;
}

class _ToothOperationLayer {
  const _ToothOperationLayer({
    required this.operation,
    required this.color,
    required this.isCurrentDraft,
  });

  final String operation;
  final Color color;
  final bool isCurrentDraft;

  @override
  bool operator ==(Object other) =>
      other is _ToothOperationLayer &&
      other.operation == operation &&
      other.color == color &&
      other.isCurrentDraft == isCurrentDraft;

  @override
  int get hashCode => Object.hash(operation, color, isCurrentDraft);
}

class _OpgToothColumn extends StatefulWidget {
  const _OpgToothColumn({
    super.key,
    required this.iso,
    required this.isUpper,
    required this.isPrimary,
    required this.drawingHeight,
    required this.currentNote,
    required this.oldNote,
    required this.extraNote,
    required this.history,
    required this.historyTitle,
    required this.historyEntries,
    required this.operationLayers,
    required this.notation,
    required this.type,
    required this.onNote,
    required this.onExtraNote,
    required this.onOpenAppointment,
    required this.isHovered,
    required this.onHoverChanged,
    this.compact = false,
    this.compactBand = 0,
    this.compactSpan = 0,
    this.compactWidth = 0,
    this.archRotation = 0,
  });

  final String iso;
  final bool isUpper;
  final bool isPrimary;
  final double drawingHeight;
  final String? currentNote;
  final String? oldNote;
  final String extraNote;
  final List<ToothHistory> history;
  final String historyTitle;
  final List<_ToothHistoryEntry> historyEntries;
  final List<_ToothOperationLayer> operationLayers;
  final String Function(String isoString) notation;
  final StateType type;
  final void Function(String iso, String? note) onNote;
  final void Function(String iso, String extraNote)? onExtraNote;
  final ValueChanged<String>? onOpenAppointment;
  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;

  /// Whether the column is one cell of the compact arch: the drawing is turned
  /// by [archRotation] so the root points outward along the curve, the notation
  /// rides inside the crown instead of above or below it, and the beside-tooth
  /// notes are left out — a phone has no room for them, and the tooltip and the
  /// wheel carry the same records.
  final bool compact;

  /// Room a compact cell keeps past the root tip (for the apex icons) and past
  /// the crown (for the notation), so neither sits on the drawing.
  final double compactBand;

  /// The non-overlapping arc width the tooth owns on the curve (used to bound
  /// its hit-test area so adjacent rotated cells never steal hovers or taps).
  final double compactSpan;

  /// How wide that cell is drawn: slightly wider than [compactSpan] so
  /// neighbouring crowns make interproximal contact.
  final double compactWidth;
  final double archRotation;

  @override
  State<_OpgToothColumn> createState() => _OpgToothColumnState();
}

class _OpgToothColumnState extends State<_OpgToothColumn> {
  final FlyoutController _wheelController = FlyoutController();

  @override
  void dispose() {
    _wheelController.dispose();
    super.dispose();
  }

  Future<void> _openWheel(BuildContext context) async {
    try {
      if (MediaQuery.of(context).size.width > 900) {
        await flyoutFocusFix(context);
        if (!context.mounted) return;
        unawaited(_wheelController.showFlyout<void>(
          builder: (ctx) => _buildStateWheel(ctx),
          barrierDismissible: true,
          dismissWithEsc: true,
          barrierColor: Colors.black.withValues(alpha: 0.18),
        ));
        return;
      }
      unawaited(showDialog(
        barrierDismissible: true,
        dismissWithEsc: true,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        context: context,
        builder: (ctx) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildStateWheel(ctx),
          ),
        ),
      ));
    } catch (e, s) {
      debugPrint('Error opening ToothStateWheel for ${widget.iso}: $e\n$s');
    }
  }

  Widget _buildStateWheel(BuildContext context) {
    return ToothStateWheel(
      type: widget.type,
      onTapClose: () => Navigator.pop(context),
      iso: widget.iso,
      toothName: widget.notation(widget.iso),
      initialValue: widget.currentNote,
      oldNote: widget.oldNote,
      extraNote: widget.extraNote,
      onExtraNote: (text) => widget.onExtraNote?.call(widget.iso, text),
      history: widget.history,
      historyTitle: widget.historyTitle,
      onOpenAppointment: widget.onOpenAppointment,
      onSet: (note) => widget.onNote(widget.iso, note),
    );
  }

  String _tooltipMessage() {
    if (widget.historyEntries.isEmpty) {
      return widget.notation(widget.iso);
    }
    final blocks = <String>[];
    for (final entry in widget.historyEntries) {
      final condition = entry.condition;
      final conditionText =
          condition != null && condition.isNotEmpty ? txt(condition) : '';
      final extraText = entry.extraNote?.trim() ?? '';
      final lines = <String>[
        if (entry.label.isNotEmpty) entry.label,
        if (conditionText.isNotEmpty) conditionText,
        if (extraText.isNotEmpty) extraText,
      ];
      if (lines.isNotEmpty) {
        blocks.add(lines.join('\n'));
      }
    }
    return blocks.isNotEmpty
        ? blocks.join('\n\n')
        : widget.notation(widget.iso);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final iso = widget.iso;
    final layers = widget.operationLayers;
    final hasCurrent =
        widget.currentNote != null && widget.currentNote!.isNotEmpty;
    final hasOld = !hasCurrent &&
        (layers.isNotEmpty || (widget.oldNote?.isNotEmpty == true));

    final neutralColor = _neutralHistoryColor(darkMode);
    final Color? stateColor = hasCurrent
        ? labelToColor(widget.currentNote!)
        : hasOld
            ? neutralColor
            : null;

    final notationColor = hasCurrent
        ? stateColor!
        : (darkMode ? const Color(0xFFB8C7DC) : const Color(0xFF475569));

    final hasHistoryText = widget.historyEntries.isNotEmpty;

    if (widget.compact) {
      return _buildCompactCell(
        context,
        darkMode,
        iso,
        layers,
        hasCurrent,
        hasOld,
        neutralColor,
        stateColor,
        notationColor,
      );
    }

    return FlyoutTarget(
      controller: _wheelController,
      child: Semantics(
        button: true,
        label: widget.notation(iso),
        onTap: () => unawaited(_openWheel(context)),
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => widget.onHoverChanged(true),
          onExit: (_) => widget.onHoverChanged(false),
          child: GestureDetector(
            key: WK.tooth(iso, selected: widget.currentNote != null),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_openWheel(context)),
            child: Tooltip(
              message: _tooltipMessage(),
              excludeFromSemantics: true,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.isHovered
                      ? (stateColor ?? theme.accentColor)
                          .withValues(alpha: darkMode ? 0.16 : 0.10)
                      : hasCurrent
                          ? stateColor!
                              .withValues(alpha: darkMode ? 0.12 : 0.07)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasCurrent
                        ? stateColor!.withValues(alpha: 0.65)
                        : widget.isHovered
                            ? (darkMode
                                ? Colors.white.withValues(alpha: 0.28)
                                : theme.accentColor.withValues(alpha: 0.35))
                            : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.isUpper)
                      _buildNotationRow(context, iso, notationColor),
                    SizedBox(
                      height: widget.drawingHeight,
                      width: double.infinity,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // 1. Original high-contrast anatomical tooth + clipped
                          // overlapping treatment drawings (colored when registered
                          // here, neutral when from another appointment/record).
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _AnatomicalToothPainter(
                                iso: iso,
                                isUpper: widget.isUpper,
                                isPrimary: widget.isPrimary,
                                darkMode: darkMode,
                                stateColor: stateColor,
                                hasCurrent: hasCurrent,
                                hasOld: hasOld,
                                isHovered: widget.isHovered,
                                operationLayers: layers,
                              ),
                            ),
                          ),
                          // 2. Apex icon(s): NO shadows, NO surrounding circle,
                          // larger when a single treatment is applied, and wrapped
                          // cleanly in a Wrap when multiple treatments are present.
                          // Historical treatments lose their color and render in a
                          // neutral tone.
                          if (layers.isNotEmpty)
                            Align(
                              alignment: widget.isUpper
                                  ? Alignment.topCenter
                                  : Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                  vertical: 1,
                                ),
                                child: _buildApexIcons(
                                  layers,
                                  darkMode,
                                  neutralColor,
                                ),
                              ),
                            ),
                          // 3. Rotated 90° treatment text tucked right beside the
                          // tooth (colored when registered here, neutral when from
                          // another appointment).
                          if (hasHistoryText)
                            Positioned(
                              right: 0,
                              top: 2,
                              bottom: 2,
                              child: _buildBesideToothRotatedNotes(
                                context,
                                darkMode,
                                theme,
                                neutralColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.isUpper)
                      _buildNotationRow(context, iso, notationColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One cell of the compact arch. The tooth is turned so its root points
  /// outward along the curve ([archRotation]) and keeps a band above it for its
  /// apex icons and a band below it for its notation, so neither has to sit on
  /// the drawing. The notation itself stays upright — a number that tilts with
  /// the arch is a number nobody reads — while the icons turn with the tooth.
  Widget _buildCompactCell(
    BuildContext context,
    bool darkMode,
    String iso,
    List<_ToothOperationLayer> layers,
    bool hasCurrent,
    bool hasOld,
    Color neutralColor,
    Color? stateColor,
    Color notationColor,
  ) {
    // Outward is the top of the cell for an upper tooth and its bottom for a
    // lower one — the drawing is mirrored for the lower jaw.
    final outward =
        widget.isUpper ? Alignment.topCenter : Alignment.bottomCenter;
    final band = widget.compactBand;
    final showNotation = band > 6;

    return FlyoutTarget(
      controller: _wheelController,
      child: Semantics(
        button: true,
        label: widget.notation(iso),
        onTap: () => unawaited(_openWheel(context)),
        excludeSemantics: true,
        child: Transform.rotate(
          angle: widget.archRotation,
          child: _TaperedToothHitRegion(
            isUpper: widget.isUpper,
            crownWidth: widget.compactSpan > 0
                ? widget.compactSpan * 0.88
                : widget.compactWidth * 0.72,
            rootWidth: widget.compactSpan > 0
                ? widget.compactSpan * 0.56
                : widget.compactWidth * 0.45,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => widget.onHoverChanged(true),
              onExit: (_) => widget.onHoverChanged(false),
              child: GestureDetector(
                key: WK.tooth(iso, selected: widget.currentNote != null),
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(_openWheel(context)),
                child: Tooltip(
                  message: _tooltipMessage(),
                  excludeFromSemantics: true,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // 1. The tooth, filling the room between the two bands.
                      SizedBox(
                        height: widget.drawingHeight,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _AnatomicalToothPainter(
                            iso: iso,
                            isUpper: widget.isUpper,
                            isPrimary: widget.isPrimary,
                            darkMode: darkMode,
                            stateColor: stateColor,
                            hasCurrent: hasCurrent,
                            hasOld: hasOld,
                            isHovered: widget.isHovered,
                            operationLayers: layers,
                          ),
                        ),
                      ),
                      // 2. Apex icons, past the root tip where nothing else is
                      // drawn.
                      if (layers.isNotEmpty)
                        Align(
                          alignment: Alignment(0, outward.y * 1.18),
                          child: _buildApexIcons(
                            layers,
                            darkMode,
                            neutralColor,
                            compact: true,
                            maxWidth: band + 6,
                          ),
                        ),
                      // 3. The notation, tucked into the lingual/palatal side of
                      // the arch well clear of the crown outline: turned back
                      // upright, and scaled to fit its tooth slot.
                      if (showNotation)
                        Align(
                          alignment: Alignment(0, outward.y * -1.32),
                          child: Transform.rotate(
                            angle: -widget.archRotation,
                            child: Transform.scale(
                              scale: _notationScale(
                                band,
                                widget.compactSpan > 0
                                    ? widget.compactSpan
                                    : widget.compactWidth,
                              ),
                              child: DentalNotation(
                                iso: iso,
                                withTooltip: false,
                                color: notationColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Renders the treatment icon(s) at the root apex:
  /// - No shadows at all
  /// - Larger (`20px`) when only a single treatment is applied
  /// - Shrunk to fit [maxWidth] in a compact cell, where a tooth is small and
  ///   the icons have a band of their own to stay inside
  /// - Neutral color when the treatment came from another appointment/record
  /// - Deduplicates by icon glyph so the same icon is never shown twice
  Widget _buildApexIcons(
    List<_ToothOperationLayer> layers,
    bool darkMode,
    Color neutralColor, {
    bool compact = false,
    double maxWidth = 0,
  }) {
    final uniqueByIcon = <IconData, _ToothOperationLayer>{};
    for (final layer in layers) {
      uniqueByIcon[labelToIcon(layer.operation)] = layer;
    }
    final dedupedLayers = uniqueByIcon.values.toList();

    final isSingle = dedupedLayers.length == 1;
    double iconSize = compact
        ? (isSingle ? 15.0 : (dedupedLayers.length == 2 ? 11.5 : 10.0))
        : (isSingle ? 20.0 : (dedupedLayers.length == 2 ? 14.5 : 12.5));
    if (compact && maxWidth > 0) {
      const spacing = 2.0;
      final fitting = (maxWidth - spacing * (dedupedLayers.length - 1)) /
          dedupedLayers.length;
      iconSize = math.max(8.0, math.min(iconSize, fitting));
    }

    return IgnorePointer(
      child: Wrap(
        spacing: 2,
        runSpacing: 1,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final layer in dedupedLayers)
            Icon(
              labelToIcon(layer.operation),
              size: iconSize,
              color: layer.isCurrentDraft
                  ? (darkMode
                      ? layer.color.toAccentColor().lightest
                      : layer.color)
                  : neutralColor.withValues(alpha: darkMode ? 0.85 : 0.80),
            ),
        ],
      ),
    );
  }

  Widget _buildNotationRow(
    BuildContext context,
    String iso,
    Color notationColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: DentalNotation(
          iso: iso,
          withTooltip: false,
          color: notationColor,
        ),
      ),
    );
  }

  /// Rotates the tooth's treatment label 90 degrees and places it immediately
  /// beside the tooth. Entries from other appointments lose their color and
  /// render in a neutral tone.
  Widget _buildBesideToothRotatedNotes(
    BuildContext context,
    bool darkMode,
    FluentThemeData theme,
    Color neutralColor,
  ) {
    final entries = widget.historyEntries;
    final visibleEntries = entries.take(2).toList();

    return Directionality(
      textDirection: locale.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final entry in visibleEntries)
            _buildRotatedNoteTag(
              context,
              entry,
              darkMode,
              theme,
              neutralColor,
            ),
        ],
      ),
    );
  }

  Widget _buildRotatedNoteTag(
    BuildContext context,
    _ToothHistoryEntry entry,
    bool darkMode,
    FluentThemeData theme,
    Color neutralColor,
  ) {
    final condition = entry.condition;
    // Current draft keeps its treatment color; notes/treatments from other
    // appointments become neutral.
    final color = entry.isCurrentDraft
        ? (condition != null && condition.isNotEmpty
            ? labelToColor(condition)
            : theme.accentColor)
        : neutralColor;

    final conditionText =
        condition != null && condition.isNotEmpty ? txt(condition) : '';
    final extraText = entry.extraNote ?? '';

    if (conditionText.isEmpty && extraText.isEmpty) {
      return const SizedBox.shrink();
    }

    final textColor = entry.isCurrentDraft
        ? (darkMode ? Colors.white : color.toAccentColor().darkest)
        : (darkMode ? const Color(0xFFCBD5E1) : const Color(0xFF475569));

    return Container(
      margin: const EdgeInsets.only(left: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: entry.isCurrentDraft
              ? (darkMode ? 0.26 : 0.15)
              : (darkMode ? 0.16 : 0.10),
        ),
        borderRadius: BorderRadius.circular(3),
        border: Border(
          left: BorderSide(
            color: color.withValues(alpha: entry.isCurrentDraft ? 1.0 : 0.65),
            width: 1.8,
          ),
        ),
      ),
      child: RotatedBox(
        quarterTurns: 3,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conditionText.isNotEmpty)
              Flexible(
                child: Text(
                  conditionText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: entry.isCurrentDraft
                        ? FontWeight.w700
                        : FontWeight.w600,
                    height: 1.0,
                    color: textColor,
                  ),
                ),
              ),
            if (extraText.isNotEmpty) ...[
              if (conditionText.isNotEmpty) const SizedBox(width: 4),
              Flexible(
                child: Text(
                  extraText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.0,
                    fontStyle: FontStyle.italic,
                    color: textColor.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Constrains pointer hit-testing of a rotated compact-arch tooth cell to a
/// tapered wedge (wider at the crown/notation end, narrower at the root apex)
/// bounded by the tooth's own arc share. This prevents adjacent rotated
/// rectangular cells from overlapping in hit-test space and stealing hover or
/// tap events from the tooth above or below them.
class _TaperedToothHitRegion extends SingleChildRenderObjectWidget {
  const _TaperedToothHitRegion({
    required this.isUpper,
    required this.crownWidth,
    required this.rootWidth,
    required super.child,
  });

  final bool isUpper;
  final double crownWidth;
  final double rootWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTaperedToothHitRegion(
        isUpper: isUpper,
        crownWidth: crownWidth,
        rootWidth: rootWidth,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTaperedToothHitRegion renderObject,
  ) {
    renderObject
      ..isUpper = isUpper
      ..crownWidth = crownWidth
      ..rootWidth = rootWidth;
  }
}

class _RenderTaperedToothHitRegion extends RenderProxyBox {
  _RenderTaperedToothHitRegion({
    required this.isUpper,
    required this.crownWidth,
    required this.rootWidth,
  });

  bool isUpper;
  double crownWidth;
  double rootWidth;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final h = size.height;
    if (h <= 0) return false;
    // Normalized progress from root apex (0.0) to crown/notation end (1.0).
    final t =
        (isUpper ? position.dy / h : (h - position.dy) / h).clamp(0.0, 1.0);
    final allowedHalfWidth =
        (rootWidth + (crownWidth - rootWidth) * t) / 2.0;
    final dxFromCenter = (position.dx - size.width / 2.0).abs();
    if (dxFromCenter > allowedHalfWidth) return false;

    return super.hitTest(result, position: position);
  }
}

/// Draws subtle OPG radiograph anatomical guides (maxillary sinus floor,
/// nasal fossa, and mandibular canal / alveolar crest contour).
class _OpgBackdropPainter extends CustomPainter {
  const _OpgBackdropPainter({
    required this.darkMode,
    required this.isPrimary,
  });

  final bool darkMode;
  final bool isPrimary;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final boneLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = darkMode
          ? const Color(0xFF283A52).withValues(alpha: 0.45)
          : const Color(0xFFCBD5E1).withValues(alpha: 0.65);

    final upperCejY = isPrimary ? h * 0.24 : h * 0.25;
    final lowerCejY = isPrimary ? h * 0.72 : h * 0.70;

    final upperCrest = Path()
      ..moveTo(8, upperCejY - 4)
      ..quadraticBezierTo(w * 0.5, upperCejY + 6, w - 8, upperCejY - 4);
    canvas.drawPath(upperCrest, boneLinePaint);

    final lowerCrest = Path()
      ..moveTo(8, lowerCejY + 4)
      ..quadraticBezierTo(w * 0.5, lowerCejY - 6, w - 8, lowerCejY + 4);
    canvas.drawPath(lowerCrest, boneLinePaint);

    if (!isPrimary) {
      final sinusPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = darkMode
            ? const Color(0xFF1E2D42).withValues(alpha: 0.55)
            : const Color(0xFFD8E2EE).withValues(alpha: 0.75);

      final rightSinus = Path()
        ..moveTo(w * 0.05, h * 0.06)
        ..quadraticBezierTo(w * 0.16, h * 0.20, w * 0.29, h * 0.08);
      final leftSinus = Path()
        ..moveTo(w * 0.71, h * 0.08)
        ..quadraticBezierTo(w * 0.84, h * 0.20, w * 0.95, h * 0.06);
      canvas.drawPath(rightSinus, sinusPaint);
      canvas.drawPath(leftSinus, sinusPaint);

      // Inferior alveolar nerve (mandibular canal) running below the lower
      // molars and curving up between the apices of the two premolars (45/44
      // on the right, 35/34 on the left) to open at the mental foramen.
      final rightIanUpper = Path()
        ..moveTo(w * 0.02, h * 0.89)
        ..cubicTo(
          w * 0.10,
          h * 0.96,
          w * 0.22,
          h * 0.95,
          w * 0.275,
          h * 0.87,
        );
      final rightIanLower = Path()
        ..moveTo(w * 0.02, h * 0.92)
        ..cubicTo(
          w * 0.10,
          h * 0.985,
          w * 0.23,
          h * 0.975,
          w * 0.285,
          h * 0.89,
        );
      final rightForamen = Path()
        ..addOval(Rect.fromCenter(
          center: Offset(w * 0.28, h * 0.875),
          width: 7.5,
          height: 5.5,
        ));

      final leftIanUpper = Path()
        ..moveTo(w * 0.98, h * 0.89)
        ..cubicTo(
          w * 0.90,
          h * 0.96,
          w * 0.78,
          h * 0.95,
          w * 0.725,
          h * 0.87,
        );
      final leftIanLower = Path()
        ..moveTo(w * 0.98, h * 0.92)
        ..cubicTo(
          w * 0.90,
          h * 0.985,
          w * 0.77,
          h * 0.975,
          w * 0.715,
          h * 0.89,
        );
      final leftForamen = Path()
        ..addOval(Rect.fromCenter(
          center: Offset(w * 0.72, h * 0.875),
          width: 7.5,
          height: 5.5,
        ));

      canvas.drawPath(rightIanUpper, sinusPaint);
      canvas.drawPath(rightIanLower, sinusPaint);
      canvas.drawPath(rightForamen, sinusPaint);
      canvas.drawPath(leftIanUpper, sinusPaint);
      canvas.drawPath(leftIanLower, sinusPaint);
      canvas.drawPath(leftForamen, sinusPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OpgBackdropPainter oldDelegate) =>
      oldDelegate.darkMode != darkMode || oldDelegate.isPrimary != isPrimary;
}

/// The compact arch's backdrop: the line the two jaws part along and the
/// midline between the patient's two sides, which together split the mouth
/// into its four quadrants.
class _CompactArchPainter extends CustomPainter {
  const _CompactArchPainter({required this.darkMode});

  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final dividerColor = darkMode
        ? const Color(0xFF334766).withValues(alpha: 0.75)
        : const Color(0xFF9EB0C7).withValues(alpha: 0.6);

    final dividerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = dividerColor;
    final dividerY = size.height / 2;
    canvas.drawPath(
      Path()
        ..moveTo(0, dividerY - 1.5)
        ..quadraticBezierTo(
            size.width / 2, dividerY + 1.5, size.width, dividerY - 1.5),
      dividerPaint,
    );
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      dividerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CompactArchPainter oldDelegate) =>
      oldDelegate.darkMode != darkMode;
}

class _OcclusalCurvePainter extends CustomPainter {
  const _OcclusalCurvePainter({
    required this.color,
    required this.isPrimary,
  });

  final Color color;
  final bool isPrimary;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;

    final path = Path()
      ..moveTo(4, midY - 2)
      ..quadraticBezierTo(w * 0.5, midY + 3, w - 4, midY - 2);
    canvas.drawPath(path, paint);

    canvas.drawLine(
      Offset(w * 0.5, 0),
      Offset(w * 0.5, h),
      paint..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _OcclusalCurvePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isPrimary != isPrimary;
}

/// Anatomically distinct labial/buccal tooth painter for OPG panoramic view.
///
/// Preserves the rich, luminous tooth shading of the original OPG design
/// while rendering crisp, anatomically clipped visual drawings for every
/// treatment type. Operations from earlier appointments are drawn in a neutral
/// radiographic grey/silver palette, whereas operations registered in the
/// current record are drawn in their vibrant treatment colors.
class _AnatomicalToothPainter extends CustomPainter {
  const _AnatomicalToothPainter({
    required this.iso,
    required this.isUpper,
    required this.isPrimary,
    required this.darkMode,
    required this.stateColor,
    required this.hasCurrent,
    required this.hasOld,
    required this.isHovered,
    required this.operationLayers,
  });

  final String iso;
  final bool isUpper;
  final bool isPrimary;
  final bool darkMode;
  final Color? stateColor;
  final bool hasCurrent;
  final bool hasOld;
  final bool isHovered;
  final List<_ToothOperationLayer> operationLayers;

  bool _hasOp(String name) => operationLayers.any((l) => l.operation == name);

  _ToothOperationLayer? _layerForOp(String name) {
    for (final l in operationLayers.reversed) {
      if (l.operation == name) return l;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final q = int.parse(iso[0]);
    final pos = int.parse(iso[1]);
    final isPatientRight = q == 1 || q == 4 || q == 5 || q == 8;
    final isAnterior = pos <= 3;

    canvas.save();

    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.translate(cx, cy);
    final sx = (size.width * 0.46) * (isPatientRight ? -1.0 : 1.0);
    final sy = (size.height * 0.46) * (isUpper ? 1.0 : -1.0);

    if (_hasOp('malposition')) {
      canvas.rotate(isPatientRight ? 0.11 : -0.11);
    } else if (_hasOp('impacted')) {
      canvas.translate(0, isUpper ? -4.0 : 4.0);
      canvas.rotate(isPatientRight ? -0.22 : 0.22);
    }

    Offset pt(double nx, double ny) {
      return Offset(nx * sx, (ny * 2.0 - 1.0) * sy);
    }

    final geometry = _buildToothGeometry(
      pos: pos,
      isUpper: isUpper,
      isPrimary: isPrimary,
      pt: pt,
    );

    final isMissing = _hasOp('missing') || _hasOp('extraction');
    final implantLayer = _layerForOp('implant');
    final isImplant = implantLayer != null;
    final isPontic = _hasOp('pontic');
    final rrootLayer = _layerForOp('rroot');
    final isRetainedRoot = rrootLayer != null;

    // Base tooth colors: only tint the tooth body when there is a current
    // draft note (`hasCurrent`). When the tooth only has history from another
    // appointment (`hasOld`), keep the tooth in neutral radiographic tones!
    final Color rootFillStart;
    final Color rootFillEnd;
    final Color enamelStart;
    final Color enamelEnd;
    final Color strokeColor;

    if (hasCurrent && stateColor != null) {
      rootFillStart = Color.lerp(
        darkMode ? const Color(0xFF647996) : const Color(0xFFD6DEE8),
        stateColor!,
        darkMode ? 0.38 : 0.28,
      )!
          .withValues(alpha: darkMode ? 0.68 : 0.85);
      rootFillEnd = Color.lerp(
        darkMode ? const Color(0xFF94A9C9) : const Color(0xFFE4EBF3),
        stateColor!,
        darkMode ? 0.45 : 0.34,
      )!
          .withValues(alpha: darkMode ? 0.86 : 0.92);
      enamelStart = Color.lerp(
        darkMode ? const Color(0xFFE6EEF8) : const Color(0xFFFFFFFF),
        stateColor!,
        darkMode ? 0.32 : 0.22,
      )!;
      enamelEnd = Color.lerp(
        darkMode ? const Color(0xFFB4C6DF) : const Color(0xFFEEF3F9),
        stateColor!,
        darkMode ? 0.42 : 0.32,
      )!;
      strokeColor = darkMode
          ? Colors.white.withValues(alpha: 0.92)
          : stateColor!.toAccentColor().darkest;
    } else if (darkMode) {
      rootFillStart = const Color(0xFF647996).withValues(alpha: 0.55);
      rootFillEnd = const Color(0xFF94A9C9).withValues(alpha: 0.82);
      enamelStart = const Color(0xFFE6EEF8);
      enamelEnd = const Color(0xFFB4C6DF);
      strokeColor = isHovered
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF8CA4C4).withValues(alpha: 0.85);
    } else {
      rootFillStart = const Color(0xFFD6DEE8);
      rootFillEnd = const Color(0xFFE4EBF3);
      enamelStart = const Color(0xFFFFFFFF);
      enamelEnd = const Color(0xFFEEF3F9);
      strokeColor = isHovered
          ? const Color(0xFF1E293B)
          : const Color(0xFF64748B).withValues(alpha: 0.85);
    }

    final opacity = isMissing ? 0.24 : 1.0;

    final rootShaderRect = Rect.fromPoints(pt(-1, 0), pt(1, 0.65));
    final rootPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: isUpper ? Alignment.topCenter : Alignment.bottomCenter,
        end: isUpper ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [
          rootFillStart.withValues(alpha: rootFillStart.a * opacity),
          rootFillEnd.withValues(alpha: rootFillEnd.a * opacity),
        ],
      ).createShader(rootShaderRect);

    final crownShaderRect = Rect.fromPoints(pt(-1, 0.55), pt(1, 1.0));
    final crownPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: isUpper ? Alignment.bottomCenter : Alignment.topCenter,
        end: isUpper ? Alignment.topCenter : Alignment.bottomCenter,
        colors: [
          enamelStart.withValues(alpha: enamelStart.a * opacity),
          enamelEnd.withValues(alpha: enamelEnd.a * opacity),
        ],
      ).createShader(crownShaderRect);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHovered ? 1.6 : 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = strokeColor.withValues(alpha: strokeColor.a * opacity);

    // 1. Roots (either implant fixture or natural roots unless pontic)
    if (isImplant) {
      _paintImplantRoots(
        canvas,
        pt,
        implantLayer.color,
      );
    } else if (!isPontic) {
      for (final backRoot in geometry.backRoots) {
        canvas.drawPath(backRoot, rootPaint);
        canvas.drawPath(
          backRoot,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = outlinePaint.color,
        );
      }
      for (final root in geometry.roots) {
        canvas.drawPath(root, rootPaint);
        canvas.drawPath(root, outlinePaint);
      }
    }

    // 2. Natural radiolucent pulp chamber & canals (when not pontic/implant)
    if (!isImplant && !isPontic) {
      final naturalPulpPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = darkMode
            ? const Color(0xFF0B111A).withValues(alpha: 0.55 * opacity)
            : const Color(0xFF94A3B8).withValues(alpha: 0.28 * opacity);
      for (final canal in geometry.pulpAndCanals) {
        canvas.drawPath(canal, naturalPulpPaint);
      }
    }

    // 3. Endodontic layers (RCT / Re-RCT / Pulpotomy) drawn inside the root/pulp
    // space BEFORE the crown body is painted on top.
    for (final layer in operationLayers) {
      if (layer.operation == 'rCT' || layer.operation == 're-RCT') {
        _paintRctObturation(
          canvas,
          pt,
          geometry,
          layer,
          isReRct: layer.operation == 're-RCT',
        );
      } else if (layer.operation == 'pulpotomy') {
        _paintPulpotomy(canvas, pt, geometry, layer.color);
      }
    }

    // 4. Crown body + internal anatomical ridges/grooves
    if (!isRetainedRoot) {
      canvas.drawPath(geometry.crown, crownPaint);
      canvas.drawPath(geometry.crown, outlinePaint);

      final detailPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.95
        ..strokeCap = StrokeCap.round
        ..color = strokeColor.withValues(alpha: 0.42 * opacity);
      for (final detail in geometry.details) {
        canvas.drawPath(detail, detailPaint);
      }
    } else {
      _paintRetainedRootStump(
        canvas,
        pt,
        rrootLayer.color,
      );
    }

    // 5. Coronal & surgical treatment layers drawn in chronological order
    for (final layer in operationLayers) {
      _paintCoronalOrPerioLayer(
        canvas: canvas,
        pt: pt,
        geometry: geometry,
        layer: layer,
        isAnterior: isAnterior,
      );
    }

    canvas.restore();
  }

  void _paintCoronalOrPerioLayer({
    required Canvas canvas,
    required Offset Function(double nx, double ny) pt,
    required _ToothGeometry geometry,
    required _ToothOperationLayer layer,
    required bool isAnterior,
  }) {
    final op = layer.operation;
    final color = layer.color;

    switch (op) {
      case 'filling':
        _paintFilling(canvas, pt, geometry, color, isAnterior: isAnterior);
      case 'overlay':
        _paintOverlayRestoration(canvas, pt, geometry, color);
      case 'veneer':
        _paintVeneer(canvas, pt, geometry, color);
      case 'crown':
      case 'abutment':
        _paintEnlargedCrown(
          canvas,
          pt,
          geometry,
          color,
          dashed: false,
          isAbutment: op == 'abutment',
        );
      case 'temporary':
        _paintEnlargedCrown(
          canvas,
          pt,
          geometry,
          color,
          dashed: true,
        );
      case 'bridge':
      case 'pontic':
        _paintBridgeOrPontic(
          canvas,
          pt,
          geometry,
          color,
          isPontic: op == 'pontic',
        );
      case 'ortho':
        _paintOrthoBracket(canvas, pt, geometry, color);
      case 'surgery':
        _paintSurgicalStitches(canvas, pt, color);
      case 'caries':
        _paintCariesLesion(canvas, pt, geometry, color, isAnterior: isAnterior);
      case 'fractured':
        _paintFractureCrack(canvas, pt, geometry, color);
      case 'recession':
        _paintGingivalRecession(canvas, pt, color);
      case 'mobility':
        _paintMobilityArrows(canvas, pt, color);
      case 'clean':
        _paintCervicalCleanArc(canvas, pt, color);
      case 'whitening':
        _paintWhiteningSparkle(canvas, pt, geometry, color);
      case 'rprimary':
        _paintRetainedPrimaryBadge(canvas, pt, color);
      case 'missing':
      case 'extraction':
        _paintExtractionCross(canvas, pt, color);
      default:
        break;
    }
  }

  /// Titanium implant fixture with realistic tapered body, apical roundness,
  /// abutment collar, and fine screw threads.
  void _paintImplantRoots(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final fixture = Path()
      ..moveTo(pt(-0.34, 0.56).dx, pt(-0.34, 0.56).dy)
      ..lineTo(pt(-0.22, 0.14).dx, pt(-0.22, 0.14).dy)
      ..quadraticBezierTo(
        pt(0, 0.08).dx,
        pt(0, 0.08).dy,
        pt(0.22, 0.14).dx,
        pt(0.22, 0.14).dy,
      )
      ..lineTo(pt(0.34, 0.56).dx, pt(0.34, 0.56).dy)
      ..close();

    final rect = fixture.getBounds();
    canvas.drawPath(
      fixture,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.85),
            color.withValues(alpha: 0.85),
          ],
        ).createShader(rect),
    );

    final threadStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawPath(fixture, threadStroke);

    for (var i = 0; i < 4; i++) {
      final ny = 0.20 + i * 0.09;
      final hw = 0.24 + i * 0.025;
      canvas.drawLine(pt(-hw, ny), pt(hw, ny), threadStroke);
    }
  }

  /// RCT / Re-RCT: When registered in the current draft, uses the vibrant
  /// gutta-percha/treatment color; when from another appointment, uses neutral
  /// radiographic silver-grey.
  void _paintRctObturation(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    _ToothOperationLayer layer, {
    required bool isReRct,
  }) {
    final fillColor = layer.isCurrentDraft
        ? (isReRct ? const Color(0xFFFFB300) : const Color(0xFFFFD54F))
        : layer.color;
    final strokeColor = layer.isCurrentDraft
        ? (isReRct ? layer.color : Colors.white.withValues(alpha: 0.92))
        : (darkMode
            ? Colors.white.withValues(alpha: 0.65)
            : const Color(0xFF475569));

    for (final canal in geometry.pulpAndCanals) {
      canvas.drawPath(
        canal,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor.withValues(
            alpha: layer.isCurrentDraft ? 0.95 : 0.75,
          ),
      );
      canvas.drawPath(
        canal,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isReRct ? 1.4 : 1.0
          ..strokeJoin = StrokeJoin.round
          ..color = strokeColor,
      );
    }
  }

  /// Pulpotomy: Distinct from RCT — only the coronal pulp chamber at the neck/
  /// top of the root-crown junction is filled, while the root canals toward the
  /// apex remain untouched!
  void _paintPulpotomy(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    final c1 = pt(-1.0, 0.44);
    final c2 = pt(1.0, 0.72);
    final coronalClip = Rect.fromPoints(c1, c2).inflate(2);

    canvas.save();
    canvas.clipRect(coronalClip);
    for (final canal in geometry.pulpAndCanals) {
      canvas.drawPath(
        canal,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.92),
      );
      canvas.drawPath(
        canal,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15
          ..color = Colors.white.withValues(alpha: 0.90),
      );
    }
    canvas.restore();

    final cap = Path()
      ..moveTo(pt(-0.28, 0.54).dx, pt(-0.28, 0.54).dy)
      ..quadraticBezierTo(
        pt(0, 0.67).dx,
        pt(0, 0.67).dy,
        pt(0.28, 0.54).dx,
        pt(0.28, 0.54).dy,
      )
      ..quadraticBezierTo(
        pt(0, 0.49).dx,
        pt(0, 0.49).dy,
        pt(-0.28, 0.54).dx,
        pt(-0.28, 0.54).dy,
      )
      ..close();
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.90),
    );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.95
        ..color = Colors.white.withValues(alpha: 0.88),
    );
  }

  /// Filling: Clipped directly to `geometry.crown` so it hugs the natural tooth
  /// enamel contour!
  void _paintFilling(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color, {
    required bool isAnterior,
  }) {
    canvas.save();
    canvas.clipPath(geometry.crown);

    final Path patch;
    if (isAnterior) {
      patch = Path()
        ..moveTo(pt(-0.95, 0.64).dx, pt(-0.95, 0.64).dy)
        ..quadraticBezierTo(
          pt(-0.08, 0.68).dx,
          pt(-0.08, 0.68).dy,
          pt(-0.14, 0.88).dx,
          pt(-0.14, 0.88).dy,
        )
        ..quadraticBezierTo(
          pt(-0.22, 0.96).dx,
          pt(-0.22, 0.96).dy,
          pt(-0.95, 0.95).dx,
          pt(-0.95, 0.95).dy,
        )
        ..close();
    } else {
      patch = Path()
        ..moveTo(pt(-0.48, 1.02).dx, pt(-0.48, 1.02).dy)
        ..quadraticBezierTo(
          pt(-0.44, 0.73).dx,
          pt(-0.44, 0.73).dy,
          pt(0.0, 0.75).dx,
          pt(0.0, 0.75).dy,
        )
        ..quadraticBezierTo(
          pt(0.44, 0.73).dx,
          pt(0.44, 0.73).dy,
          pt(0.48, 1.02).dx,
          pt(0.48, 1.02).dy,
        )
        ..close();
    }

    canvas.drawPath(
      patch,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.85),
    );
    canvas.drawPath(
      patch,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.88),
    );
    canvas.restore();
  }

  /// Overlay: Extends across the entire crown from mesial to distal, clipped
  /// cleanly to `geometry.crown`.
  void _paintOverlayRestoration(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    canvas.save();
    canvas.clipPath(geometry.crown);

    final overlayBand = Path()
      ..moveTo(pt(-1.15, 0.66).dx, pt(-1.15, 0.66).dy)
      ..lineTo(pt(-1.15, 1.08).dx, pt(-1.15, 1.08).dy)
      ..lineTo(pt(1.15, 1.08).dx, pt(1.15, 1.08).dy)
      ..lineTo(pt(1.15, 0.66).dx, pt(1.15, 0.66).dy)
      ..quadraticBezierTo(
        pt(0.48, 0.74).dx,
        pt(0.48, 0.74).dy,
        pt(0.0, 0.67).dx,
        pt(0.0, 0.67).dy,
      )
      ..quadraticBezierTo(
        pt(-0.48, 0.74).dx,
        pt(-0.48, 0.74).dy,
        pt(-1.15, 0.66).dx,
        pt(-1.15, 0.66).dy,
      )
      ..close();

    canvas.drawPath(
      overlayBand,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.82),
    );
    canvas.drawPath(
      overlayBand,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.90),
    );
    canvas.restore();

    canvas.drawPath(
      geometry.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..color = color,
    );
  }

  /// Veneer: Half a crown covering only one side (mesial half of `geometry.crown`).
  void _paintVeneer(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    final bounds = geometry.crown.getBounds();
    final midX = pt(0.02, 0.78).dx;
    final mesialX = pt(-1.2, 0.78).dx;
    final clipLeft = math.min(midX, mesialX);
    final clipRight = math.max(midX, mesialX);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(
      clipLeft,
      bounds.top - 6,
      clipRight,
      bounds.bottom + 6,
    ));

    canvas.drawPath(
      geometry.crown,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.65),
    );
    canvas.drawPath(
      geometry.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..color = color,
    );
    canvas.restore();

    canvas.save();
    canvas.clipPath(geometry.crown);
    canvas.drawLine(
      pt(0.02, 0.50),
      pt(0.02, 1.02),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.90),
    );
    canvas.restore();
  }

  /// Crown & Temporary Crown: Enlarged anatomical crown contour (`1.13x`),
  /// dashed when `temporary`.
  void _paintEnlargedCrown(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color, {
    required bool dashed,
    bool isAbutment = false,
  }) {
    final bounds = geometry.crown.getBounds();
    final outerCrown = _scalePathAround(
      geometry.crown,
      bounds.center,
      1.13,
      1.11,
    );

    canvas.drawPath(
      outerCrown,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: isUpper ? Alignment.bottomCenter : Alignment.topCenter,
          end: isUpper ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: dashed ? 0.28 : 0.52),
            color.withValues(alpha: dashed ? 0.14 : 0.32),
          ],
        ).createShader(bounds),
    );

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 1.65 : 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    if (dashed) {
      _drawDashedPath(
        canvas,
        outerCrown,
        borderPaint,
        dashLength: 2.6,
        gapLength: 2.2,
      );
    } else {
      canvas.drawPath(outerCrown, borderPaint);
      canvas.drawPath(
        geometry.crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85
          ..color = Colors.white.withValues(alpha: 0.65),
      );
    }

    if (isAbutment) {
      canvas.drawLine(
        pt(0, 0.48),
        pt(0, 0.78),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.88),
      );
    }
  }

  void _paintBridgeOrPontic(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color, {
    required bool isPontic,
  }) {
    _paintEnlargedCrown(canvas, pt, geometry, color, dashed: false);
    final connectorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(pt(-1.04, 0.76), pt(-0.74, 0.76), connectorPaint);
    canvas.drawLine(pt(0.74, 0.76), pt(1.04, 0.76), connectorPaint);
  }

  void _paintOrthoBracket(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    final c = pt(0, 0.76);
    final wireLeft = pt(-0.98, 0.76);
    final wireRight = pt(0.98, 0.76);

    canvas.drawLine(
      wireLeft,
      wireRight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..color = darkMode ? const Color(0xFFE2E8F0) : const Color(0xFF475569),
    );

    final padRect = Rect.fromCenter(center: c, width: 7.2, height: 6.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(padRect, const Radius.circular(1.3)),
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(padRect, const Radius.circular(1.3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.95
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    final slotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.95
      ..color = Colors.white;
    canvas.drawLine(
      Offset(c.dx, c.dy - 2.6),
      Offset(c.dx, c.dy + 2.6),
      slotPaint,
    );
    canvas.drawLine(
      Offset(c.dx - 3.2, c.dy),
      Offset(c.dx + 3.2, c.dy),
      slotPaint,
    );
  }

  void _paintSurgicalStitches(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final flap = Path()
      ..moveTo(pt(-0.56, 0.34).dx, pt(-0.56, 0.34).dy)
      ..quadraticBezierTo(
        pt(0.0, 0.24).dx,
        pt(0.0, 0.24).dy,
        pt(0.56, 0.34).dx,
        pt(0.56, 0.34).dy,
      );
    canvas.drawPath(
      flap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    final stitchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.90);

    for (final nx in [-0.32, 0.0, 0.32]) {
      final baseNy = nx == 0.0 ? 0.29 : 0.315;
      canvas.drawLine(
        pt(nx - 0.04, baseNy - 0.065),
        pt(nx + 0.04, baseNy + 0.065),
        stitchPaint,
      );
      canvas.drawLine(
        pt(nx - 0.055, baseNy + 0.015),
        pt(nx + 0.055, baseNy - 0.015),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.05
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  void _paintCariesLesion(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color, {
    required bool isAnterior,
  }) {
    canvas.save();
    canvas.clipPath(geometry.crown);
    final center = isAnterior ? pt(0.34, 0.75) : pt(0.16, 0.83);
    canvas.drawCircle(
      center,
      3.8,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.88),
    );
    canvas.drawCircle(
      center,
      1.8,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black.withValues(alpha: 0.50),
    );
    canvas.restore();
  }

  void _paintFractureCrack(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    canvas.save();
    canvas.clipPath(geometry.crown);
    final crack = Path()
      ..moveTo(pt(-0.46, 0.95).dx, pt(-0.46, 0.95).dy)
      ..lineTo(pt(-0.08, 0.80).dx, pt(-0.08, 0.80).dy)
      ..lineTo(pt(0.14, 0.83).dx, pt(0.14, 0.83).dy)
      ..lineTo(pt(0.48, 0.65).dx, pt(0.48, 0.65).dy);
    canvas.drawPath(
      crack,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();
  }

  void _paintGingivalRecession(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final rec = Path()
      ..moveTo(pt(-0.58, 0.54).dx, pt(-0.58, 0.54).dy)
      ..quadraticBezierTo(
        pt(0.0, 0.36).dx,
        pt(0.0, 0.36).dy,
        pt(0.58, 0.54).dx,
        pt(0.58, 0.54).dy,
      );
    canvas.drawPath(
      rec,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintMobilityArrows(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color;
    final pL = pt(-0.62, 0.80);
    final pR = pt(0.62, 0.80);
    canvas.drawLine(pL, pR, paint);
    canvas.drawLine(pL, Offset(pL.dx + 3.0, pL.dy - 2.2), paint);
    canvas.drawLine(pL, Offset(pL.dx + 3.0, pL.dy + 2.2), paint);
    canvas.drawLine(pR, Offset(pR.dx - 3.0, pR.dy - 2.2), paint);
    canvas.drawLine(pR, Offset(pR.dx - 3.0, pR.dy + 2.2), paint);
  }

  void _paintCervicalCleanArc(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final arc = Path()
      ..moveTo(pt(-0.54, 0.58).dx, pt(-0.54, 0.58).dy)
      ..quadraticBezierTo(
        pt(0, 0.52).dx,
        pt(0, 0.52).dy,
        pt(0.54, 0.58).dx,
        pt(0.54, 0.58).dy,
      );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintWhiteningSparkle(
    Canvas canvas,
    Offset Function(double, double) pt,
    _ToothGeometry geometry,
    Color color,
  ) {
    canvas.save();
    canvas.clipPath(geometry.crown);
    canvas.drawPath(
      geometry.crown,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.restore();

    final c = pt(0.0, 0.78);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(Offset(c.dx - 4.0, c.dy), Offset(c.dx + 4.0, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - 4.0), Offset(c.dx, c.dy + 4.0), p);
  }

  void _paintRetainedRootStump(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final jagged = Path()
      ..moveTo(pt(-0.50, 0.56).dx, pt(-0.50, 0.56).dy)
      ..lineTo(pt(-0.18, 0.61).dx, pt(-0.18, 0.61).dy)
      ..lineTo(pt(0.12, 0.54).dx, pt(0.12, 0.54).dy)
      ..lineTo(pt(0.50, 0.58).dx, pt(0.50, 0.58).dy);
    canvas.drawPath(
      jagged,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintRetainedPrimaryBadge(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final cap = Path()
      ..moveTo(pt(-0.46, 0.62).dx, pt(-0.46, 0.62).dy)
      ..quadraticBezierTo(
        pt(0, 0.75).dx,
        pt(0, 0.75).dy,
        pt(0.46, 0.62).dx,
        pt(0.46, 0.62).dy,
      );
    canvas.drawPath(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintExtractionCross(
    Canvas canvas,
    Offset Function(double, double) pt,
    Color color,
  ) {
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.80);
    canvas.drawLine(pt(-0.54, 0.22), pt(0.54, 0.85), crossPaint);
    canvas.drawLine(pt(-0.54, 0.85), pt(0.54, 0.22), crossPaint);
  }

  Path _scalePathAround(Path path, Offset pivot, double sx, double sy) {
    final matrix = Matrix4.identity()
      ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);
    return path.transform(matrix.storage);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnatomicalToothPainter oldDelegate) {
    if (oldDelegate.iso != iso ||
        oldDelegate.isUpper != isUpper ||
        oldDelegate.isPrimary != isPrimary ||
        oldDelegate.darkMode != darkMode ||
        oldDelegate.stateColor != stateColor ||
        oldDelegate.hasCurrent != hasCurrent ||
        oldDelegate.hasOld != hasOld ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.operationLayers.length != operationLayers.length) {
      return true;
    }
    for (var i = 0; i < operationLayers.length; i++) {
      if (oldDelegate.operationLayers[i] != operationLayers[i]) return true;
    }
    return false;
  }
}

class _ToothGeometry {
  const _ToothGeometry({
    required this.roots,
    this.backRoots = const [],
    required this.crown,
    this.pulpAndCanals = const [],
    this.details = const [],
  });

  final List<Path> roots;
  final List<Path> backRoots;
  final Path crown;
  final List<Path> pulpAndCanals;
  final List<Path> details;
}

/// Builds anatomically distinct tooth outlines in normalized coordinates:
/// - `nx` in [-1..1]: `-nx` is MESIAL, `+nx` is DISTAL.
/// - `ny` in [0..1]: `0` is root apex, `~0.58` is CEJ (cervical line), `1.0` is
///   incisal edge / cusp tip.
_ToothGeometry _buildToothGeometry({
  required int pos,
  required bool isUpper,
  required bool isPrimary,
  required Offset Function(double nx, double ny) pt,
}) {
  if (isPrimary) {
    return switch (pos) {
      1 => _incisorGeometry(
          pt: pt,
          crownHalfWidth: isUpper ? 0.68 : 0.54,
          cejHalfWidth: isUpper ? 0.46 : 0.36,
          rootLengthNy: 0.14,
          distalIncisalRoundness: 0.05,
          distalRootBend: 0.04,
          hasLabialGrooves: isUpper,
        ),
      2 => _incisorGeometry(
          pt: pt,
          crownHalfWidth: isUpper ? 0.56 : 0.58,
          cejHalfWidth: isUpper ? 0.38 : 0.40,
          rootLengthNy: 0.16,
          distalIncisalRoundness: 0.11,
          distalRootBend: 0.12,
          hasLabialGrooves: false,
        ),
      3 => _canineGeometry(
          pt: pt,
          crownHalfWidth: 0.68,
          cejHalfWidth: 0.46,
          rootApexNy: 0.10,
          cuspSharpness: 0.14,
        ),
      4 => isUpper
          ? _upperMolarGeometry(
              pt: pt,
              variant: 1,
              crownScale: 0.86,
              rootApexNy: 0.14,
            )
          : _lowerMolarGeometry(
              pt: pt,
              variant: 2,
              crownScale: 0.86,
              rootApexNy: 0.14,
            ),
      _ => isUpper
          ? _upperMolarGeometry(
              pt: pt,
              variant: 1,
              crownScale: 0.94,
              rootApexNy: 0.12,
            )
          : _lowerMolarGeometry(
              pt: pt,
              variant: 1,
              crownScale: 0.94,
              rootApexNy: 0.12,
            ),
    };
  }

  return switch (pos) {
    1 => isUpper
        ? _incisorGeometry(
            pt: pt,
            crownHalfWidth: 0.76,
            cejHalfWidth: 0.50,
            rootLengthNy: 0.10,
            distalIncisalRoundness: 0.05,
            distalRootBend: 0.03,
            hasLabialGrooves: true,
          )
        : _incisorGeometry(
            pt: pt,
            crownHalfWidth: 0.52,
            cejHalfWidth: 0.34,
            rootLengthNy: 0.12,
            distalIncisalRoundness: 0.02,
            distalRootBend: 0.01,
            hasLabialGrooves: false,
          ),
    2 => isUpper
        ? _incisorGeometry(
            pt: pt,
            crownHalfWidth: 0.60,
            cejHalfWidth: 0.40,
            rootLengthNy: 0.13,
            distalIncisalRoundness: 0.14,
            distalRootBend: 0.16,
            hasLabialGrooves: false,
            crownTopNy: 0.94,
          )
        : _incisorGeometry(
            pt: pt,
            crownHalfWidth: 0.60,
            cejHalfWidth: 0.38,
            rootLengthNy: 0.10,
            distalIncisalRoundness: 0.09,
            distalRootBend: 0.10,
            hasLabialGrooves: false,
          ),
    3 => _canineGeometry(
        pt: pt,
        crownHalfWidth: isUpper ? 0.72 : 0.66,
        cejHalfWidth: isUpper ? 0.48 : 0.44,
        rootApexNy: 0.04,
        cuspSharpness: isUpper ? 0.17 : 0.13,
      ),
    4 => _premolarGeometry(
        pt: pt,
        isFirst: true,
        isUpper: isUpper,
      ),
    5 => _premolarGeometry(
        pt: pt,
        isFirst: false,
        isUpper: isUpper,
      ),
    6 => isUpper
        ? _upperMolarGeometry(pt: pt, variant: 1)
        : _lowerMolarGeometry(pt: pt, variant: 1),
    7 => isUpper
        ? _upperMolarGeometry(pt: pt, variant: 2)
        : _lowerMolarGeometry(pt: pt, variant: 2),
    _ => isUpper
        ? _upperMolarGeometry(pt: pt, variant: 3)
        : _lowerMolarGeometry(pt: pt, variant: 3),
  };
}

_ToothGeometry _incisorGeometry({
  required Offset Function(double nx, double ny) pt,
  required double crownHalfWidth,
  required double cejHalfWidth,
  required double rootLengthNy,
  required double distalIncisalRoundness,
  required double distalRootBend,
  required bool hasLabialGrooves,
  double crownTopNy = 0.97,
}) {
  const cejNy = 0.56;

  final root = Path()
    ..moveTo(pt(-cejHalfWidth, cejNy).dx, pt(-cejHalfWidth, cejNy).dy)
    ..cubicTo(
      pt(-cejHalfWidth * 0.85, 0.36).dx,
      pt(-cejHalfWidth * 0.85, 0.36).dy,
      pt(-0.14 + distalRootBend * 0.5, rootLengthNy + 0.08).dx,
      pt(-0.14 + distalRootBend * 0.5, rootLengthNy + 0.08).dy,
      pt(distalRootBend, rootLengthNy).dx,
      pt(distalRootBend, rootLengthNy).dy,
    )
    ..cubicTo(
      pt(0.14 + distalRootBend, rootLengthNy + 0.08).dx,
      pt(0.14 + distalRootBend, rootLengthNy + 0.08).dy,
      pt(cejHalfWidth * 0.85, 0.36).dx,
      pt(cejHalfWidth * 0.85, 0.36).dy,
      pt(cejHalfWidth, cejNy).dx,
      pt(cejHalfWidth, cejNy).dy,
    )
    ..close();

  final mesialIncisalNy = crownTopNy;
  final distalIncisalNy = crownTopNy - distalIncisalRoundness;

  final crown = Path()
    ..moveTo(pt(-cejHalfWidth, cejNy).dx, pt(-cejHalfWidth, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.04).dx,
      pt(0, cejNy - 0.04).dy,
      pt(cejHalfWidth, cejNy).dx,
      pt(cejHalfWidth, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalfWidth * 0.98, cejNy + 0.14).dx,
      pt(crownHalfWidth * 0.98, cejNy + 0.14).dy,
      pt(crownHalfWidth, distalIncisalNy - 0.06).dx,
      pt(crownHalfWidth, distalIncisalNy - 0.06).dy,
      pt(crownHalfWidth * 0.86, distalIncisalNy).dx,
      pt(crownHalfWidth * 0.86, distalIncisalNy).dy,
    )
    ..quadraticBezierTo(
      pt(0, crownTopNy + 0.01).dx,
      pt(0, crownTopNy + 0.01).dy,
      pt(-crownHalfWidth * 0.92, mesialIncisalNy).dx,
      pt(-crownHalfWidth * 0.92, mesialIncisalNy).dy,
    )
    ..cubicTo(
      pt(-crownHalfWidth, mesialIncisalNy - 0.05).dx,
      pt(-crownHalfWidth, mesialIncisalNy - 0.05).dy,
      pt(-crownHalfWidth * 0.96, cejNy + 0.14).dx,
      pt(-crownHalfWidth * 0.96, cejNy + 0.14).dy,
      pt(-cejHalfWidth, cejNy).dx,
      pt(-cejHalfWidth, cejNy).dy,
    )
    ..close();

  final pulp = Path()
    ..moveTo(pt(distalRootBend * 0.85, rootLengthNy + 0.05).dx,
        pt(distalRootBend * 0.85, rootLengthNy + 0.05).dy)
    ..lineTo(pt(-cejHalfWidth * 0.28, cejNy + 0.14).dx,
        pt(-cejHalfWidth * 0.28, cejNy + 0.14).dy)
    ..lineTo(pt(cejHalfWidth * 0.28, cejNy + 0.14).dx,
        pt(cejHalfWidth * 0.28, cejNy + 0.14).dy)
    ..close();

  final details = <Path>[];
  if (hasLabialGrooves) {
    final g1 = Path()
      ..moveTo(pt(-0.22, cejNy + 0.12).dx, pt(-0.22, cejNy + 0.12).dy)
      ..lineTo(
          pt(-0.26, crownTopNy - 0.05).dx, pt(-0.26, crownTopNy - 0.05).dy);
    final g2 = Path()
      ..moveTo(pt(0.22, cejNy + 0.12).dx, pt(0.22, cejNy + 0.12).dy)
      ..lineTo(pt(0.26, crownTopNy - 0.05).dx, pt(0.26, crownTopNy - 0.05).dy);
    details.addAll([g1, g2]);
  } else {
    final g = Path()
      ..moveTo(pt(0.0, cejNy + 0.10).dx, pt(0.0, cejNy + 0.10).dy)
      ..lineTo(pt(distalIncisalRoundness * 0.4, crownTopNy - 0.07).dx,
          pt(distalIncisalRoundness * 0.4, crownTopNy - 0.07).dy);
    details.add(g);
  }

  return _ToothGeometry(
    roots: [root],
    crown: crown,
    pulpAndCanals: [pulp],
    details: details,
  );
}

_ToothGeometry _canineGeometry({
  required Offset Function(double nx, double ny) pt,
  required double crownHalfWidth,
  required double cejHalfWidth,
  required double rootApexNy,
  required double cuspSharpness,
}) {
  const cejNy = 0.56;

  final root = Path()
    ..moveTo(pt(-cejHalfWidth, cejNy).dx, pt(-cejHalfWidth, cejNy).dy)
    ..cubicTo(
      pt(-cejHalfWidth * 0.88, 0.32).dx,
      pt(-cejHalfWidth * 0.88, 0.32).dy,
      pt(-0.14, rootApexNy + 0.08).dx,
      pt(-0.14, rootApexNy + 0.08).dy,
      pt(0.06, rootApexNy).dx,
      pt(0.06, rootApexNy).dy,
    )
    ..cubicTo(
      pt(0.20, rootApexNy + 0.08).dx,
      pt(0.20, rootApexNy + 0.08).dy,
      pt(cejHalfWidth * 0.88, 0.32).dx,
      pt(cejHalfWidth * 0.88, 0.32).dy,
      pt(cejHalfWidth, cejNy).dx,
      pt(cejHalfWidth, cejNy).dy,
    )
    ..close();

  final crown = Path()
    ..moveTo(pt(-cejHalfWidth, cejNy).dx, pt(-cejHalfWidth, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.05).dx,
      pt(0, cejNy - 0.05).dy,
      pt(cejHalfWidth, cejNy).dx,
      pt(cejHalfWidth, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalfWidth * 0.95, cejNy + 0.10).dx,
      pt(crownHalfWidth * 0.95, cejNy + 0.10).dy,
      pt(crownHalfWidth * 1.02, 0.76).dx,
      pt(crownHalfWidth * 1.02, 0.76).dy,
      pt(crownHalfWidth * 0.88, 0.81).dx,
      pt(crownHalfWidth * 0.88, 0.81).dy,
    )
    ..lineTo(
        pt(-0.04, 0.82 + cuspSharpness).dx, pt(-0.04, 0.82 + cuspSharpness).dy)
    ..lineTo(pt(-crownHalfWidth * 0.88, 0.84).dx,
        pt(-crownHalfWidth * 0.88, 0.84).dy)
    ..cubicTo(
      pt(-crownHalfWidth, 0.78).dx,
      pt(-crownHalfWidth, 0.78).dy,
      pt(-crownHalfWidth * 0.92, cejNy + 0.10).dx,
      pt(-crownHalfWidth * 0.92, cejNy + 0.10).dy,
      pt(-cejHalfWidth, cejNy).dx,
      pt(-cejHalfWidth, cejNy).dy,
    )
    ..close();

  final pulp = Path()
    ..moveTo(pt(0.05, rootApexNy + 0.06).dx, pt(0.05, rootApexNy + 0.06).dy)
    ..lineTo(pt(-0.16, cejNy + 0.08).dx, pt(-0.16, cejNy + 0.08).dy)
    ..lineTo(pt(-0.03, cejNy + 0.22).dx, pt(-0.03, cejNy + 0.22).dy)
    ..lineTo(pt(0.16, cejNy + 0.08).dx, pt(0.16, cejNy + 0.08).dy)
    ..close();

  final labialRidge = Path()
    ..moveTo(pt(0.0, cejNy + 0.06).dx, pt(0.0, cejNy + 0.06).dy)
    ..lineTo(
        pt(-0.04, 0.80 + cuspSharpness).dx, pt(-0.04, 0.80 + cuspSharpness).dy);

  return _ToothGeometry(
    roots: [root],
    crown: crown,
    pulpAndCanals: [pulp],
    details: [labialRidge],
  );
}

_ToothGeometry _premolarGeometry({
  required Offset Function(double nx, double ny) pt,
  required bool isFirst,
  required bool isUpper,
}) {
  const cejNy = 0.56;
  final cejHalf = isFirst ? 0.46 : 0.48;
  final crownHalf = isFirst ? 0.72 : 0.75;

  final roots = <Path>[];
  final backRoots = <Path>[];
  final pulps = <Path>[];

  if (isUpper && isFirst) {
    final palatalRoot = Path()
      ..moveTo(pt(-cejHalf * 0.75, cejNy).dx, pt(-cejHalf * 0.75, cejNy).dy)
      ..quadraticBezierTo(
        pt(0.28, 0.28).dx,
        pt(0.28, 0.28).dy,
        pt(0.22, 0.14).dx,
        pt(0.22, 0.14).dy,
      )
      ..quadraticBezierTo(
        pt(0.38, 0.30).dx,
        pt(0.38, 0.30).dy,
        pt(cejHalf * 0.85, cejNy).dx,
        pt(cejHalf * 0.85, cejNy).dy,
      )
      ..close();
    backRoots.add(palatalRoot);

    final buccalRoot = Path()
      ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
      ..cubicTo(
        pt(-cejHalf * 0.85, 0.34).dx,
        pt(-cejHalf * 0.34, 0.34).dy,
        pt(-0.22, 0.18).dx,
        pt(-0.22, 0.18).dy,
        pt(-0.14, 0.11).dx,
        pt(-0.14, 0.11).dy,
      )
      ..cubicTo(
        pt(0.02, 0.18).dx,
        pt(0.02, 0.18).dy,
        pt(cejHalf * 0.75, 0.36).dx,
        pt(cejHalf * 0.75, 0.36).dy,
        pt(cejHalf, cejNy).dx,
        pt(cejHalf, cejNy).dy,
      )
      ..close();
    roots.add(buccalRoot);
  } else {
    final apexNy = isFirst ? 0.11 : 0.13;
    final bend = isFirst ? 0.04 : 0.09;
    final singleRoot = Path()
      ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
      ..cubicTo(
        pt(-cejHalf * 0.85, 0.34).dx,
        pt(-cejHalf * 0.85, 0.34).dy,
        pt(-0.14 + bend * 0.5, apexNy + 0.08).dx,
        pt(-0.14 + bend * 0.5, apexNy + 0.08).dy,
        pt(bend, apexNy).dx,
        pt(bend, apexNy).dy,
      )
      ..cubicTo(
        pt(0.16 + bend, apexNy + 0.08).dx,
        pt(0.16 + bend, apexNy + 0.08).dy,
        pt(cejHalf * 0.85, 0.34).dx,
        pt(cejHalf * 0.85, 0.34).dy,
        pt(cejHalf, cejNy).dx,
        pt(cejHalf, cejNy).dy,
      )
      ..close();
    roots.add(singleRoot);
  }

  pulps.add(
    Path()
      ..moveTo(pt(0.0, 0.18).dx, pt(0.0, 0.18).dy)
      ..lineTo(pt(-0.16, cejNy + 0.12).dx, pt(-0.16, cejNy + 0.12).dy)
      ..lineTo(pt(0.16, cejNy + 0.12).dx, pt(cejHalf * 0.3, cejNy + 0.12).dy)
      ..close(),
  );

  final cuspTipNy = isFirst ? 0.96 : 0.93;
  final crown = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.04).dx,
      pt(0, cejNy - 0.04).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalf, cejNy + 0.12).dx,
      pt(crownHalf, cejNy + 0.12).dy,
      pt(crownHalf, 0.78).dx,
      pt(crownHalf, 0.78).dy,
      pt(crownHalf * 0.82, 0.84).dx,
      pt(crownHalf * 0.82, 0.84).dy,
    )
    ..lineTo(pt(isFirst ? -0.04 : 0.0, cuspTipNy).dx,
        pt(isFirst ? -0.04 : 0.0, cuspTipNy).dy)
    ..lineTo(pt(-crownHalf * 0.84, 0.84).dx, pt(-crownHalf * 0.84, 0.84).dy)
    ..cubicTo(
      pt(-crownHalf, 0.78).dx,
      pt(-crownHalf, 0.78).dy,
      pt(-crownHalf, cejNy + 0.12).dx,
      pt(-crownHalf, cejNy + 0.12).dy,
      pt(-cejHalf, cejNy).dx,
      pt(-cejHalf, cejNy).dy,
    )
    ..close();

  final lingualCuspArc = Path()
    ..moveTo(pt(-crownHalf * 0.55, 0.83).dx, pt(-crownHalf * 0.55, 0.83).dy)
    ..quadraticBezierTo(
      pt(isFirst ? 0.18 : 0.12, 0.91).dx,
      pt(isFirst ? 0.18 : 0.12, 0.91).dy,
      pt(crownHalf * 0.65, 0.82).dx,
      pt(crownHalf * 0.65, 0.82).dy,
    );
  final buccalRidge = Path()
    ..moveTo(pt(0, cejNy + 0.08).dx, pt(0, cejNy + 0.08).dy)
    ..lineTo(pt(isFirst ? -0.04 : 0.0, cuspTipNy - 0.04).dx,
        pt(isFirst ? -0.04 : 0.0, cuspTipNy - 0.04).dy);

  return _ToothGeometry(
    roots: roots,
    backRoots: backRoots,
    crown: crown,
    pulpAndCanals: pulps,
    details: [lingualCuspArc, buccalRidge],
  );
}

_ToothGeometry _upperMolarGeometry({
  required Offset Function(double nx, double ny) pt,
  required int variant,
  double crownScale = 1.0,
  double? rootApexNy,
}) {
  const cejNy = 0.55;
  final scale = crownScale *
      switch (variant) {
        1 => 1.0,
        2 => 0.92,
        _ => 0.82,
      };
  final cejHalf = 0.64 * scale;
  final crownHalf = 0.86 * scale;
  final apexNy = rootApexNy ??
      switch (variant) {
        1 => 0.10,
        2 => 0.13,
        _ => 0.19,
      };
  final rootSpread = switch (variant) {
    1 => 0.56,
    2 => 0.42,
    _ => 0.24,
  };
  final distalBend = switch (variant) {
    1 => 0.04,
    2 => 0.12,
    _ => 0.20,
  };

  final palatalRoot = Path()
    ..moveTo(pt(-0.24 * scale, cejNy).dx, pt(-0.24 * scale, cejNy).dy)
    ..cubicTo(
      pt(-0.16, 0.30).dx,
      pt(-0.16, 0.30).dy,
      pt(-0.08 + distalBend * 0.4, apexNy + 0.02).dx,
      pt(-0.08 + distalBend * 0.4, apexNy + 0.02).dy,
      pt(0.02 + distalBend * 0.4, apexNy - 0.02).dx,
      pt(0.02 + distalBend * 0.4, apexNy - 0.02).dy,
    )
    ..cubicTo(
      pt(0.14 + distalBend * 0.4, apexNy + 0.02).dx,
      pt(0.14 + distalBend * 0.4, apexNy + 0.02).dy,
      pt(0.20, 0.30).dx,
      pt(0.20, 0.30).dy,
      pt(0.24 * scale, cejNy).dx,
      pt(0.24 * scale, cejNy).dy,
    )
    ..close();

  final furcationNy = variant == 3 ? 0.34 : 0.42;
  final buccalRoots = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..cubicTo(
      pt(-cejHalf * 1.02, 0.36).dx,
      pt(-cejHalf * 1.02, 0.36).dy,
      pt(-rootSpread, apexNy + 0.08).dx,
      pt(-rootSpread, apexNy + 0.08).dy,
      pt(-rootSpread * 0.82 + distalBend, apexNy + 0.02).dx,
      pt(-rootSpread * 0.82 + distalBend, apexNy + 0.02).dy,
    )
    ..quadraticBezierTo(
      pt(-0.14, 0.28).dx,
      pt(-0.14, 0.28).dy,
      pt(0.0, furcationNy).dx,
      pt(0.0, furcationNy).dy,
    )
    ..quadraticBezierTo(
      pt(0.16, 0.28).dx,
      pt(0.16, 0.28).dy,
      pt(rootSpread * 0.78 + distalBend, apexNy + 0.05).dx,
      pt(rootSpread * 0.78 + distalBend, apexNy + 0.05).dy,
    )
    ..cubicTo(
      pt(rootSpread + distalBend, apexNy + 0.12).dx,
      pt(rootSpread + distalBend, apexNy + 0.12).dy,
      pt(cejHalf * 1.02, 0.36).dx,
      pt(cejHalf * 1.02, 0.36).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..close();

  final crown = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.03).dx,
      pt(0, cejNy - 0.03).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalf, cejNy + 0.10).dx,
      pt(crownHalf, cejNy + 0.10).dy,
      pt(crownHalf, 0.80).dx,
      pt(crownHalf, 0.80).dy,
      pt(crownHalf * 0.82, 0.87).dx,
      pt(crownHalf * 0.82, 0.87).dy,
    )
    ..quadraticBezierTo(
      pt(crownHalf * 0.46, 0.96).dx,
      pt(crownHalf * 0.46, 0.96).dy,
      pt(0.04, 0.87).dx,
      pt(0.04, 0.87).dy,
    )
    ..quadraticBezierTo(
      pt(-crownHalf * 0.46, 0.98).dx,
      pt(-crownHalf * 0.46, 0.98).dy,
      pt(-crownHalf * 0.85, 0.88).dx,
      pt(-crownHalf * 0.85, 0.88).dy,
    )
    ..cubicTo(
      pt(-crownHalf, 0.80).dx,
      pt(-crownHalf, 0.80).dy,
      pt(-crownHalf, cejNy + 0.10).dx,
      pt(-crownHalf, cejNy + 0.10).dy,
      pt(-cejHalf, cejNy).dx,
      pt(-cejHalf, cejNy).dy,
    )
    ..close();

  final pulp = Path()
    ..moveTo(pt(-rootSpread * 0.68 + distalBend, apexNy + 0.08).dx,
        pt(-rootSpread * 0.68 + distalBend, apexNy + 0.08).dy)
    ..lineTo(
        pt(-0.32 * scale, cejNy + 0.15).dx, pt(-0.32 * scale, cejNy + 0.15).dy)
    ..lineTo(
        pt(0.32 * scale, cejNy + 0.15).dx, pt(0.32 * scale, cejNy + 0.15).dy)
    ..lineTo(pt(rootSpread * 0.65 + distalBend, apexNy + 0.10).dx,
        pt(rootSpread * 0.65 + distalBend, apexNy + 0.10).dy)
    ..lineTo(pt(0.08, cejNy + 0.02).dx, pt(0.08, cejNy + 0.02).dy)
    ..lineTo(pt(-0.08, cejNy + 0.02).dx, pt(-0.08, cejNy + 0.02).dy)
    ..close();

  final buccalGroove = Path()
    ..moveTo(pt(0.04, 0.87).dx, pt(0.04, 0.87).dy)
    ..lineTo(pt(0.02, cejNy + 0.14).dx, pt(0.02, cejNy + 0.14).dy);

  return _ToothGeometry(
    roots: [buccalRoots],
    backRoots: [palatalRoot],
    crown: crown,
    pulpAndCanals: [pulp],
    details: [buccalGroove],
  );
}

_ToothGeometry _lowerMolarGeometry({
  required Offset Function(double nx, double ny) pt,
  required int variant,
  double crownScale = 1.0,
  double? rootApexNy,
}) {
  const cejNy = 0.55;
  final scale = crownScale *
      switch (variant) {
        1 => 1.0,
        2 => 0.92,
        _ => 0.82,
      };
  final cejHalf = 0.66 * scale;
  final crownHalf = 0.88 * scale;
  final apexNy = rootApexNy ??
      switch (variant) {
        1 => 0.10,
        2 => 0.13,
        _ => 0.19,
      };
  final rootSpread = switch (variant) {
    1 => 0.54,
    2 => 0.40,
    _ => 0.24,
  };
  final distalBend = switch (variant) {
    1 => 0.05,
    2 => 0.12,
    _ => 0.20,
  };
  final furcationNy = variant == 3 ? 0.35 : 0.43;

  final roots = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..cubicTo(
      pt(-cejHalf * 1.02, 0.36).dx,
      pt(-cejHalf * 1.02, 0.36).dy,
      pt(-rootSpread, apexNy + 0.08).dx,
      pt(-rootSpread, apexNy + 0.08).dy,
      pt(-rootSpread * 0.78 + distalBend, apexNy).dx,
      pt(-rootSpread * 0.78 + distalBend, apexNy).dy,
    )
    ..quadraticBezierTo(
      pt(-0.12, 0.26).dx,
      pt(-0.12, 0.26).dy,
      pt(0.0, furcationNy).dx,
      pt(0.0, furcationNy).dy,
    )
    ..quadraticBezierTo(
      pt(0.14, 0.26).dx,
      pt(0.14, 0.26).dy,
      pt(rootSpread * 0.78 + distalBend, apexNy + 0.03).dx,
      pt(rootSpread * 0.78 + distalBend, apexNy + 0.03).dy,
    )
    ..cubicTo(
      pt(rootSpread + distalBend, apexNy + 0.10).dx,
      pt(rootSpread + distalBend, apexNy + 0.10).dy,
      pt(cejHalf * 1.02, 0.36).dx,
      pt(cejHalf * 1.02, 0.36).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..close();

  final crown = Path()
    ..moveTo(pt(-cejHalf, cejNy).dx, pt(-cejHalf, cejNy).dy)
    ..quadraticBezierTo(
      pt(0, cejNy - 0.03).dx,
      pt(0, cejNy - 0.03).dy,
      pt(cejHalf, cejNy).dx,
      pt(cejHalf, cejNy).dy,
    )
    ..cubicTo(
      pt(crownHalf, cejNy + 0.10).dx,
      pt(crownHalf, cejNy + 0.10).dy,
      pt(crownHalf, 0.79).dx,
      pt(crownHalf, 0.79).dy,
      pt(crownHalf * 0.85, 0.86).dx,
      pt(crownHalf * 0.85, 0.86).dy,
    );

  final details = <Path>[];

  if (variant == 1) {
    crown
      ..quadraticBezierTo(
        pt(crownHalf * 0.68, 0.93).dx,
        pt(crownHalf * 0.68, 0.93).dy,
        pt(crownHalf * 0.44, 0.86).dx,
        pt(crownHalf * 0.44, 0.86).dy,
      )
      ..quadraticBezierTo(
        pt(0.08, 0.97).dx,
        pt(0.08, 0.97).dy,
        pt(-crownHalf * 0.26, 0.87).dx,
        pt(-crownHalf * 0.26, 0.87).dy,
      )
      ..quadraticBezierTo(
        pt(-crownHalf * 0.58, 0.98).dx,
        pt(-crownHalf * 0.58, 0.98).dy,
        pt(-crownHalf * 0.86, 0.88).dx,
        pt(-crownHalf * 0.86, 0.88).dy,
      );

    details.add(
      Path()
        ..moveTo(pt(-crownHalf * 0.26, 0.87).dx, pt(-crownHalf * 0.26, 0.87).dy)
        ..lineTo(pt(-crownHalf * 0.24, cejNy + 0.12).dx,
            pt(-crownHalf * 0.24, cejNy + 0.12).dy),
    );
    details.add(
      Path()
        ..moveTo(pt(crownHalf * 0.44, 0.86).dx, pt(crownHalf * 0.44, 0.86).dy)
        ..lineTo(pt(crownHalf * 0.38, cejNy + 0.18).dx,
            pt(crownHalf * 0.38, cejNy + 0.18).dy),
    );
  } else {
    crown
      ..quadraticBezierTo(
        pt(crownHalf * 0.45, 0.95).dx,
        pt(crownHalf * 0.45, 0.95).dy,
        pt(0.0, 0.86).dx,
        pt(0.0, 0.86).dy,
      )
      ..quadraticBezierTo(
        pt(-crownHalf * 0.45, 0.97).dx,
        pt(-crownHalf * 0.45, 0.97).dy,
        pt(-crownHalf * 0.85, 0.87).dx,
        pt(-crownHalf * 0.85, 0.87).dy,
      );

    details.add(
      Path()
        ..moveTo(pt(0.0, 0.86).dx, pt(0.0, 0.86).dy)
        ..lineTo(pt(0.0, cejNy + 0.14).dx, pt(0.0, cejNy + 0.14).dy),
    );
  }

  crown
    ..cubicTo(
      pt(-crownHalf, 0.80).dx,
      pt(-crownHalf, 0.80).dy,
      pt(-crownHalf, cejNy + 0.10).dx,
      pt(-crownHalf, cejNy + 0.10).dy,
      pt(-cejHalf, cejNy).dx,
      pt(-cejHalf, cejNy).dy,
    )
    ..close();

  final pulp = Path()
    ..moveTo(pt(-rootSpread * 0.65 + distalBend, apexNy + 0.08).dx,
        pt(-rootSpread * 0.65 + distalBend, apexNy + 0.08).dy)
    ..lineTo(
        pt(-0.34 * scale, cejNy + 0.15).dx, pt(-0.34 * scale, cejNy + 0.15).dy)
    ..lineTo(
        pt(0.34 * scale, cejNy + 0.15).dx, pt(0.34 * scale, cejNy + 0.15).dy)
    ..lineTo(pt(rootSpread * 0.65 + distalBend, apexNy + 0.10).dx,
        pt(rootSpread * 0.65 + distalBend, apexNy + 0.10).dy)
    ..lineTo(pt(0.10, cejNy + 0.02).dx, pt(0.10, cejNy + 0.02).dy)
    ..lineTo(pt(-0.10, cejNy + 0.02).dx, pt(-0.10, cejNy + 0.02).dy)
    ..close();

  return _ToothGeometry(
    roots: [roots],
    crown: crown,
    pulpAndCanals: [pulp],
    details: details,
  );
}

/// Computes the panel width for the active panel and tab on a given screen
/// width.
/// - On phone-width viewports (`< 490`), the panel expands to fill the screen
///   width so the compact dental arch and forms utilize all available horizontal
///   space.
/// - When the active panel tab displays a dental chart, the panel widens:
///   on medium screens (`490..1000`) to `440px` so the compact ovoid arch has
///   generous horizontal room, and on wide screens (`>= kOpgViewportMinWidth`)
///   up to `kOpgWidePanelWidth` for the 16-column OPG panoramic chart.
double computePanelWidth({
  required double screenWidth,
  required bool minimized,
  required String? activeTabTitleKey,
}) {
  if (screenWidth < 490) return screenWidth;
  final isDentalChartTab = activeTabTitleKey == 'dentalNotes' ||
      activeTabTitleKey == 'operativeDetails';
  if (!minimized && isDentalChartTab) {
    if (screenWidth >= kOpgViewportMinWidth) {
      return math.min(kOpgWidePanelWidth, screenWidth * 0.62);
    }
    return math.min(440.0, screenWidth - 40);
  }
  return 350;
}
