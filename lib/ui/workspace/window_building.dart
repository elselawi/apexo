part of 'windows_layer.dart';

/// The layer's drawing: the stack, the cards, the phone sheet and the drag that
/// moves a window. Kept apart from the state machine that decides *what* is on
/// screen, so each file can be read as one thing.
extension _WindowsAreaBuilding on _WindowsAreaState {
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  /// The place a window was opened from, in this area's own coordinates.
  ///
  /// The pointer is recorded in the app's coordinates — a menu lives in the
  /// navigator's overlay, above the app's own widgets — so it is brought into
  /// this area's frame before it places a window.
  ///
  /// The area's own frame is not always known yet: a window can be opened into
  /// a tree that is still being built, and there is nothing to bring the
  /// position into. The app's own coordinates are then the best guess, and the
  /// window is placed again as soon as the frame is known.
  Offset? _originIn(Offset? origin) {
    if (origin == null) return null;
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize || !object.attached) {
      return origin;
    }
    return object.globalToLocal(origin);
  }

  /// The windows, each where it was put — beside the panel, or wherever it has
  /// been dragged since.
  ///
  /// A stack rather than a wrap with a scroll view: a window is always somewhere
  /// on the screen, so nothing is ever hidden below a fold that has to be
  /// scrolled to find. The layer itself draws nothing and takes no clicks: only
  /// the windows do, so the screen behind them keeps working.
  Widget _buildStack() {
    final metrics = _metrics;
    final entries = [..._live, ..._closing.values];
    final keys = {for (final entry in entries) entry.key};

    // Whatever left is forgotten; whatever stayed keeps its stacking order; a
    // window that just arrived goes on top of what was already there.
    _stack.removeWhere((key) => !keys.contains(key));
    for (final entry in entries) {
      if (!_stack.contains(entry.key)) _stack.add(entry.key);
    }
    // The window the app last asked for stays in front of the row while it is on
    // screen — including across the frames in which the rest of the row arrives.
    // The first frame that draws it must not bury it under a neighbour the plan
    // opened beside it (plan §4.8: one selection, one thing in front of it).
    final focused = _focusKey;
    if (focused != null) {
      if (!keys.contains(focused)) {
        _focusKey = null;
      } else if (_stack.last != focused) {
        _stack
          ..remove(focused)
          ..add(focused);
      }
    }
    _places.removeWhere((key, place) {
      if (keys.contains(key)) return false;
      place.dispose();
      return true;
    });
    _cells.removeWhere((key, _) => !keys.contains(key));
    // A window that is gone takes its height with it: opened again from another
    // row, it has to be measured where it now stands.
    _heights.removeWhere((key, _) => !keys.contains(key));
    _fitted.removeWhere((key) => !keys.contains(key));

    // The windows a panel opened for itself go on the grid from the panel's
    // side; a window a row asked for goes where that row is. Every entry gets a
    // place, a window already folding away included: without one it would have
    // nothing to animate out of, and would never finish leaving.
    final widths = [
      for (final entry in entries)
        entry.widthIn(metrics.bounds.width, metrics.panelWidth),
    ];
    // Only the windows that stand on the grid take a cell: one placed at a tap
    // sits where it was asked for. The row's capacity is measured for the
    // panel's own windows, so a tap-placed one taking a cell would push the last
    // of them out of the row that was counted for them.
    final onGrid = [
      for (final (index, entry) in entries.indexed)
        if (entry.floating?.origin == null) index,
    ];
    final slots = arrangeWindows(
      demands: [
        for (final index in onGrid)
          WindowDemand(
            width: widths[index],
            minHeight: entries[index].model.minHeight,
            maxHeight: entries[index].model.maxHeight,
          ),
      ],
      bounds: metrics.bounds,
      rtl: _rtl,
    );
    final slotOf = {
      for (final (slot, index) in onGrid.indexed) index: slots[slot],
    };
    final rtl = _rtl;
    for (final (index, entry) in entries.indexed) {
      final cell = slotOf[index];
      // A window placed at a tap keeps the room under it; one placed on the grid
      // is capped to its cell, so it can never cover the window below.
      _cells[entry.key] = cell?.height ?? metrics.maxHeight;
      _places.putIfAbsent(entry.key, () {
        final origin = _originIn(entry.floating?.origin);
        final place = ValueNotifier<WindowPlacement>(_placementAt(
          origin: origin,
          width: widths[index],
          bounds: metrics.bounds,
          rtl: rtl,
          cell: cell,
          height: _heights[entry.key],
        ));
        if (entry.floating?.origin != null) {
          // The frame this area is drawn in may not have been laid out yet, in
          // which case the place was worked out from a guess: it is worked out
          // again as soon as the frame is known.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final resolved = _originIn(entry.floating?.origin);
            if (resolved == null || resolved == origin) return;
            place.value = _placementAt(
              origin: resolved,
              width: widths[index],
              bounds: metrics.bounds,
              rtl: rtl,
              cell: cell,
              height: _heights[entry.key],
            );
          });
        }
        return place;
      });
    }

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final key in _stack)
            if (_places[key] case final place?)
              _positioned(_entryFor(key), place, metrics),
        ],
      ),
    );
  }

  _WindowEntry _entryFor(String key) =>
      _closing[key] ?? _live.firstWhere((entry) => entry.key == key);

  /// One window at its place, rebuilt on its own when it is dragged: the card is
  /// passed through unchanged, so moving a window never rebuilds the editor in
  /// it.
  Widget _positioned(
    _WindowEntry entry,
    ValueNotifier<WindowPlacement> place,
    _AreaMetrics metrics,
  ) {
    final width = entry.widthIn(metrics.bounds.width, metrics.panelWidth);
    // A window a tap placed is laid out once with the whole screen to grow in, so
    // the height it asks for can be read and it can be lifted by it. Until then
    // it is drawn at nothing: its first frame is only there to be measured, and a
    // window shown where it does not fit would be the forced scroll this exists
    // to avoid.
    final measuring =
        entry.floating?.origin != null && !_fitted.contains(entry.key);
    return ValueListenableBuilder<WindowPlacement>(
      key: ValueKey('place-${entry.key}'),
      valueListenable: place,
      child: _entrance(
        entry,
        AlignmentDirectional.topEnd,
        draggable: true,
      ),
      builder: (context, value, child) {
        final at = metrics.bounds.clamp(value, width: width);
        return Positioned(
          left: at.left,
          top: at.top,
          width: width,
          child: ConstrainedBox(
            // A window is as tall as its content, up to its cell, up to the
            // screen, and up to the room left under its own top: without a
            // ceiling a body that fills the space it is given — an order list
            // with an `Expanded` child — would be asked to fill infinity, a
            // window opened low on the screen would hang off the bottom of it,
            // and one in a grid row would cover the window under it.
            //
            // While it is measured the room under its top is not yet a limit: the
            // measurement is what decides where that top goes.
            constraints: BoxConstraints(
              maxHeight: math.max(
                0,
                math.min(
                  math.min(metrics.maxHeight, entry.model.maxHeight),
                  measuring
                      ? metrics.bounds.height
                      : math.min(
                          _cells[entry.key] ?? metrics.maxHeight,
                          metrics.bounds.bottom - at.top,
                        ),
                ),
              ),
            ),
            // The frame around every window is the same whether or not it is
            // being measured: swapping it out would rebuild the editor inside,
            // and the window it drew first would be a second one.
            child: _Measured(
              onSize: measuring
                  ? (size) => _placeByItsHeight(entry, place, size)
                  : null,
              child: Opacity(opacity: measuring ? 0 : 1, child: child!),
            ),
          ),
        );
      },
    );
  }

  /// Puts a window a tap opened in its place now that its own height is known:
  /// lifted just far enough for the whole of it to sit above the bottom edge, so
  /// a window asked for by a row near the foot of the screen opens whole rather
  /// than scrolled to its title.
  void _placeByItsHeight(
    _WindowEntry entry,
    ValueNotifier<WindowPlacement> place,
    Size size,
  ) {
    // Nothing was laid out: there is no height to place by, and the window has
    // nothing on it to show yet either. It is measured again next time.
    if (!mounted || size.height <= 0) return;
    final metrics = _metrics;
    _rebuild(() {
      _fitted.add(entry.key);
      _heights[entry.key] = size.height;
    });
    place.value = _placementAt(
      origin: _originIn(entry.floating?.origin),
      width: entry.widthIn(metrics.bounds.width, metrics.panelWidth),
      bounds: metrics.bounds,
      rtl: _rtl,
      cell: null,
      height: size.height,
    );
  }

  /// Where a window goes: at the tap that asked for it, or in its place on the
  /// grid when it was not opened at one.
  WindowPlacement _placementAt({
    required Offset? origin,
    required double width,
    required WindowBounds bounds,
    required bool rtl,
    required WindowSlot? cell,
    double? height,
  }) {
    if (origin == null) {
      return cell?.placement ??
          placementAt(
            origin: Offset(bounds.left, bounds.top),
            width: width,
            bounds: bounds,
            rtl: rtl,
          );
    }
    return placementAt(
      origin: origin,
      width: width,
      bounds: bounds,
      rtl: rtl,
      height: height,
    );
  }

  /// Brings a window in front of the others — what grabbing its header, or
  /// touching it anywhere, means.
  void _raise(String key) {
    if (_stack.isEmpty || _stack.last == key) return;
    _rebuild(() {
      // The user's own choice wins over the window the app last asked for.
      _focusKey = null;
      _stack
        ..remove(key)
        ..add(key);
    });
  }

  /// Moves a window by [delta], the way the pointer moved, and keeps it in
  /// reach: a window cannot be dragged off the screen.
  void _dragBy(String key, Offset delta) {
    final place = _places[key];
    final entry = _closing[key] ??
        _live.where((candidate) => candidate.key == key).firstOrNull;
    if (place == null || entry == null) return;
    final metrics = _metrics;
    final width = entry.widthIn(metrics.bounds.width, metrics.panelWidth);
    final bounds = metrics.bounds;
    place.value = bounds.clamp(
      bounds.clamp(place.value, width: width).moved(
            dx: delta.dx,
            dy: delta.dy,
          ),
      width: width,
    );
  }

  /// A phone has no room beside the panel, so a window comes over it as a sheet
  /// that slides down from the top edge, as tall as its content — the footer
  /// stays at the foot of the window rather than the foot of the screen.
  Widget _buildSheet(_WindowEntry entry) {
    final viewPadding = MediaQuery.paddingOf(context);
    final room = _room;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_dismiss(entry)),
          child: ColoredBox(
            color: FluentTheme.of(context).resources.smokeFillColorDefault,
          ),
        ),
        PositionedDirectional(
          start: 8,
          end: 8,
          top: viewPadding.top + kWindowEdgeInset + _commandHeight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(room * 0.88, entry.model.maxHeight),
            ),
            child: _entrance(entry, AlignmentDirectional.topCenter),
          ),
        ),
      ],
    );
  }

  /// Closing the sheet closes the window: a standalone one asks its owner, a
  /// panel's goes back to the dock.
  ///
  /// A standalone window with unsaved work asks first — the same question its
  /// own Close asks — because a tap beside the sheet is not consent to lose it.
  Future<void> _dismiss(_WindowEntry entry) async {
    final floating = entry.floating;
    if (floating == null) {
      _workspace?.minimize(entry.id, slot: entry.group?.slot ?? kHostSlot);
      return;
    }
    if (floating.hasChanges?.call() ?? false) {
      if (!await confirmDiscardFloatingWindow(context)) return;
      if (!mounted) return;
    }
    (floating.onClose ?? () => WindowsManager.close(floating)).call();
  }

  Widget _entrance(
    _WindowEntry entry,
    AlignmentGeometry from, {
    bool draggable = false,
  }) {
    final leaving = _closing.containsKey(entry.key);
    final active = !leaving &&
        (!draggable ||
            _stack.lastWhere(
                  (key) => !_closing.containsKey(key),
                  orElse: () => '',
                ) ==
                entry.key);
    final floating = entry.floating;
    return _WindowEntrance(
      key: ValueKey('entrance-${entry.key}'),
      leaving: leaving,
      onLeft: () => _forget(entry.key),
      from: from,
      animateEntrance: !_replacements.contains(entry.key),
      child: floating != null
          ? StandaloneWindowCard(
              key: ValueKey('window-card-${entry.key}'),
              floating: floating,
              active: active,
              compact: widget.screenWidth < kWindowsBreakpoint,
              accent: PanelAccents.ofScope(floating.scope),
              onRaise: draggable ? () => _raise(entry.key) : null,
              onDragUpdate: draggable ? (d) => _dragBy(entry.key, d) : null,
            )
          : StreamBuilder<bool>(
              // The session's own verdict on unsaved work, live: a window of that
              // record says so beside its title, exactly as its dock pill does —
              // and the session is the record's owner, whatever group it is in.
              stream: entry.session!.hasUnsavedChanges.stream,
              builder: (context, _) {
                final session = entry.session!;
                return PanelWindowCard(
                  key: ValueKey('window-card-${entry.id}'),
                  window: entry.window!,
                  active: active,
                  accent: entry.group?.accent,
                  badge: entry.group?.glyph,
                  dirty: session.hasUnsavedChanges(),
                  // The window saves **its own record**: the session's write, never
                  // the panel's. A visit's window that saved the patient would be
                  // the one bug this whole design deletes (plan §6.2-6).
                  onSave: _savesRecord(entry) ? session.save : null,
                  onMinimize: () => _workspace?.minimize(entry.id,
                      slot: entry.group?.slot ?? kHostSlot),
                  onRaise: draggable ? () => _raise(entry.key) : null,
                  onDragUpdate: draggable ? (d) => _dragBy(entry.key, d) : null,
                  attachments: _attachmentsOf(entry, session),
                );
              },
            ),
    );
  }

  /// The editors this window carries, as a tray on its own frame.
  ///
  /// The window that owns an attachment draws its chips, so the control sits
  /// where the thing it is about sits — never in a second dock somewhere else.
  /// A visit's labwork and photos are not among them: they hang off the band (and
  /// the visit's post-op card), which outlives the chart in the row.
  Widget? _attachmentsOf(_WindowEntry entry, WindowRecordSession session) {
    final group = entry.group;
    if (group == null) return null;
    final windows = <PanelWindow>[
      for (final window in group.windows)
        if (window.attachedTo == entry.model.id) window,
    ];
    if (windows.isEmpty) return null;
    return WindowAttachments(
      windows: windows,
      accent: group.accent,
      keyForWindow: (window) =>
          WK.attachmentToggle(window.id, owner: entry.model.id),
      isOpen: (window) =>
          _workspace?.isOpen(window.id, slot: group.slot) ?? false,
      enabled: (window) => !(window.onlyIfSaved && session.isNew),
      onToggle: (window) => _workspace?.toggle(window.id, slot: group.slot),
    );
  }

  /// Whether [entry]'s window gets a Save in its own footer.
  bool _savesRecord(_WindowEntry entry) =>
      entry.model.editsRecord && (entry.session?.showBottomControls ?? false);
}

/// Tells [onSize] the size its child was laid out at, once the frame that laid it
/// out is over.
///
/// A window a tap opened is laid out with the whole screen to grow in, so the
/// height it asks for is known before it is drawn: the layer lifts it by that
/// height, and it cannot lift it by a height it is still guessing at.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onSize, required super.child});

  /// Null once the window's size is no longer wanted.
  final ValueChanged<Size>? onSize;

  @override
  _RenderMeasured createRenderObject(BuildContext context) =>
      _RenderMeasured(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) =>
      renderObject.onSize = onSize;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onSize);

  ValueChanged<Size>? onSize;

  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    final onSize = this.onSize;
    if (onSize == null || measured == _reported) return;
    _reported = measured;
    // A size is read during layout, where the window's place may not change: it
    // is a notifier, and setting it now would rebuild the tree being laid out.
    SchedulerBinding.instance.addPostFrameCallback((_) => onSize(measured));
  }
}
