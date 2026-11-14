part of 'panel_screen.dart';

/// How long the band takes to unfold over the panel when a visit opens.
const _bandEntranceDuration = Duration(milliseconds: 260);

/// A switch between visits replays that unfold, quicker than the first visit's
/// so moving between visits does not hold up the work.
const _bandSwitchDuration = Duration(milliseconds: 150);

// The band for the visit a panel carries. A visit is not a panel and cannot
// draw a header, so this stands in for its name, state and actions.
class _VisitBand extends StatefulWidget {
  const _VisitBand({
    required this.panel,
    required this.session,
    required this.dirtyVisits,
    required this.replacing,
  });

  final Panel panel;
  final HostedRecordSession session;

  /// How many records this panel carries whose draft differs from the store.
  final int dirtyVisits;

  /// True when this band takes another visit's place: it arrives quickly and
  /// keeps its height, so the record under it is not shoved about.
  final bool replacing;

  @override
  State<_VisitBand> createState() => _VisitBandState();
}

class _VisitBandState extends State<_VisitBand> {
  Timer? _transientTimer;
  String? _transient;
  bool _wasDone = false;

  @override
  void initState() {
    super.initState();
    _wasDone = widget.session.isDone;
  }

  @override
  void dispose() {
    _transientTimer?.cancel();
    super.dispose();
  }

