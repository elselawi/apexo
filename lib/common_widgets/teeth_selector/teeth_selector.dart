import 'dart:async';
import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/svg.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_state_wheel.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

typedef Data = ({Size size, Map<String, _Tooth> teeth});

class TeethSelector extends StatefulWidget {
  const TeethSelector({
    super.key,
    this.currentNotes = const {},
    this.oldNotes = const {},
    this.extraNotes = const {},
    this.leftString = "Left",
    this.rightString = "Right",
    this.textStyle,
    this.tooltipTextStyle,
    this.showPrimary = false,
    this.history = const [],
    this.historyTitle = 'toothHistory',
    required this.notation,
    required this.onNote,
    this.onExtraNote,
    required this.type,
  });
  final Map<String, String> currentNotes;
  final Map<String, String> oldNotes;
  final Map<String, String> extraNotes;
  final String leftString;
  final String rightString;
  final void Function(String tooth, String? note) onNote;
  final void Function(String tooth, String extraNote)? onExtraNote;
  final String Function(String isoString) notation;
  final TextStyle? textStyle;
  final TextStyle? tooltipTextStyle;
  final bool showPrimary;
  final List<ToothHistory> history;
  final String historyTitle;
  final StateType type;

  @override
  State<TeethSelector> createState() => _TeethSelectorState();
}

class _TeethSelectorState extends State<TeethSelector> {
  Data data = _loadTeeth();

  bool showPermanent = true;
  bool showPrimary = false;
  late final Map<String, String> _extraNotes;

  @override
  void initState() {
    for (var element in widget.currentNotes.keys) {
      if (data.teeth[element] != null) {
        data.teeth[element]!.selected = true;
      }
    }
    _extraNotes = Map<String, String>.from(widget.extraNotes);
    // For "other" treatments, pre-fill the extra note with the custom text
    for (final entry in widget.currentNotes.entries) {
      if (txOptions.where((x) => x.label == entry.value).isEmpty &&
          entry.value.isNotEmpty &&
          !_extraNotes.containsKey(entry.key)) {
        _extraNotes[entry.key] = entry.value;
      }
    }
    showPrimary = widget.showPrimary ||
        [...widget.currentNotes.keys, ...widget.oldNotes.keys].any((iso) =>
            iso.startsWith("5") ||
            iso.startsWith("6") ||
            iso.startsWith("7") ||
            iso.startsWith("8"));
    super.initState();
  }

  @override
  void didUpdateWidget(covariant TeethSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _extraNotes
      ..clear()
      ..addAll(widget.extraNotes);
  }

