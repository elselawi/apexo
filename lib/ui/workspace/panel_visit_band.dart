part of 'panel_screen.dart';

// The bubble for the visit a panel carries. A visit is not a panel and cannot
// draw a header, so this stands in for its name, state and actions.
class _VisitBand extends StatefulWidget {
  const _VisitBand({
    required this.panel,
    required this.session,
    required this.dirtyVisits,
  });

  final Panel panel;
  final HostedRecordSession session;

  /// How many records this panel carries whose draft differs from the store.
  final int dirtyVisits;

  @override
  State<_VisitBand> createState() => _VisitBandState();
}

class _VisitBandState extends State<_VisitBand> {
  final FlyoutController _menu = FlyoutController();

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
    _menu.dispose();
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
    return StreamBuilder<int>(
      stream: widget.panel.workspace.revision.stream,
      builder: (context, _) => StreamBuilder<bool>(
        stream: session.hasUnsavedChanges.stream,
        builder: (context, _) {
          final theme = FluentTheme.of(context);
          // Blend over the solid fill: Fluent's scaffold background is
          // translucent acrylic, so a bubble painted on it would wash out.
          final background = Color.alphaBlend(
            accent.withValues(alpha: 0.055),
            theme.resources.solidBackgroundFillColorSecondary,
          );
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 8, 4),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  key: WK.visitBand,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.34),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
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
                          padding:
                              const EdgeInsetsDirectional.fromSTEB(8, 2, 8, 2),
                          // Keyed by visit id: switching visits rebuilds the
                          // form instead of keeping the old one's state.
                          child: KeyedSubtree(
                            key: ValueKey('visit-content-${session.itemId}'),
                            child: content,
                          ),
                        ),
                      _buildTransient(context),
                      _buildAttachments(accent),
                      _buildFooter(context, accent),
                    ],
                  ),
                ),
                PositionedDirectional(
                  top: -5,
                  start: 102,
                  child: CustomPaint(
                    size: const Size(14, 6),
                    painter: _VisitBandArrow(
                      background: background,
                      border: accent.withValues(alpha: 0.34),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The colour the visit's kind is known by, for the bubble and its footer.
  Color get _accent =>
      widget.panel.accent ?? FluentTheme.of(context).accentColor;

  Widget _buildIdentity(BuildContext context) {
    final session = widget.session;
    final theme = FluentTheme.of(context);
    final done = session.isDone;
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
                fontSize: 12,
                color: session.isArchived ? Colors.grey : null,
              ),
            ),
          ),
          if (session.isArchived) _chip(txt('archived'), Colors.grey),
          Container(
            key: WK.visitState,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (done ? Colors.green : Colors.orange).withValues(
                alpha: 0.14,
              ),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: (done ? Colors.green : Colors.orange).withValues(
                  alpha: 0.45,
                ),
              ),
            ),
            child: Txt(
              txt(done ? 'completed' : 'pending'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: done ? Colors.green : Colors.orange,
              ),
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
          child: Txt(label, style: TextStyle(fontSize: 10, color: color)),
        ),
      );

  Widget _buildTransient(BuildContext context) {
    if (_transient == null) return const SizedBox.shrink();
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 8, 0),
      child: Row(
        children: [
          Icon(FluentIcons.check_mark, size: 11, color: Colors.green),
          const SizedBox(width: 4),
          Flexible(
            child: Txt(
              txt(_transient!),
              key: WK.visitMarkedCompleted,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption?.copyWith(
                fontSize: 10,
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
  Widget _buildFooter(BuildContext context, Color accent) {
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
        color:
            Color.alphaBlend(accent.withValues(alpha: 0.08), theme.menuColor),
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
                    style: TextStyle(fontSize: 10, color: Colors.orange),
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
              FlyoutTarget(
                controller: _menu,
                child: Tooltip(
                  message: txt('more'),
                  child: IconButton(
                    key: WK.visitMenu,
                    icon: const Icon(FluentIcons.more, size: 14),
                    onPressed: _openMenu,
                  ),
                ),
              ),
              Tooltip(
                message: txt('detachKeepsDraft'),
                child: Button(
                  key: WK.visitDetach,
                  onPressed: widget.panel.detach,
                  child: ButtonContent(
                    WindowsIcons.chrome_close,
                    txt('close'),
                    size: 11,
                  ),
                ),
              ),
              if (session.canArchive)
                DeleteButton(
                key: WK.visitDelete,
                restorable: true,
                actionText: actionText,
                actionIcon: actionIcon,
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
                child: ButtonContent(actionIcon, actionText, size: 11),
              ),
              if (dirty)
                FilledButton(
                  key: WK.visitSave,
                  onPressed: () => unawaited(_saveVisit()),
                  child: ButtonContent(
                    WindowsIcons.save,
                    txt(session.saveLabel),
                    size: 11,
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

  Future<void> _openMenu() async {
    final session = widget.session;
    await flyoutFocusFix(context);
    if (!mounted) return;
    unawaited(_menu.showFlyout<void>(
      dismissWithEsc: true,
      builder: (context) => MenuFlyout(items: [
        MenuFlyoutItem(
          key: WK.visitMenuDone,
          // Goes through the session so the toggle edits the open draft.
          text: Txt(txt(session.isDone ? 'markAsPending' : 'markAsDone')),
          leading: Icon(
            session.isDone ? FluentIcons.hour_glass : WindowsIcons.completed,
          ),
          onPressed: () {
            session.markDone(!session.isDone);
            setState(() {});
          },
        ),
      ]),
    ));
  }
}

// Same 14x6 tail as the post-op card's, so the two bubbles cannot grow
// different arrows.
class _VisitBandArrow extends CustomPainter {
  const _VisitBandArrow({required this.background, required this.border});

  final Color background;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final tail = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(tail, Paint()..color = background);
    // Only the two upper edges are stroked; the bubble's border draws the base.
    final edge = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
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
