import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/svg.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_state_wheel.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

typedef Data = ({Size size, Map<String, _Tooth> teeth});

class TeethSelector extends StatefulWidget {
  final Map<String, String> currentNotes;
  final Map<String, String> oldNotes;
  final String leftString;
  final String rightString;
  final void Function(String tooth, String? note) onNote;
  final String Function(String isoString) notation;
  final TextStyle? textStyle;
  final TextStyle? tooltipTextStyle;
  final bool showPrimary;
  final StateType type;

  const TeethSelector({
    super.key,
    this.currentNotes = const {},
    this.oldNotes = const {},
    this.leftString = "Left",
    this.rightString = "Right",
    this.textStyle,
    this.tooltipTextStyle,
    this.showPrimary = false,
    required this.notation,
    required this.onNote,
    required this.type,
  });

  @override
  State<TeethSelector> createState() => _TeethSelectorState();
}

class _TeethSelectorState extends State<TeethSelector> {
  Data data = _loadTeeth();

  bool showPermanent = true;
  bool showPrimary = false;

  @override
  void initState() {
    for (var element in widget.currentNotes.keys) {
      if (data.teeth[element] != null) {
        data.teeth[element]!.selected = true;
      }
    }
    showPrimary = widget.showPrimary ||
        [...widget.currentNotes.keys, ...widget.oldNotes.keys].any((iso) =>
            iso.startsWith("5") ||
            iso.startsWith("6") ||
            iso.startsWith("7") ||
            iso.startsWith("8"));
    super.initState();
    super.initState();
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
                        key: Key(widget.currentNotes.toString()),
                        toothNote: MapEntry<String, String?>(
                            tKey, widget.currentNotes[tKey]),
                        tooth: tooth,
                        notation: widget.notation,
                        onNote: (iso, tooth) {
                          setState(() {
                            widget.onNote(iso, tooth);
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
            if (widget.oldNotes.isNotEmpty)
              _legendItem(
                "pastAppointments",
                WindowsIcons.history,
                Colors.transparent,
                FluentTheme.of(context).inactiveColor,
                context
              )
          ],
        )
      ],
    );
  }

  Container _legendItem(
      String note, IconData icon, Color color, Color textColor, BuildContext context) {
    return Container(
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(4), border: Border.all(color: textColor)),
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
  });

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
  Widget build(BuildContext context) {
    final bool darkMode = FluentTheme.of(context).brightness == Brightness.dark;
    final String? note = widget.oldNote ?? widget.currentNote;
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
        child: GestureDetector(
          key: Key(
              "tooth-iso-${widget.toothNote.key}-${widget.tooth.selected ? "selected" : "not-selected"}"),
          onTap: () {
            wheelController.showFlyout(
                placementMode: FlyoutPlacementMode.auto,
                builder: (x) => ToothStateWheel(
                    type: widget.type,
                    onTapClose: () {
                      wheelController.close();
                    },
                    iso: tKey,
                    toothName: widget.notation(tKey),
                    initialValue: widget.toothNote.value,
                    oldNote: widget.oldNote,
                    onSet: (note) {
                      wheelController.close();
                      widget.onNote(tKey, note);
                    }));
          },
          child: Tooltip(
            message: widget.notation(tKey),
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
                    color: FluentTheme.of(context).brightness == Brightness.dark
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
    );
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
  final Path path;
  final double strokeWidth;
  final Color strokeColor;

  const _ToothBorder(
    this.path, {
    required this.strokeWidth,
    required this.strokeColor,
  });

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