  @override
  Widget build(BuildContext context) {
    if (data.size == Size.zero) return const UnconstrainedBox();
    final allNotes = <String>{
      ...[
        ...widget.currentNotes.values,
        ...widget.oldNotes.values
      ].map((x) => txOptions.where((y) => y.label == x).isEmpty ? "other" : x)
    }.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          child: SizedBox.fromSize(
            size: data.size,
            child: Stack(
              children: [
                Positioned(
                  bottom: data.size.height / 2 - 30,
                  left: data.size.width / 2 - 80,
                  child: Transform.scale(
                    scale: 1,
                    child: SizedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Checkbox(
                              checked: showPermanent,
                              onChanged: (checked) => setState(
                                  () => showPermanent = checked == true),
                              content: Txt(txt("showPermanent")),
                            ),
                            const SizedBox(height: 5),
                            Checkbox(
                              checked: showPrimary,
                              onChanged: (checked) =>
                                  setState(() => showPrimary = checked == true),
                              content: Txt(txt("showPrimary")),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: data.size.height * 0.5 - 11,
                  child: Text(widget.rightString,
                      style: (widget.textStyle ??
                              FluentTheme.of(context).typography.bodyStrong)!
                          .copyWith(color: Colors.grey)),
                ),
                Positioned(
                  right: 10,
                  top: data.size.height * 0.5 - 11,
                  child: Text(widget.leftString,
                      style: (widget.textStyle ??
                              FluentTheme.of(context).typography.bodyStrong)!
                          .copyWith(color: Colors.grey)),
                ),
                // teeth
                for (final MapEntry(key: tKey, value: tooth)
                    in data.teeth.entries)
                  if ((showPrimary || int.parse(tKey) < 50) &&
                      (showPermanent || int.parse(tKey) > 50))
                    Positioned.fromRect(
                      rect: tooth.rect,
                      child: _SingleToothDraw(
                        type: widget.type,
                        history: widget.history,
                        historyTitle: widget.historyTitle,
                        extraNote: _extraNotes[tKey] ?? '',
                        onExtraNote: (text) {
                          setState(() => _extraNotes[tKey] = text);
                          widget.onExtraNote?.call(tKey, text);
                        },
                        key: ValueKey(tKey),
                        toothNote: MapEntry<String, String?>(
                            tKey, widget.currentNotes[tKey]),
                        tooth: tooth,
                        notation: widget.notation,
                        onNote: (iso, tooth) {
                          setState(() {
                            widget.onNote(iso, tooth);
                            if (tooth == null) _extraNotes.remove(iso);
                          });
                        },
                        currentNote: widget.currentNotes[tKey],
                        oldNote: widget.oldNotes[tKey],
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ...List.generate(
              allNotes.length,
              (i) => _legendItem(allNotes[i], labelToIcon(allNotes[i]),
                  labelToColor(allNotes[i]), Colors.white, context),
            ),
          ],
        ),
      ],
    );
  }

  Container _legendItem(String note, IconData icon, Color color,
      Color textColor, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: textColor)),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 5),
          Txt(
            txt(note),
            style: FluentTheme.of(context)
                .typography
                .caption!
                .copyWith(color: textColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _SingleToothDraw extends StatefulWidget {
  const _SingleToothDraw({
    super.key,
    required this.toothNote,
    required this.tooth,
    required this.currentNote,
    required this.oldNote,
    required this.notation,
    required this.onNote,
    required this.type,
    required this.extraNote,
    required this.onExtraNote,
    required this.history,
    required this.historyTitle,
  });

  final String extraNote;
  final ValueChanged<String> onExtraNote;
  final List<ToothHistory> history;
  final String historyTitle;
  final String Function(String isoString) notation;
  final MapEntry<String, String?> toothNote;
  final _Tooth tooth;
  final String? currentNote;
  final String? oldNote;
  final void Function(String iso, String? note) onNote;
  final StateType type;

  @override
  State<_SingleToothDraw> createState() => _SingleToothDrawState();
}

class _SingleToothDrawState extends State<_SingleToothDraw> {
  final FlyoutController wheelController = FlyoutController();

  @override
  void dispose() {
    wheelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool darkMode = FluentTheme.of(context).brightness == Brightness.dark;
    final String? note = widget.currentNote ?? widget.oldNote;
    final tKey = widget.toothNote.key;
    final tColor = widget.currentNote != null
        ? labelToColor(widget.currentNote!)
        : widget.oldNote != null
            ? labelToColor(widget.oldNote!)
                .withAlpha(50)
                .toAccentColor()
                .darkest
            : FluentTheme.of(context).inactiveColor.withAlpha(180);
    return Container(
      margin: darkMode ? const EdgeInsets.all(3) : null,
      decoration: BoxDecoration(
        color: darkMode ? tColor : Colors.transparent,
        borderRadius: BorderRadius.circular(100),
      ),
      child: FlyoutTarget(
        controller: wheelController,
        child: Semantics(
          // One semantics node per tooth, with the **action** attached to the
          // tooth itself. `Tooltip` only contributes a label, and an assistive
          // activation of a label-only node is delivered as a synthesized
          // pointer event at the node's centre — which, for the incisors whose
          // bounding-box centre falls outside their own path, landed on the
          // sibling drawn after them (the node for tooth 11 opened 12, the node
          // for 12 opened 13). Attaching the action removes the ambiguity.
          button: true,
          label: widget.notation(tKey),
          onTap: () => unawaited(_open(context, tKey)),
          excludeSemantics: true,
          child: GestureDetector(
            // `selected` means "this tooth carries a condition **in the draft**",
            // which is `currentNote != null` — not the `_Tooth.selected` flag,
            // which is only ever set once, in `initState`, from the notes the
            // chart opened with. Recording a condition never updated it, so the
            // key stayed `not-selected` and both `tooth_chart 02`/`03` and
            // `patient_panel 05` waited forever for `tooth-iso-<n>-selected`.
            // History (`oldNote` with no current note) must stay unselected —
            // that is what `patient_panel 05` asserts.
            key: WK.tooth(tKey, selected: widget.currentNote != null),
            onTap: () => unawaited(_open(context, tKey)),
            child: Tooltip(
              message: widget.notation(tKey),
              excludeFromSemantics: true,
              child: Stack(
                children: [
                  if (note != null)
                    Center(
                      child: Icon(
                        widget.oldNote != null && widget.currentNote == null
                            ? WindowsIcons.history
                            : labelToIcon(note),
                        color: darkMode
                            ? Colors.white
                            : tColor.toAccentColor().darkest,
                      ),
                    )
                  else
                    Center(
                        child: DentalNotation(
                      iso: tKey,
                      withTooltip: false,
                      color: darkMode
                          ? FluentTheme.of(context).inactiveBackgroundColor
                          : Colors.grey,
                    )),
                  Container(
                    decoration: ShapeDecoration(
                      color:
                          FluentTheme.of(context).brightness == Brightness.dark
                              ? Colors.transparent
                              : tColor,
                      shape: _ToothBorder(
                        widget.tooth.path,
                        strokeColor: Colors.transparent,
                        strokeWidth: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the treatment-state picker for [tKey] — a flyout on a wide screen,
  /// a dialog otherwise. Shared by the pointer gesture and the semantics
  /// action so both routes do exactly the same thing.
  Future<void> _open(BuildContext context, String tKey) async {
    try {
      if (MediaQuery.of(context).size.width > 900) {
        await flyoutFocusFix(context);
        unawaited(wheelController.showFlyout<void>(
          builder: (context) => _showStateWheel(context, tKey),
          barrierDismissible: true,
          dismissWithEsc: true,
          barrierColor: Colors.black.withValues(alpha: 0.18),
        ));
        return;
      }
      unawaited(showDialog(
          barrierDismissible: true,
          dismissWithEsc: true,
          barrierColor: Colors.black.withValues(alpha: 0.35),
          context: context,
          builder: (context) => Center(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: _showStateWheel(context, tKey),
              ))));
    } catch (e, s) {
      debugPrint('Error in _open: $e\n$s');
    }
  }

  Widget _showStateWheel(BuildContext context, String tKey) {
    return ToothStateWheel(
        type: widget.type,
        onTapClose: () {
          Navigator.pop(context);
        },
        iso: tKey,
        toothName: widget.notation(tKey),
        initialValue: widget.toothNote.value,
        oldNote: widget.oldNote,
        extraNote: widget.extraNote,
        onExtraNote: widget.onExtraNote,
        history: widget.history,
        historyTitle: widget.historyTitle,
        onSet: (note) {
          widget.onNote(tKey, note);
        });
  }
}

Data _loadTeeth() {
  final doc = XmlDocument.parse(svgString);
  final viewBox = doc.rootElement.getAttribute('viewBox')!.split(' ');
  final w = double.parse(viewBox[2]);
  final h = double.parse(viewBox[3]);

  final teeth = doc.rootElement.findAllElements('path');
  return (
    size: Size(w, h),
    teeth: <String, _Tooth>{
      for (final tooth in teeth)
        tooth.getAttribute('id')!:
            _Tooth(parseSvgPathData(tooth.getAttribute('d')!)),
    },
  );
}

class _Tooth {
  _Tooth(Path originalPath) {
    rect = originalPath.getBounds();
    path = originalPath.shift(-rect.topLeft);
  }

  late final Path path;
  late final Rect rect;
  bool selected = false;
}

class _ToothBorder extends ShapeBorder {
  const _ToothBorder(
    this.path, {
    required this.strokeWidth,
    required this.strokeColor,
  });
  final Path path;
  final double strokeWidth;
  final Color strokeColor;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return rect.topLeft == Offset.zero ? path : path.shift(rect.topLeft);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor;
    canvas.drawPath(getOuterPath(rect), paint);
  }

  @override
  ShapeBorder scale(double t) => this;
}
