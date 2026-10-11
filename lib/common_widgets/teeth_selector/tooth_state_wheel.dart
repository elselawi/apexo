import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/live_transcription_button.dart';
import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'dart:async';
import 'dart:math' as math;

class ToothStateWheel extends StatefulWidget {
  const ToothStateWheel({
    super.key,
    required this.initialValue,
    required this.iso,
    required this.toothName,
    required this.onSet,
    required this.onTapClose,
    required this.oldNote,
    required this.type,
    this.extraNote = '',
    this.onExtraNote,
    this.history = const [],
    this.historyTitle = 'toothHistory',
  });
  final String toothName;
  final String iso;
  final String? initialValue;
  final ValueChanged<String?> onSet;
  final VoidCallback onTapClose;
  final String? oldNote;
  final StateType type;
  final String extraNote;
  final ValueChanged<String>? onExtraNote;
  final List<ToothHistory> history;

  /// Localization key naming what [history] holds — the patient's baseline and
  /// earlier appointments for the treatment being recorded, or the notes
  /// earlier appointments left on this tooth when it is browsed from the
  /// patient's own records.
  final String historyTitle;

  @override
  State<ToothStateWheel> createState() => _ToothStateWheelState();
}

class _ToothStateWheelState extends State<ToothStateWheel> {
  /// Shared geometry of the wheel and its folded view, and the length of the
  /// animation that travels between them.
  static const _morph = Duration(milliseconds: 350);

  /// The folded corners of the surface; while the ring is open the same box is
  /// rounded by half its width, which is what draws the circle.
  static const _cornerRadius = 16.0;

  /// The chosen option's box, matching the option circles on the ring.
  static const _chip = _optionSize;
  static const _chipTop = 12.0;

  /// The folded view hangs its controls on the surface's edges: the chosen
  /// option on the leading edge and dictation on the trailing one, with the
  /// notes field between them and the save/clear pair along the bottom.
  static const _edgeMargin = 14.0;
  static const _notesTop = 80.0;
  static const _rowHeight = 34.0;
  static const _rowGap = 10.0;
  static const _bottomMargin = 12.0;

  /// Width reserved for the dictation button, which grows as it records.
  static const _dictationRow = 72.0;

  /// How far the chosen option reaches past its own box once it has grown.
  static const _chipGrow = _chip * (_chosenScale - 1) / 2;

  String? _selectedLabel;
  bool _isOtherMode = false;
  bool _hasNote = false;

  /// Whether the ring of options is open. Recording a choice folds it away so
  /// the chosen option can ride on top of the notes field; clearing the tooth
  /// is what brings the ring back.
  late bool _optionsExpanded;
  late final TextEditingController _notesController;
  final TextEditingController _otherController = TextEditingController();

  final treatments = txOptions.where((x) => x.type != StateType.state).toList();
  final states = txOptions.where((x) => x.type != StateType.treatment).toList();

  List<TxOption> get options {
    return widget.type == StateType.state ? states : treatments;
  }

