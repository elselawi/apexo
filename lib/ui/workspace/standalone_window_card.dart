import 'dart:async';

import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/window_actions.dart';
import 'package:apexo/ui/workspace/window_close_button.dart';
import 'package:apexo/ui/workspace/window_shell.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A window with no panel behind it, so it carries the Save and Close a panel
/// would have offered.
class StandaloneWindowCard extends StatefulWidget {
  const StandaloneWindowCard({
    super.key,
    required this.floating,
    required this.compact,
    this.accent,
    this.active = true,
    this.onRaise,
    this.onDragUpdate,
  });

  final FloatingWindow floating;

  /// Whether the window is a phone sheet, which is drawn with the frame's close.
  final bool compact;

  /// The colour the record's kind is known by, from the window's scope.
  final Color? accent;

  /// Whether this window is in front of the other floating windows.
  final bool active;

  /// Touching the window brings it in front of the others.
  final VoidCallback? onRaise;

  /// Dragging the window by its header.
  final ValueChanged<Offset>? onDragUpdate;

  @override
  State<StandaloneWindowCard> createState() => _StandaloneWindowCardState();
}

class _StandaloneWindowCardState extends State<StandaloneWindowCard> {
  // A draft is edited in place, so only its owner can say it is dirty: poll it
  // and redraw when it flips.
  static const Duration _sampleEvery = Duration(milliseconds: 600);

  Timer? _sampler;
  bool _dirty = false;
  bool _opening = false;

  bool get _dirtyNow =>
      widget.floating.canSave && (widget.floating.hasChanges?.call() ?? false);

  @override
  void initState() {
    super.initState();
    _dirty = _dirtyNow;
    _startSampling();
  }

  @override
  void didUpdateWidget(covariant StandaloneWindowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The same window can be asked for again with a new draft behind it.
    if (oldWidget.floating != widget.floating) {
      _dirty = _dirtyNow;
      _startSampling();
    }
  }

  @override
  void dispose() {
    _sampler?.cancel();
    super.dispose();
  }

  void _startSampling() {
    _sampler?.cancel();
    if (!widget.floating.canSave || widget.floating.hasChanges == null) return;
    _sampler = Timer.periodic(_sampleEvery, (_) => _resample());
  }

  /// Re-reads whether the draft is dirty — after a save, and on every sample.
  void _resample() {
    final dirty = _dirtyNow;
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  // The panel opens on this window, adopts its draft and its own opener closes
  // it: closing here would discard the work before the panel could take it.
  Future<void> _openRecord() async {
    if (_opening) return;
    _opening = true;
    try {
      final floating = widget.floating;
      final openRecord = floating.onOpenRecord;
      if (openRecord == null) return;
      // A window that cannot hand its work over would lose it when the record
      // takes its place, so ask before opening.
      if (_dirtyNow && !floating.canAdopt) {
        if (!await confirmDiscardFloatingWindow(context)) return;
        if (!mounted) return;
        floating.onClose?.call();
      }
      await openRecord();
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.floating.window;
    final onClose = widget.floating.onClose;
    return WindowShell(
      icon: window.icon,
      title: window.title,
      subtitle: window.subtitle?.call(),
      accent: widget.accent,
      active: widget.active,
      dirty: _dirty,
      onRaise: widget.onRaise,
      onClose: onClose,
      closeDirty: _dirty,
      closeHasChanges: widget.floating.hasChanges,
      closeButtonKey: WK.windowHeaderClose,
      onDragUpdate: widget.onDragUpdate,
      actions: [
        if (widget.floating.onOpenRecord != null)
          Button(
            key: WK.windowOpenRecord,
            onPressed: () => unawaited(_openRecord()),
            child: ButtonContent(
              FluentIcons.open_in_new_tab,
              txt(widget.floating.openRecordLabel),
              // "Open in" points sideways, so mirror it in right-to-left.
              flipInRtl: true,
            ),
          ),
      ],
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (window.footer != null) window.footer!,
          if (onClose != null)
            WindowActions(
              savable: widget.floating.canSave,
              dirty: _dirty,
              hasChanges: widget.floating.hasChanges,
              onSave: widget.floating.onSave ?? () async {},
              onSaved: _resample,
              onClose: onClose,
              extraActions: window.footerActions,
            ),
        ],
      ),
      padding: window.padding,
      scrollable: window.scrollable,
      child: window.body,
    );
  }
}
