part of 'panel_screen.dart';

/// The band: the record a panel **carries**, drawn as a bubble under the panel's
/// own workspaces, with its own name, its own footer and its own editor.
///
/// A visit is not a panel, so it cannot draw a header — this is what says whose
/// windows in the row are, where the visit stands, and what closes it
/// (plan §4.1, §4.4). It is also where the visit's **appointment form** lives:
/// when, how long, whose, and what was planned fit in a compact strip, so they
/// need no window and no row slot of their own.
///
/// Everything it shows is read from the session's draft, so it is live: typing a
/// post-op note flips `pending` to `completed` at once, and a line says so
/// (plan §8.1).
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

  /// Notes a `pending → completed` transition the moment the band draws it, and
  /// says so once the frame is done.
  ///
  /// The band is rebuilt from the session's own dirty stream rather than being
  /// recreated, so this cannot live in `didUpdateWidget`: the widget the user
  /// sees flip is this one, and it is the one that has to notice.
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
    // A panel can carry a different visit without being rebuilt from scratch.
    // The state that remembers *which* visit was last drawn belongs to the visit,
    // not to the band's slot.
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
          // Blended over the panel's own opaque fill, not over
          // `scaffoldBackgroundColor`: that one is a 25%-opaque acrylic layer in
          // Fluent, and a bubble painted on it is translucent — its tail then
          // washes out over the page while the bubble above it looks solid.
          final background = Color.alphaBlend(
            accent.withValues(alpha: 0.055),
            theme.resources.solidBackgroundFillColorSecondary,
          );
          return Padding(
            // Room above for the tail, so the bubble points up at the patient
            // record above it instead of merely sitting under it.
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
                          // The form belongs to the visit: a different visit is a
                          // different editor, never the old one relabelled. This
                          // is what keeps its date, time and duration honest the
                          // moment the chart switches scope.
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
          // Whose visit this is and when: a label, never a selector — a third
          // control that changes the selection is how two controls start to
          // disagree (plan §4.8). The band's actions live in its footer, so the
          // identity line is only identity.
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

  /// `Marked completed`, for a moment, on its own line: the state changed while
  /// the user was typing, and this is the sentence that says so (plan §8.1).
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

  /// The editors hanging off the band — a visit's labwork order and its photos —
  /// as the same attachment tray a panel draws under itself.
  ///
  /// They are the record's **parts**, not its tools: the dock above carries the
  /// one thing that opens the record's own surface, and these sit at the band's
  /// foot, one click from their editors and one click back. Empty for a record
  /// that hangs nothing off its band.
  Widget _buildAttachments(Color accent) {
    final windows = <PanelWindow>[
      for (final window in widget.session.windows)
        if (window.attachedTo == PanelWindow.bandAttachment) window,
    ];
    if (windows.isEmpty) return const SizedBox.shrink();
    // The record's windows live in the row's attached slot; the tray switches
    // exactly what the dock would have switched.
    return WindowAttachments(
      key: WK.visitBandAttachments,
      windows: windows,
      accent: accent,
      // The band has an edge of its own: no paperclip ahead of the chips, and
      // the same small inset every field above them starts at, so the tray reads
      // as the band's foot rather than as an indent under it.
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

  /// The band's footer: the retained-draft hint and its way back to that visit,
  /// then the record's own actions — the same grammar as a panel's bottom bar.
  ///
  /// The count changes what is shown, never which visit is selected (plan §2.4).
  /// Save and Delete are standard Fluent buttons, so their colours follow the
  /// theme; Close keeps its draft and says so in its tooltip.
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
        // A footer of its own: a different surface from the fields above it, so
        // the eye reads "actions" rather than one more row of the form.
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
                  onPressed: () => unawaited(session.save()),
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
    // Deleting takes the visit off this panel as well; restoring keeps it open
    // where it is.
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
          // The toggle that already exists in the visit's menu, routed through
          // the session so it edits the open draft — and is reversible in place
          // (plan §8.1).
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

/// The small tail on top of the visit bubble, pointing up at the patient
/// record — its name and its workspaces — that the band belongs to.
///
/// The band is not another field group: it is a card *about* the visit the
/// patient panel carries. The tail is what makes that relation visible without a
/// label saying so. It is drawn at the post-op card's size and depth — the same
/// gesture over the same kind of bubble — so the two cards of the app cannot
/// grow two different arrows.
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
    // Only the two upper edges are drawn: the bottom edge is the bubble's own
    // border, and stroking it would draw a line across the tail.
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
