part of 'windows_layer.dart';

extension _WindowsAreaBuilding on _WindowsAreaState {
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  /// Brings a window origin from app coordinates (menus sit in the overlay)
  /// into this area's; during the first build the result can be a guess.
  Offset? _originIn(Offset? origin) {
    if (origin == null) return null;
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize || !object.attached) {
      return origin;
    }
    return object.globalToLocal(origin);
  }

  Widget _buildStack() {
    final metrics = _metrics;
    final entries = [..._live, ..._closing.values];
    final keys = {for (final entry in entries) entry.key};
    _stack.removeWhere((key) => !keys.contains(key));
    for (final entry in entries) {
      if (!_stack.contains(entry.key)) _stack.add(entry.key);
    }
    // The window the app last asked for stays on top while it is on screen,
    // including the frames in which the rest of its row arrives.
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
    // A closed window drops its measured height: reopened elsewhere, it
    // must be measured again.
    _heights.removeWhere((key, _) => !keys.contains(key));
    _fitted.removeWhere((key) => !keys.contains(key));

    // Every entry needs a place, one already folding away included: without one
    // it has nothing to animate out of and never finishes leaving.
    final widths = [
      for (final entry in entries)
        entry.widthIn(metrics.bounds.width, metrics.panelWidth),
    ];
    // Only grid windows take a slot: the row's capacity is measured for the
    // panel's own windows, so a tap-placed one taking a cell would overflow it.
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
      // Grid windows are capped to their cell so they never cover one below;
      // a tap-placed window keeps the room under it.
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
          // Origin may have been a guess before layout; re-resolve it now.
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

  /// One window at its place. The card is passed to the builder as `child`, so
  /// dragging rebuilds the position, not the editor inside.
  Widget _positioned(
    _WindowEntry entry,
    ValueNotifier<WindowPlacement> place,
    _AreaMetrics metrics,
  ) {
    final width = entry.widthIn(metrics.bounds.width, metrics.panelWidth);
    // A tap-placed window is laid out once at full height before it is shown:
    // its first frame only exists to be measured, so it is drawn at opacity 0.
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
            // Capped by its cell, screen and room below its top: without it
            // a filling body gets infinity, a low window hangs off the bottom;
            // while measuring, the room below the top is not a limit.
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
            // The measuring wrapper stays even with nothing to report:
            // swapping it out would rebuild the editor and lose its state.
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

  /// Lifts a tap-opened window just enough to sit above the bottom edge once
  /// its height is known, so it opens whole instead of scrolled to its title.
  void _placeByItsHeight(
    _WindowEntry entry,
    ValueNotifier<WindowPlacement> place,
    Size size,
  ) {
    // Zero height means nothing was laid out; it is measured again next time.
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

  Widget _buildSheet(_WindowEntry entry) {
    final media = MediaQuery.of(context);
    final top = _safeArea(media).top + kWindowEdgeInset + _commandHeight;
    // The keyboard takes away the sheet's lower room: cap the card to what is
    // left above it, so its editor scrolls to the field under the keys instead
    // of hiding it behind them.
    final room = math.min(
      _room,
      math.max(0.0, media.size.height - media.viewInsets.bottom - top),
    );
    // At rest the sheet keeps a peek of the page behind it: tapping beside it
    // is the way out. With the keys up that peek is dead space over the one
    // editor the user is working in, so the sheet takes the whole room left
    // above them — and the window's own height ceiling no longer holds it short.
    final keyboardUp = media.viewInsets.bottom > 0;
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
          top: top,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: keyboardUp
                  ? room
                  : math.min(room * 0.88, entry.model.maxHeight),
            ),
            child: _entrance(entry, AlignmentDirectional.topCenter),
          ),
        ),
      ],
    );
  }

  /// Closing the sheet closes its window. A standalone window with unsaved work
  /// asks first: a tap beside the sheet is not consent to lose it.
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
              // Dirty state comes from the session, the record's owner, so the
              // window matches its dock pill whatever group it is in.
              stream: entry.session!.hasUnsavedChanges.stream,
              builder: (context, _) {
                final session = entry.session!;
                return PanelWindowCard(
                  key: ValueKey('window-card-${entry.id}'),
                  window: entry.window!,
                  active: active,
                  accent: entry.group?.accent,
                  dirty: session.hasUnsavedChanges(),
                  // Saves the session's own record, never the panel's: a visit
                  // window must not write the patient.
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

  /// The tray of editors this window carries. A visit's labwork and photos hang
  /// off its band instead of this tray.
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

/// Reports its child's laid-out size after the frame. A tap-opened window must
/// be lifted by a height known before it is drawn, not one still being guessed.
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
    // The place is a notifier: setting it during layout would rebuild the tree
    // being laid out.
    SchedulerBinding.instance.addPostFrameCallback((_) => onSize(measured));
  }
}
