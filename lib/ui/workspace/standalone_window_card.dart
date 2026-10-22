import 'dart:async';

import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/window_actions.dart';
import 'package:apexo/ui/workspace/window_close_button.dart';
import 'package:apexo/ui/workspace/window_shell.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A window standing on its own: no panel behind it, so it carries the Save and
/// Close a panel would have offered — Close in the header, where a panel's
/// window has its minimize, and both in the footer.
///
/// A window that writes nothing — a list, a scan, a photo — carries Close alone.
class StandaloneWindowCard extends StatefulWidget {
  const StandaloneWindowCard({
    super.key,
    required this.floating,
    required this.compact,
    this.accent,
    this.onRaise,
    this.onDragUpdate,
  });

  final FloatingWindow floating;

  /// Whether the window is a phone sheet, which is drawn with the frame's close.
  final bool compact;

  /// The colour the record's kind is known by, from the window's scope.
  final Color? accent;

  /// Touching the window brings it in front of the others.
  final VoidCallback? onRaise;

  /// Dragging the window by its header.
  final ValueChanged<Offset>? onDragUpdate;

  @override
  State<StandaloneWindowCard> createState() => _StandaloneWindowCardState();
}

class _StandaloneWindowCardState extends State<StandaloneWindowCard> {
  /// A draft is edited in place, and only its owner can say whether it differs
  /// from what was stored: sample it, and redraw when it flips. Sampled once
  /// here, so the header's Close and the footer's ask with the same answer.
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

  /// Leaves the window for the panel that holds its record: the panel opens on
  /// the window the user was already looking at, and takes the window's work
  /// with it — the panel carries it, starts dirty on it, and its own Save is
  /// the one write.
  ///
  /// So the window is **not** closed here: closing it first would throw the
  /// work away before the panel had a chance to take it, and the panel would
  /// then show work it never stored while reporting nothing to save. The
  /// panel's own opener closes the window once it has adopted what it held.
  Future<void> _openRecord() async {
    if (_opening) return;
    _opening = true;
    try {
      final floating = widget.floating;
      final openRecord = floating.onOpenRecord;
      if (openRecord == null) return;
      // A window that cannot hand its work over would lose it: then the
      // question has to be asked before the record takes the window's place.
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
      dirty: _dirty,
      onRaise: widget.onRaise,
      onDragUpdate: widget.onDragUpdate,
      actions: [
        if (widget.floating.onOpenRecord != null)
          Button(
            key: WK.windowOpenRecord,
            onPressed: () => unawaited(_openRecord()),
            style: greyButtonStyle.copyWith(
              padding: const WidgetStatePropertyAll(
                EdgeInsetsDirectional.fromSTEB(8, 2, 10, 2),
              ),
              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            child: ButtonContent(
              FluentIcons.open_in_new_tab,
              txt('openRecord'),
              size: 14,
              // "Open in" points somewhere: in a right-to-left app it points
              // the other way.
              flipInRtl: true,
            ),
          ),
        if (onClose != null)
          WindowCloseButton(
            key: WK.windowHeaderClose,
            dirty: _dirty,
            hasChanges: widget.floating.hasChanges,
            onClose: onClose,
            compact: true,
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
            ),
        ],
      ),
      padding: window.padding,
      scrollable: window.scrollable,
      child: window.body,
    );
  }
}