  /// Shows [key] for a moment — the transition that used to happen in silence.
  void _flash(String key) {
    _transientTimer?.cancel();
    setState(() => _transient = key);
    _transientTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _transient = null);
    });
  }

  // Noticed in build, not didUpdateWidget: the band is rebuilt from the
  // session's dirty stream rather than recreated.
  void _noticeCompletion(bool done) {
    if (done == _wasDone) return;
    _wasDone = done;
    if (!done) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _flash('visitMarkedCompleted');
    });
  }

  @override
  void didUpdateWidget(covariant _VisitBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The band survives a switch to a different visit, so the per-visit state
    // resets here.
    if (!identical(oldWidget.session, widget.session)) {
      _transientTimer?.cancel();
      _transient = null;
      _wasDone = widget.session.isDone;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final accent = session.accent ?? _accent;
    final theme = FluentTheme.of(context);
    // The tail grows out of the footer, so it must be the footer's colour.
    final footerBackground = Color.alphaBlend(
      accent.withValues(alpha: 0.08),
      theme.menuColor,
    );
    return StreamBuilder<int>(
      stream: widget.panel.workspace.revision.stream,
      builder: (context, _) => StreamBuilder<bool>(
        stream: session.hasUnsavedChanges.stream,
        builder: (context, _) {
          final materials = FluentMaterials.of(context);
          final background = Color.alphaBlend(
            accent.withValues(alpha: 0.06),
            materials.card,
          );
          return _Reveal(
            duration:
                widget.replacing ? _bandSwitchDuration : _bandEntranceDuration,
            grow: !widget.replacing,
            child: Padding(
              // The tail hangs into this bottom padding, below the card.
              padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 8, 9),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    key: WK.visitBand,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: FluentMaterials.surfaceRadius,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.34),
                        width: FluentMaterials.hairlineWidth,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildIdentity(context),
                        if (session.bandContent case final content?)
                          Padding(
                            key: WK.visitContent,
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                8, 2, 8, 2),
                            // Keyed by visit id: switching visits rebuilds the
                            // form instead of keeping the old one's state.
                            child: KeyedSubtree(
                              key: ValueKey('visit-content-${session.itemId}'),
                              child: content,
                            ),
                          ),
                        _buildTransient(context),
                        _buildAttachments(accent),
                        _buildFooter(context, accent, footerBackground),
                      ],
                    ),
                  ),
                  // Points down at the record the visit was opened from.
                  PositionedDirectional(
                    bottom: -5,
                    start: 16,
                    child: CustomPaint(
                      key: WK.visitBandTail,
                      size: const Size(14, 6),
                      painter: _VisitBandArrow(
                        background: footerBackground,
                        border: accent.withValues(alpha: 0.34),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The colour the visit's kind is known by, for the band and its footer.
  Color get _accent =>
      widget.panel.accent ?? FluentTheme.of(context).accentColor;

  Widget _buildIdentity(BuildContext context) {
    final session = widget.session;
    final theme = FluentTheme.of(context);
    final done = session.isDone;
    final color = done ? Colors.green : Colors.orange;
    _noticeCompletion(done);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 0),
      child: Row(
        children: [
          Txt(session.unicodeSymbol, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: Txt(
              session.bandLabel,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.bodyStrong?.copyWith(
                fontSize: 13,
                color: session.isArchived ? Colors.grey : null,
              ),
            ),
          ),
          if (session.isArchived) _chip(txt('archived'), Colors.grey),
          Container(
            key: WK.visitState,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (color).withValues(
                alpha: 0.14,
              ),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: (color).withValues(
                  alpha: 0.45,
                ),
              ),
            ),
            child: Row(
              spacing: 5,
              children: [
                Icon(
                  done ? WindowsIcons.check_mark : FluentIcons.hour_glass,
                  color: color,
                ),
                Txt(
                  txt(done ? 'completed' : 'pending'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Txt(label, style: TextStyle(fontSize: 12, color: color)),
        ),
      );

  Widget _buildTransient(BuildContext context) {
    if (_transient == null) return const SizedBox.shrink();
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 8, 0),
      child: Row(
        children: [
          Icon(FluentIcons.check_mark, size: 20, color: Colors.green),
          const SizedBox(width: 4),
          Flexible(
            child: Txt(
              txt(_transient!),
              key: WK.visitMarkedCompleted,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption?.copyWith(
                fontSize: 13,
                color: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachments(Color accent) {
    final windows = <PanelWindow>[
      for (final window in widget.session.windows)
        if (window.attachedTo == PanelWindow.bandAttachment) window,
    ];
    if (windows.isEmpty) return const SizedBox.shrink();
    return WindowAttachments(
      key: WK.visitBandAttachments,
      windows: windows,
      accent: accent,
      marker: false,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
      keyForWindow: (window) =>
          WK.attachmentToggle(window.id, owner: PanelWindow.bandAttachment),
      isOpen: (window) =>
          widget.panel.workspace.isOpen(window.id, slot: kAttachedSlot),
      enabled: (window) => !window.onlyIfSaved || !widget.session.isNew,
      onToggle: (window) =>
          widget.panel.workspace.toggle(window.id, slot: kAttachedSlot),
    );
  }

  // Close keeps the draft; its tooltip says so.
  Widget _buildFooter(BuildContext context, Color accent, Color background) {
    final session = widget.session;
    final theme = FluentTheme.of(context);
    final dirty = session.hasPendingEdits;
    final otherDirty = widget.panel.owned
        .where((owned) => !identical(owned, session) && owned.hasPendingEdits)
        .toList();
    final archived = session.isArchived;
    final actionIcon = archived ? WindowsIcons.undo : WindowsIcons.delete;
    final actionText = txt(archived ? 'restore' : 'delete');
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 7),
      decoration: BoxDecoration(
        color: background,
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.22)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (otherDirty.isNotEmpty) ...[
            Row(
              children: [
                const UnsavedDot(size: 7),
                const SizedBox(width: 6),
                Expanded(
                  child: Txt(
                    txt('unsavedVisitsCount')
                        .replaceAll('{count}', '${widget.dirtyVisits}'),
                    key: WK.visitUnsavedCount,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  key: WK.visitMoveToVisit,
                  onPressed: () => widget.panel.attach(otherDirty.first),
                  child: ButtonContent(
                    FluentIcons.go,
                    txt('moveToVisit'),
                    size: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Tooltip(
                message: txt('detachKeepsDraft'),
                child: IconButton(
                  key: WK.visitDetach,
                  onPressed: widget.panel.detach,
                  icon: ButtonContent(
                    WindowsIcons.clear,
                    txt('close'),
                    size: 13,
                  ),
                ),
              ),
              if (session.canArchive)
                DeleteButton(
                  key: WK.visitDelete,
                  restorable: true,
                  actionText: actionText,
                  actionIcon: actionIcon,
                  // Red says this removes the visit, not just closes the band.
                  style: ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(
                      archived
                          ? theme.accentColor.normal
                          : theme.resources.systemFillColorCritical,
                    ),
                  ),
                  preview: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 5,
                    children: [
                      Txt(session.unicodeSymbol,
                          style: const TextStyle(fontSize: 12)),
                      Txt(session.displayTitle),
                    ],
                  ),
                  onConfirm: () => unawaited(_archiveOrRestore(archived)),
                  child: ButtonContent(actionIcon, actionText, size: 13),
                ),
              if (dirty)
                FilledButton(
                  key: WK.visitSave,
                  onPressed: () => unawaited(_saveVisit()),
                  child: ButtonContent(
                    WindowsIcons.save,
                    txt(session.saveLabel),
                    size: 13,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveVisit() async {
    try {
      await widget.session.save();
    } catch (e, st) {
      logger('Saving "${widget.session.itemId}" failed', st);
      showErrorMessage(e, 'savingFailed');
    }
  }

  Future<void> _archiveOrRestore(bool archived) async {
    final session = widget.session;
    final panel = widget.panel;
    try {
      await session.setArchived(!archived);
    } catch (e, st) {
      logger('Archiving "${session.itemId}" failed', st);
      showErrorMessage(e, 'savingFailed');
      return;
    }
    // Deleting also detaches the visit; restoring leaves it open.
    if (!archived && identical(panel.attached, session)) panel.detach();
  }
}

// The same 14x6 tail as the post-op card's, flipped: this one hangs under the
// band and points down at the record the visit was opened from.
class _VisitBandArrow extends CustomPainter {
  const _VisitBandArrow({required this.background, required this.border});

  final Color background;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final tail = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(tail, Paint()..color = background);
    // Only the two lower edges are stroked; the band's border draws the base.
    final edge = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(
      edge,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_VisitBandArrow oldDelegate) =>
      oldDelegate.background != background || oldDelegate.border != border;
}

/// Unfolds [child] into place: its height grows from the top while it fades and
/// drops the last few pixels, so whatever sits under it slides instead of
/// jumping. The band and the record's read-only notice share it.
class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.child,
    this.duration = _bandEntranceDuration,
    this.grow = true,
  });

  final Widget child;
  final Duration duration;

  /// Whether the child gains its height as it arrives. A band that takes
  /// another visit's place does not: growing would drop the record out from
  /// under it first, so that band only fades and drops into place.
  final bool grow;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _value = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _value,
      // One shape for every value: swapping the wrappers out at rest would
      // rebuild the band's whole subtree — and the form on it — on the frame
      // the animation ends.
      builder: (context, child) {
        final value = reduceMotion ? 1.0 : _value.value;
        return ClipRect(
          // Settled: no clip, no layers between the panel and its band.
          clipBehavior: value >= 1 ? Clip.none : Clip.hardEdge,
          child: Align(
            alignment: AlignmentDirectional.topCenter,
            // A replacing band keeps its height; it only fades into place.
            heightFactor: widget.grow ? value : 1,
            child: Opacity(
              // A replacing band starts half visible so the change reads as one
              // band replacing another, not as a blink.
              opacity: widget.grow ? value : 0.4 + 0.6 * value,
              child: FractionalTranslation(
                translation:
                    Offset(0, (widget.grow ? -0.03 : -0.015) * (1 - value)),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