  @override
  void initState() {
    super.initState();
    _selectedLabel = widget.initialValue;
    _optionsExpanded = _selectedLabel == null || _selectedLabel!.isEmpty;
    _hasNote = widget.extraNote.isNotEmpty;
    _notesController = TextEditingController(text: widget.extraNote);

    if (txOptions.where((x) => x.label == _selectedLabel).isEmpty &&
        _selectedLabel != null &&
        _selectedLabel != "") {
      _isOtherMode = true;
      _otherController.text = _selectedLabel ?? "";
    }
  }

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    _notesController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  void _select(String? label) {
    setState(() {
      _selectedLabel = label;
      _isOtherMode = false;
      // Clearing the tooth leaves the ring open; choosing folds it away.
      _optionsExpanded = label == null || label.isEmpty;
    });
    widget.onSet(label);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final records = widget.history
        .where((record) =>
            record.teeth.containsKey(widget.iso) ||
            record.notes[widget.iso]?.isNotEmpty == true)
        .toList()
      ..sort((a, b) =>
          (b.date ?? DateTime(9999)).compareTo(a.date ?? DateTime(9999)));

    // Tapping anywhere that is not one of the floating surfaces (the wheel,
    // the notes field, the header or the history card) dismisses the whole
    // popup. The surfaces each absorb their own taps below, and none of the
    // absorbing handlers touch semantics — the labelled controls inside them
    // keep the accessibility tree exactly as it was.
    return GestureDetector(
      onTap: widget.onTapClose,
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(media.size.width - 24, 760),
          maxHeight:
              math.max(160, media.size.height - media.viewInsets.bottom - 32),
        ),
        child: SingleChildScrollView(
          clipBehavior: Clip.none,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _headerPill(context),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final wheel = _wheel(context);
                  final hasHistory =
                      records.isNotEmpty || widget.oldNote != null;
                  final historySurface = hasHistory
                      ? _historySurface(context, records: records)
                      : null;

                  if (hasHistory) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(fit: BoxFit.scaleDown, child: wheel),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: math.min(availableWidth, 350.0),
                          child: historySurface!,
                        ),
                      ],
                    );
                  }

                  return Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: wheel),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerPill(BuildContext context) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: theme.menuColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.inactiveColor.withAlpha(darkMode ? 60 : 35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: darkMode ? 0.35 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DentalNotation(iso: widget.iso, withTooltip: false),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                widget.toothName,
                style: theme.typography.bodyStrong?.copyWith(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: txt('close'),
              child: IconButton(
                key: const ValueKey('wheel-close'),
                onPressed: widget.onTapClose,
                style: filledButtonStyle(Colors.red),
                icon: const Icon(WindowsIcons.chrome_close, size: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wheel(BuildContext context) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    const size = 350.0;
    final collapsed = !_optionsExpanded;
    final accent = _accentColor;
    final hasChoice = _hasChoice;

    // The surface's shape is the wheel's own: the gaps around it belong to the
    // popup, whose dismiss handler is waiting behind them.
    return AnimatedContainer(
      key: const ValueKey('choice-wheel'),
      duration: _morph,
      curve: Curves.easeInOutCubic,
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: theme.menuColor,
        // The round wheel and the notes rectangle are the same square box:
        // only the corner radius travels between them, so the morph keeps
        // the overall width the ring was built around.
        borderRadius:
            BorderRadius.circular(collapsed ? _cornerRadius : size / 2),
        border: Border.all(
          color: hasChoice
              ? accent.withValues(alpha: darkMode ? 0.6 : 0.4)
              : theme.inactiveColor.withAlpha(darkMode ? 60 : 40),
          width: hasChoice ? 2.0 : 1.0,
        ),
        boxShadow: [
          if (hasChoice)
            BoxShadow(
              color: accent.withValues(alpha: darkMode ? 0.20 : 0.10),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: darkMode ? 0.35 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // The clip keeps hit testing on the paint: the surface takes every tap
      // that lands on it — the gaps between the ring's options included —
      // while the corners of the box it is drawn in stay the dismiss
      // handler's, so the popup still closes when they are tapped.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
            begin: size / 2, end: collapsed ? _cornerRadius : size / 2),
        duration: _morph,
        curve: Curves.easeInOutCubic,
        builder: (context, radius, child) => ClipRRect(
          clipper: _SurfaceClipper(radius),
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            child: child,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The surface's own border insets this box, so the ring and the
            // notes surface are laid out against the box they actually get.
            final box = constraints.maxWidth;
            return Stack(
              alignment: Alignment.center,
              children: [
                _notesSurface(context, collapsed: collapsed, box: box),
                _dictationButton(collapsed: collapsed, box: box),
                for (var index = 0; index < options.length; index++)
                  _optionButton(index, collapsed: collapsed, box: box),
                _foldedActions(collapsed: collapsed, box: box),
              ],
            );
          },
        ),
      ),
    );
  }

  bool get _hasChoice =>
      _isOtherMode || (_selectedLabel != null && _selectedLabel!.isNotEmpty);

  Color get _accentColor =>
      _isOtherMode ? Colors.teal : labelToColor(_selectedLabel ?? '');

  /// One option on the ring.
  ///
  /// Recording a choice folds the ring away: every option but the chosen one
  /// shrinks out of sight and stops taking taps, while the chosen one rides to
  /// the leading edge of the surface and stays there for good.
  Widget _optionButton(int index,
      {required bool collapsed, required double box}) {
    const ringRadius = 147.0;
    final option = options[index];
    final isSelected =
        _isOtherMode ? option.label == 'other' : _selectedLabel == option.label;
    final hidden = collapsed && !isSelected;
    final angle = index * 2 * math.pi / options.length - math.pi / 2;
    final atTop = isSelected && collapsed;
    // Kept clear of the edge by its grown size, so its painted edge lines up
    // with the notes field below rather than its box.
    const lead = _edgeMargin + _chipGrow;

    return AnimatedPositioned(
      duration: _morph,
      curve: Curves.easeInOutCubic,
      left: atTop
          ? (locale.isRtl ? box - lead - _chip : lead)
          : box / 2 + ringRadius * math.cos(angle) - _chip / 2,
      top:
          atTop ? _chipTop : box / 2 + ringRadius * math.sin(angle) - _chip / 2,
      child: IgnorePointer(
        ignoring: hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: _RadialButton(
            state: option,
            isSelected: isSelected,
            isHidden: hidden,
            onTap: () => _choose(option.label),
          ),
        ),
      ),
    );
  }

  /// Records [label] on the tooth, or opens the custom editor for `other`.
  ///
  /// A second tap on the same option within [doubleTapWindow] confirms the
  /// choice by closing the popup — "set it and get out", without waiting for
  /// extra notes to be typed. Once a choice is recorded the ring stays folded;
  /// the clear control is the way back to it.
  static const doubleTapWindow = Duration(milliseconds: 350);
  Timer? _doubleTapTimer;
  String? _pendingTapLabel;

  void _choose(String label) {
    if (_pendingTapLabel == label) {
      // Second tap on the same option: the choice is already recorded, so
      // there is nothing left to edit — close the whole popup.
      _doubleTapTimer?.cancel();
      _pendingTapLabel = null;
      widget.onTapClose();
      return;
    }

    _doubleTapTimer?.cancel();
    _pendingTapLabel = label;
    _doubleTapTimer = Timer(doubleTapWindow, () {
      _pendingTapLabel = null;
    });

    if (label == 'other') {
      if (_isOtherMode) return;
      setState(() {
        _isOtherMode = true;
        _optionsExpanded = false;
        _otherController.text = txOptions.any((o) => o.label == _selectedLabel)
            ? ''
            : _selectedLabel ?? '';
      });
      return;
    }

    if (!_isOtherMode && label == _selectedLabel) {
      // Already recorded: a recorded treatment keeps this folded view, and
      // clearing it is the way back to the ring.
      return;
    }

    _select(label);
  }

  /// The notes surface at the heart of the wheel.
  ///
  /// While the ring is open it is the familiar circle; recording a choice
  /// widens it into a rounded rectangle tucked under the chosen option so a
  /// full note fits comfortably. It carries the option's own colour rather
  /// than a grey field box, and stays out of the way until there is something
  /// to attach a note to — a chosen option, the custom "other" editor, or
  /// notes carried in from a saved record.
  Widget _notesSurface(BuildContext context,
      {required bool collapsed, required double box}) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    const circle = 196.0;
    final showField = _hasChoice || _hasNote;
    final accent = _accentColor;

    return AnimatedPositioned(
      duration: _morph,
      curve: Curves.easeInOutCubic,
      left: collapsed ? _edgeMargin : (box - circle) / 2,
      top: collapsed ? _notesTop : (box - circle) / 2,
      width: collapsed ? box - 2 * _edgeMargin : circle,
      height: collapsed
          ? box - _notesTop - _rowGap - _rowHeight - _bottomMargin
          : circle,
      child: AnimatedContainer(
        key: const ValueKey('extra-notes-circle'),
        duration: _morph,
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(collapsed ? 14 : circle / 2),
          color: showField
              ? accent.withValues(alpha: darkMode ? 0.16 : 0.09)
              : Colors.transparent,
          border: Border.all(
            color: showField
                ? accent.withValues(alpha: darkMode ? 0.45 : 0.30)
                : theme.inactiveColor.withAlpha(darkMode ? 45 : 30),
            width: collapsed ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (showField)
              BoxShadow(
                color: Colors.black.withValues(alpha: darkMode ? 0.25 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: showField
              ? _WheelTextField(
                  key: ValueKey(_isOtherMode ? 'other-field' : 'notes'),
                  controller:
                      _isOtherMode ? _otherController : _notesController,
                  placeholder:
                      txt(_isOtherMode ? 'other' : 'extraInfoPlaceholder'),
                  autofocus: _isOtherMode,
                  // Folded, dictation lives beside the chosen option; while
                  // the ring is open it stays on the field, as before.
                  micPlacement:
                      collapsed ? MicPlacement.none : MicPlacement.bottomCenter,
                  onChanged: _isOtherMode ? _onOtherChanged : _onNotesChanged,
                )
              : _hubHint(context),
        ),
      ),
    );
  }

  /// The folded view's actions, along the bottom of the surface.
  ///
  /// Saving keeps the note — it was stored as it was typed — and closes the
  /// wheel; clearing takes the choice, the note and the custom label with it
  /// and puts the ring back. Save comes first, so in left-to-right it sits at
  /// the left of the pair and in right-to-left the whole row mirrors with it.
  Widget _foldedActions({required bool collapsed, required double box}) {
    final color = _accentColor;
    final visible = collapsed && _hasChoice;
    final top = box - _bottomMargin - _rowHeight;
    final save = FilledButton(
      key: const ValueKey('wheel-save'),
      style: filledButtonStyle(color),
      onPressed: widget.onTapClose,
      child: ButtonContent(WindowsIcons.check_mark, txt('save'), size: 14),
    );
    final clear = Button(
      key: const ValueKey('wheel-clear'),
      onPressed: _clear,
      child: ButtonContent(WindowsIcons.chrome_close, txt('clear'), size: 14),
    );

    return AnimatedPositioned(
      duration: _morph,
      curve: Curves.easeInOutCubic,
      left: 0,
      right: 0,
      // Rises into place as the ring folds away, instead of simply appearing.
      top: collapsed ? top : top + 14,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: locale.isRtl ? [clear, save] : [save, clear],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Dictation, at the trailing edge of the surface.
  ///
  /// It feeds whichever field is on the surface — the notes field, or the
  /// custom "other" editor — so folding the ring never takes the microphone
  /// away from what is being written.
  Widget _dictationButton({required bool collapsed, required double box}) {
    final available = transcriptionAvailable;
    final color = _accentColor;
    final rtl = locale.isRtl;

    return AnimatedPositioned(
      duration: _morph,
      curve: Curves.easeInOutCubic,
      left: rtl ? _edgeMargin : box - _edgeMargin - _dictationRow,
      top: _chipTop,
      // Built only when dictation is actually on offer: the button owns a
      // recorder, and there is no reason to hold one while it is unavailable.
      child: available
          ? _flank(
              visible: collapsed && _hasChoice,
              // Hugs the trailing edge, so the slot's spare width — the room
              // the button needs while it counts down — stays inwards, where
              // it cannot push the option around.
              alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
              // Wears the chosen option's colour, like the Save control below.
              // The key follows the field it dictates into: the button binds
              // its controller once, when it is built, so switching between
              // the notes field and the custom "other" editor has to give it
              // a new one to bind.
              child: LiveTranscriptionButton(
                key: ValueKey(
                    'wheel-dictation-${_isOtherMode ? 'other' : 'notes'}'),
                iconColor: color,
                textController:
                    _isOtherMode ? _otherController : _notesController,
                onDone: _isOtherMode ? _onOtherChanged : _onNotesChanged,
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  /// A slot at the trailing edge of the surface, faded in with the folded view.
  ///
  /// The slot is wider than the control it holds so the growing dictation
  /// button — the one that counts down while recording — keeps its place
  /// instead of pushing anything around.
  Widget _flank({
    required bool visible,
    required Alignment alignment,
    required Widget child,
  }) {
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: SizedBox(
            width: _dictationRow,
            height: _chip,
            child: Align(alignment: alignment, child: child),
          ),
        ),
      ),
    );
  }

  void _clear() {
    _notesController.clear();
    _hasNote = false;
    _otherController.clear();
    widget.onExtraNote?.call('');
    _select(null);
  }

  void _onNotesChanged(String text) {
    final hasNote = text.isNotEmpty;
    if (hasNote != _hasNote) {
      setState(() => _hasNote = hasNote);
    }
    widget.onExtraNote?.call(text);
  }

  /// The custom "other" option commits as it is typed — exactly like a note —
  /// so the tooth is never left with an unsaved custom label.
  void _onOtherChanged(String text) {
    final label = text.trim();
    setState(() => _selectedLabel = label.isEmpty ? null : label);
    widget.onSet(label.isEmpty ? null : label);
  }

  Widget _hubHint(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DentalNotation(
            iso: widget.iso,
            withTooltip: false,
            color: theme.accentColor,
          ),
          const SizedBox(height: 10),
          Txt(
            txt(widget.type == StateType.state
                ? 'tap the condition or history of the tooth to register it'
                : 'tap the treatment you have performed to register it to the tooth'),
            style: theme.typography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _historySurface(BuildContext context,
      {required List<ToothHistory> records}) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 320,
          minWidth: 260,
          maxHeight: 210,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.menuColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.inactiveColor.withAlpha(darkMode ? 60 : 35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: darkMode ? 0.35 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(WindowsIcons.history, size: 13, color: theme.accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Txt(
                    txt(widget.historyTitle),
                    style: theme.typography.bodyStrong?.copyWith(fontSize: 13),
                  ),
                ),
                if (records.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.inactiveBackgroundColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${records.length}',
                      style: theme.typography.caption?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final record in records) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 3,
                              height:
                                  (record.notes[widget.iso]?.isNotEmpty == true)
                                      ? 44
                                      : 26,
                              decoration: BoxDecoration(
                                color: record.date == null
                                    ? Colors.teal.withValues(alpha: 0.8)
                                    : theme.accentColor.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        record.date == null
                                            ? FluentIcons.contact_info
                                            : WindowsIcons.calendar,
                                        size: 11,
                                        color: record.date == null
                                            ? Colors.teal
                                            : theme.accentColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        record.label,
                                        style:
                                            theme.typography.caption?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          color: record.date == null
                                              ? (darkMode
                                                  ? Colors.teal.lightest
                                                  : Colors.teal.darkest)
                                              : theme.typography.caption?.color,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (record.teeth[widget.iso] != null) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(
                                          labelToIcon(
                                              record.teeth[widget.iso]!),
                                          size: 12,
                                          color: labelToColor(
                                              record.teeth[widget.iso]!),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          txt(record.teeth[widget.iso]!),
                                          style: theme.typography.bodyStrong
                                              ?.copyWith(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (record.notes[widget.iso]?.isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      record.notes[widget.iso]!,
                                      style: theme.typography.caption?.copyWith(
                                        fontSize: 11.5,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (records.isEmpty && widget.oldNote != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          txt(widget.oldNote!),
                          style: theme.typography.caption,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Size of an option's circle on the ring, and of the box the chosen one
/// rides in afterwards.
const _optionSize = 54.0;

// How much the chosen option grows once it is the only one left on the
// surface: with the ring folded away there is nothing to be highlighted
// against, so the option simply takes more of the space for itself.
const _chosenScale = 1.3;

class _RadialButton extends StatelessWidget {
  const _RadialButton({
    required this.state,
    required this.isSelected,
    required this.isHidden,
    required this.onTap,
  });
  final TxOption state;
  final bool isSelected;
  final bool isHidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: txt(state.label),
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: txt(state.label),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: isHidden ? 0.3 : (isSelected ? _chosenScale : 1.0),
            duration: const Duration(milliseconds: 250),
            curve: isHidden ? Curves.easeInCubic : Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: isHidden ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 250),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                height: _optionSize,
                width: _optionSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.color,
                  border: Border.all(
                    color: state.color.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: state.color.withValues(alpha: 0.35),
                      blurRadius: 6,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(state.icon, size: 24, color: Colors.white),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Txt(
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          txt(state.label),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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
}

/// The in-wheel text surface shared by the extra-notes field and the custom
/// "other" option editor — one look, one behaviour. It paints nothing of its
/// own: the tinted, morphing surface behind it carries the colour, so the
/// platform's default grey field box never shows through.
class _WheelTextField extends StatelessWidget {
  const _WheelTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    this.autofocus = false,
    this.micPlacement = MicPlacement.none,
  });
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final MicPlacement micPlacement;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return LiveTranscribingTextField(
      controller: controller,
      placeholder: placeholder,
      expands: true,
      maxLines: null,
      autofocus: autofocus,
      micPlacement: micPlacement,
      decoration: const BoxDecoration(),
      style: theme.typography.body?.copyWith(fontSize: 12.5, height: 1.25),
      padding: const EdgeInsetsDirectional.fromSTEB(30, 30, 30, 40),
      onChanged: onChanged,
      onTranscriptionDone: onChanged,
    );
  }
}

/// Clips the wheel to the shape it is painted as.
///
/// A [CustomClipper] rather than the plain radius of a [ClipRRect], because
/// only a clipper makes the clip take part in hit testing — and that is what
/// lets the surface absorb taps inside its circle or its folded rectangle
/// while the corners of the box around them fall through to the popup.
class _SurfaceClipper extends CustomClipper<RRect> {
  const _SurfaceClipper(this.radius);
  final double radius;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));

  @override
  bool shouldReclip(_SurfaceClipper oldClipper) => oldClipper.radius != radius;
}
