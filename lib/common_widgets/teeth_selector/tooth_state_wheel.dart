import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/live_transcription_button.dart';
import 'package:apexo/common_widgets/live_transcribing_textfield.dart';
import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/features/settings/settings_stores.dart';
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
    this.onOpenAppointment,
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

  final String historyTitle;

  /// The wheel closes itself first; the caller only opens the appointment.
  final ValueChanged<String>? onOpenAppointment;

  @override
  State<ToothStateWheel> createState() => _ToothStateWheelState();
}

class _ToothStateWheelState extends State<ToothStateWheel> {
  static const _morph = Duration(milliseconds: 350);

  static const _cornerRadius = 16.0;

  /// The chosen option's box, matching the option circles on the ring.
  static const _chip = _optionSize;
  static const _chipTop = 12.0;

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
    final records = _records();

    // Tapping outside the floating surfaces dismisses the popup; the surfaces
    // absorb their own taps without touching the semantics tree.
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

    return AnimatedContainer(
      key: const ValueKey('choice-wheel'),
      duration: _morph,
      curve: Curves.easeInOutCubic,
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: theme.menuColor,
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

  Widget _optionButton(int index,
      {required bool collapsed, required double box}) {
    const ringRadius = 147.0;
    final option = options[index];
    final isSelected =
        _isOtherMode ? option.label == 'other' : _selectedLabel == option.label;
    final hidden = collapsed && !isSelected;
    final angle = index * 2 * math.pi / options.length - math.pi / 2;
    final atTop = isSelected && collapsed;
    // inset by its grown size so its painted edge lines up with the notes field.
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

  // a second tap on the same option within this window closes the popup,
  // confirming the choice without waiting for extra notes.
  static const doubleTapWindow = Duration(milliseconds: 350);
  Timer? _doubleTapTimer;
  String? _pendingTapLabel;

  void _choose(String label) {
    if (_pendingTapLabel == label) {
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
      // tapping it again does nothing; clearing is the way back to the ring.
      return;
    }

    _select(label);
  }

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
                  micPlacement:
                      collapsed ? MicPlacement.none : MicPlacement.bottomCenter,
                  onChanged: _isOtherMode ? _onOtherChanged : _onNotesChanged,
                )
              : _hubHint(context),
        ),
      ),
    );
  }

  // saving keeps the note because the field already reported every keystroke;
  // clearing drops the choice, note and custom label and brings the ring back.
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
                children: [save, clear],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dictationButton({required bool collapsed, required double box}) {
    final available = transcriptionAvailable;
    final color = _accentColor;
    final rtl = locale.isRtl;

    return AnimatedPositioned(
      duration: _morph,
      curve: Curves.easeInOutCubic,
      left: rtl ? _edgeMargin : box - _edgeMargin - _dictationRow,
      top: _chipTop,
      // built only when dictation is available: the button owns a recorder.
      child: available
          ? _flank(
              visible: collapsed && _hasChoice,
              alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
              // the key follows the field it dictates into: the button binds
              // its controller once, so switching fields must rebuild it.
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

  // wider than the control it holds so the growing dictation button keeps its
  // place instead of pushing anything around.
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

  // copies an earlier record's treatment and note into this tooth; setting the
  // controller text fires no onChanged, so the note is reported by hand.
  void _copyRecord(ToothHistory record) {
    final treatment = record.teeth[widget.iso];
    if (treatment != null) _select(treatment);
    final note = record.notes[widget.iso];
    if (note != null && note.isNotEmpty) {
      _notesController.text = note;
      _onNotesChanged(note);
    }
  }

  void _onNotesChanged(String text) {
    final hasNote = text.isNotEmpty;
    if (hasNote != _hasNote) {
      setState(() => _hasNote = hasNote);
    }
    widget.onExtraNote?.call(text);
  }

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

  // a treatment recorded outside `history` arrives as `oldNote` alone; it is
  // wrapped as a dateless dental-notes record so the card can render it.
  List<ToothHistory> _records() {
    final records = widget.history
        .where((record) =>
            record.teeth.containsKey(widget.iso) ||
            record.notes[widget.iso]?.isNotEmpty == true)
        .toList();
    final oldNote = widget.oldNote;
    if (records.isEmpty && oldNote != null) {
      records.add(ToothHistory(
        label: txt('dentalNotes'),
        teeth: {widget.iso: oldNote},
        notes: const {},
      ));
    }
    return records
      ..sort((a, b) =>
          (b.date ?? DateTime(9999)).compareTo(a.date ?? DateTime(9999)));
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
              child: _HistoryScrollFade(
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
                                      if (record.date == null) ...[
                                        Icon(
                                          FluentIcons.contact_info,
                                          size: 11,
                                          color: Colors.teal,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Flexible(
                                        child: Text(
                                          record.date == null
                                              ? record.label
                                              : DF.full(record.date!),
                                          style: theme.typography.caption
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                            color: record.date == null
                                                ? (darkMode
                                                    ? Colors.teal.lightest
                                                    : Colors.teal.darkest)
                                                : theme
                                                    .typography.caption?.color,
                                          ),
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
                                        fontSize: 13.0,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (record.appointmentId != null) ...[
                              Tooltip(
                                message: txt('copyIntoThisRecord'),
                                child: IconButton(
                                  key: ValueKey(
                                      'copyNotes-${record.appointmentId}-${widget.iso}'),
                                  iconButtonMode: IconButtonMode.small,
                                  icon: const Icon(WindowsIcons.copy, size: 12),
                                  onPressed: () => _copyRecord(record),
                                ),
                              ),
                              if (widget.onOpenAppointment != null)
                                Tooltip(
                                  message: txt('open'),
                                  child: IconButton(
                                    key: ValueKey(
                                        'open-appointment-${record.appointmentId}'),
                                    iconButtonMode: IconButtonMode.small,
                                    icon: const Icon(
                                        WindowsIcons.open_in_new_window,
                                        size: 12),
                                    onPressed: () {
                                      widget.onTapClose();
                                      widget.onOpenAppointment!(
                                          record.appointmentId!);
                                    },
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
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

const _optionSize = 54.0;

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

// paints no decoration: the tinted surface behind it carries the colour.
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
      style: theme.typography.body?.copyWith(fontSize: 14.0, height: 1.3),
      padding: const EdgeInsetsDirectional.fromSTEB(30, 30, 30, 40),
      onChanged: onChanged,
      onTranscriptionDone: onChanged,
    );
  }
}

// clips the wheel to its painted shape. [ClipRRect] only clips hit testing
// when it is given a clipper, so the rounded shape is built here.
class _SurfaceClipper extends CustomClipper<RRect> {
  const _SurfaceClipper(this.radius);
  final double radius;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));

  @override
  bool shouldReclip(_SurfaceClipper oldClipper) => oldClipper.radius != radius;
}

class _HistoryScrollFade extends StatefulWidget {
  const _HistoryScrollFade({required this.child});
  final Widget child;

  @override
  State<_HistoryScrollFade> createState() => _HistoryScrollFadeState();
}

class _HistoryScrollFadeState extends State<_HistoryScrollFade> {
  final ScrollController _controller = ScrollController();
  bool _fadeTop = false;
  bool _fadeBottom = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncFade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFade());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFade);
    _controller.dispose();
    super.dispose();
  }

  void _syncFade() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final top = pos.maxScrollExtent > 1.0 && pos.pixels > 1.0;
    final bottom =
        pos.maxScrollExtent > 1.0 && pos.pixels < pos.maxScrollExtent - 1.0;
    if (top != _fadeTop || bottom != _fadeBottom) {
      setState(() {
        _fadeTop = top;
        _fadeBottom = bottom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _syncFade();
        return false;
      },
      child: ShaderMask(
        key: const ValueKey('wheel-history-fade'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          if (!_fadeTop && !_fadeBottom) {
            return const LinearGradient(
              colors: [Colors.white, Colors.white],
            ).createShader(bounds);
          }
          final h = bounds.height;
          final stop = h > 0 ? (20.0 / h).clamp(0.06, 0.22) : 0.14;
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _fadeTop ? Colors.transparent : Colors.white,
              Colors.white,
              Colors.white,
              _fadeBottom ? Colors.transparent : Colors.white,
            ],
            stops: [
              0.0,
              _fadeTop ? stop : 0.0,
              _fadeBottom ? 1.0 - stop : 1.0,
              1.0,
            ],
          ).createShader(bounds);
        },
        child: SingleChildScrollView(
          controller: _controller,
          child: widget.child,
        ),
      ),
    );
  }
}
