part of 'opg_dental_chart.dart';

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
    final allowedHalfWidth = (rootWidth + (crownWidth - rootWidth) * t) / 2.0;
    final dxFromCenter = (position.dx - size.width / 2.0).abs();
    if (dxFromCenter > allowedHalfWidth) return false;

    return super.hitTest(result, position: position);
  }
}

/// Draws subtle OPG radiograph anatomical guides (maxillary sinus floor,
/// nasal fossa, and mandibular canal / alveolar crest contour).
