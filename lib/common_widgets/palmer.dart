import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PalmerNotation extends StatelessWidget {
  const PalmerNotation(
      {super.key,
      this.color,
      required this.iso,
      this.note,
      this.withTooltip = true});

  final Color? color;
  final String iso;
  final String? note;
  final bool withTooltip;

  @override
  Widget build(BuildContext context) {
    final Color color = this.color ?? Colors.black;
    final borderSide = BorderSide(color: color, width: 2);
    final int isoInt = int.parse(iso);
    String arch = iso[0];
    String tooth = iso[1];

    if (isoInt > 48) {
      if (tooth == "1") tooth = "A";
      if (tooth == "2") tooth = "B";
      if (tooth == "3") tooth = "C";
      if (tooth == "4") tooth = "D";
      if (tooth == "5") tooth = "E";
    }

    if (arch == "5") arch = "1";
    if (arch == "6") arch = "2";
    if (arch == "7") arch = "3";
    if (arch == "8") arch = "4";

    final bool upper = arch == "1" || arch == "2";
    final bool left = arch == "2" || arch == "3";

    return withTooltip
        ? Tooltip(
            enableFeedback: true,
            triggerMode: TooltipTriggerMode.tap,
            message: txt(note ?? iso),
            child: _content(color, upper, borderSide, left, tooth),
          )
        : _content(color, upper, borderSide, left, tooth);
  }

  Container _content(
      Color color, bool upper, BorderSide borderSide, bool left, String tooth) {
    return Container(
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        border: Border(
          bottom: upper ? borderSide : BorderSide.none,
          top: upper == false ? borderSide : BorderSide.none,
          left: left ? borderSide : BorderSide.none,
          right: left == false ? borderSide : BorderSide.none,
        ),
      ),
      width: 20,
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 0),
      child: Text(
        tooth,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
