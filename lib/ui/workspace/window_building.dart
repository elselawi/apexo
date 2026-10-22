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
    _places.removeWhere((key, place) {
      if (keys.contains(key)) return false;
      place.dispose();
      return true;
    });
    _cells.removeWhere((key, _) => !keys.contains(key));

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
            constraints: BoxConstraints(
              maxHeight: math.max(
                0,
                math.min(
                  math.min(
                    math.min(metrics.maxHeight, entry.model.maxHeight),
                    _cells[entry.key] ?? metrics.maxHeight,
                  ),
                  metrics.bounds.bottom - at.top,
                ),
              ),
            ),
            child: child,
          ),
        );
      },
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
    );
  }

  /// Brings a window in front of the others — what grabbing its header, or
  /// touching it anywhere, means.
  void _raise(String key) {
    if (_stack.isEmpty || _stack.last == key) return;
    _rebuild(() {
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
    final room = MediaQuery.sizeOf(context).height -
        viewPadding.top -
        viewPadding.bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_dismiss(entry)),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.36)),
        ),
        PositionedDirectional(
          start: 8,
          end: 8,
          top: viewPadding.top + 8,
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
      _workspace?.minimize(entry.id);
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
    final floating = entry.floating;
    return _WindowEntrance(
      key: ValueKey('entrance-${entry.key}'),
      leaving: leaving,
      onLeft: () => _forget(entry.key),
      from: from,
      child: floating != null
          ? StandaloneWindowCard(
              key: ValueKey('window-card-${entry.key}'),
              floating: floating,
              compact: widget.screenWidth < kWindowsBreakpoint,
              accent: PanelAccents.ofScope(floating.scope),
              onRaise: draggable ? () => _raise(entry.key) : null,
              onDragUpdate: draggable ? (d) => _dragBy(entry.key, d) : null,
            )
          : StreamBuilder<bool>(
              // The panel's own verdict on unsaved work, live: a window of that
              // record says so beside its title, exactly as its dock pill does.
              stream: widget.panel!.hasUnsavedChanges.stream,
              builder: (context, _) => PanelWindowCard(
                key: ValueKey('window-card-${entry.id}'),
                window: entry.window!,
                accent: widget.panel?.accent,
                dirty: widget.panel!.hasUnsavedChanges(),
                // A window that edits the record saves the record, with the
                // panel's own write — so the window's Save and the panel's can
                // never disagree about what "saving" means.
                onSave: _savesRecord(entry.window!) ? widget.panel!.save : null,
                onMinimize: () => _workspace?.minimize(entry.id),
                onRaise: draggable ? () => _raise(entry.key) : null,
                onDragUpdate: draggable ? (d) => _dragBy(entry.key, d) : null,
              ),
            ),
    );
  }

  /// Whether [window] gets the panel's Save in its own footer.
  bool _savesRecord(PanelWindow window) =>
      window.editsRecord && (widget.panel?.showBottomControls ?? false);
}
