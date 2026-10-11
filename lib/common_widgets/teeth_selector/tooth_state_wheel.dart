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

  @override
  State<ToothStateWheel> createState() => _ToothStateWheelState();
}

class _ToothStateWheelState extends State<ToothStateWheel> {
  String? _selectedLabel;
  bool _isOtherMode = false;
  bool _hasNote = false;
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
    _hasNote = widget.extraNote.isNotEmpty;
    _notesController = TextEditingController(text: widget.extraNote);

    if (txOptions.where((x) => x.label == _selectedLabel).isEmpty &&
        _selectedLabel != null &&
        _selectedLabel != "") {
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

                  if (hasHistory && availableWidth >= 680) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(fit: BoxFit.scaleDown, child: wheel),
                        const SizedBox(width: 16),
                        historySurface!,
                      ],
                    );
                  }

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
            Button(
              onPressed: widget.onTapClose,
              style: ButtonStyle(
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(WindowsIcons.chrome_close, size: 10),
                  const SizedBox(width: 4),
                  Txt(txt('close')),
                ],
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
    final hasSelection = _selectedLabel != null && _selectedLabel!.isNotEmpty;
    final selectedColor = labelToColor(_selectedLabel ?? '');

    // Only the circle itself is a surface: the transparent square corners
    // around it let a tap through to the popup's own dismiss handler.
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.deferToChild,
      excludeFromSemantics: true,
      child: Container(
        key: const ValueKey('choice-wheel'),
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.menuColor,
          border: Border.all(
            color: hasSelection
                ? selectedColor.withValues(alpha: darkMode ? 0.6 : 0.4)
                : theme.inactiveColor.withAlpha(darkMode ? 60 : 40),
            width: hasSelection ? 2.0 : 1.0,
          ),
          boxShadow: [
            if (hasSelection)
              BoxShadow(
                color: selectedColor.withValues(alpha: darkMode ? 0.20 : 0.10),
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Center hub: Extra notes and the clear control
            _centerHub(context),

            // 18 radial buttons
            for (var index = 0; index < options.length; index++)
              Transform.translate(
                offset: Offset(
                  147 *
                      math.cos(
                          index * 2 * math.pi / options.length - math.pi / 2),
                  147 *
                      math.sin(
                          index * 2 * math.pi / options.length - math.pi / 2),
                ),
                child: _RadialButton(
                  state: options[index],
                  isSelected: _isOtherMode
                      ? options[index].label == 'other'
                      : _selectedLabel == options[index].label,
                  isDimmed: _isOtherMode
                      ? options[index].label != 'other'
                      : hasSelection && _selectedLabel != options[index].label,
                  onTap: () => _choose(options[index].label),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Records [label] on the tooth, or opens the custom editor for `other`.
  ///
  /// A second tap on the same option within [doubleTapWindow] confirms the
  /// choice by closing the popup — "set it and get out", without waiting for
  /// extra notes to be typed.
  static const doubleTapWindow = Duration(milliseconds: 350);
  Timer? _doubleTapTimer;
  String? _pendingTapLabel;

  void _choose(String label) {
    if (label == 'other') {
      setState(() {
        _isOtherMode = true;
        _otherController.text = txOptions.any((o) => o.label == _selectedLabel)
            ? ''
            : _selectedLabel ?? '';
      });
      return;
    }

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
    _select(label);
  }

  Widget _centerHub(BuildContext context) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final hasSelection = _selectedLabel != null && _selectedLabel!.isNotEmpty;
    final selectedColor = labelToColor(_selectedLabel ?? '');
    // The notes field only earns its place once there is something to attach
    // it to — a chosen option, the custom "other" editor, or notes carried in
    // from a saved record.
    final showField = hasSelection || _isOtherMode || _hasNote;

    return AnimatedContainer(
      key: const ValueKey('extra-notes-circle'),
      duration: const Duration(milliseconds: 250),
      width: 196,
      height: 196,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.inactiveBackgroundColor
            .withValues(alpha: darkMode ? 0.30 : 0.40),
        border: Border.all(
          color: hasSelection
              ? selectedColor.withValues(alpha: darkMode ? 0.55 : 0.35)
              : theme.inactiveColor.withAlpha(darkMode ? 45 : 30),
          width: hasSelection ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: darkMode ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: showField
                    ? _CircleTextField(
                        key: ValueKey(_isOtherMode ? 'other-field' : 'notes'),
                        controller:
                            _isOtherMode ? _otherController : _notesController,
                        placeholder: txt(
                            _isOtherMode ? 'other' : 'extraInfoPlaceholder'),
                        autofocus: _isOtherMode,
                        onChanged:
                            _isOtherMode ? _onOtherChanged : _onNotesChanged,
                      )
                    : _hubHint(context),
              ),
            ),
            if (hasSelection || _isOtherMode)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(child: _selectionPill(context)),
              ),
          ],
        ),
      ),
    );
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

  /// The only control floating above the notes field: clearing the tooth.
  ///
  /// The chosen treatment itself is already unmistakable — its button on the
  /// wheel carries the highlight and the check badge — so naming it here only
  /// crowded the clear action into a corner. Dropping the label lets the
  /// control sit centred, comfortably tappable, in the same accent colour as
  /// the choice it removes.
  Widget _selectionPill(BuildContext context) {
    final theme = FluentTheme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final isOther = _isOtherMode;
    final color = isOther ? Colors.teal : labelToColor(_selectedLabel ?? '');
    return Tooltip(
      message: txt('delete'),
      excludeFromSemantics: true,
      child: GestureDetector(
        onTap: () {
          _notesController.clear();
          _hasNote = false;
          _otherController.clear();
          widget.onExtraNote?.call('');
          _select(null);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.menuColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: darkMode ? 0.35 : 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(WindowsIcons.delete, size: 15, color: color),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 52),
                child: Text(
                  txt('delete'),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
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
                    txt('toothRecordHistory'),
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

class _RadialButton extends StatelessWidget {
  const _RadialButton({
    required this.state,
    required this.isSelected,
    required this.isDimmed,
    required this.onTap,
  });
  final TxOption state;
  final bool isSelected;
  final bool isDimmed;
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
            scale: isSelected ? 1.15 : (isDimmed ? 0.94 : 1.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: isDimmed ? 0.38 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.color,
                  border: Border.all(
                    color: isSelected
                        ? Colors.white
                        : state.color.withValues(alpha: 0.5),
                    width: isSelected ? 2.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: state.color.withValues(alpha: 0.75),
                            blurRadius: 10,
                            spreadRadius: 3,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: isDimmed
                                ? Colors.black.withValues(alpha: 0.08)
                                : state.color.withValues(alpha: 0.35),
                            blurRadius: isDimmed ? 4 : 6,
                            spreadRadius: isDimmed ? 0 : 1,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
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
                      if (isSelected)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: Icon(
                              WindowsIcons.check_mark,
                              size: 8,
                              color: state.color,
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

/// The circular, in-wheel text surface shared by the extra-notes field and the
/// custom "other" option editor — one look, one behaviour, including the
/// dictation button centred along the bottom edge and padding that keeps text
/// clear of the circle's curvature and of any selection pill above it.
class _CircleTextField extends StatelessWidget {
  const _CircleTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return LiveTranscribingTextField(
      controller: controller,
      placeholder: placeholder,
      expands: true,
      maxLines: null,
      autofocus: autofocus,
      micPlacement: MicPlacement.bottomCenter,
      style: theme.typography.body?.copyWith(fontSize: 12.5, height: 1.25),
      padding: const EdgeInsetsDirectional.fromSTEB(30, 46, 30, 40),
      onChanged: onChanged,
      onTranscriptionDone: onChanged,
    );
  }
}
