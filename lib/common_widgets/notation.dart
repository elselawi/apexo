import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DentalNotation extends StatelessWidget {
  const DentalNotation({
    super.key,
    this.color,
    required this.iso,
    this.note,
    this.withTooltip = true,
  });

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
    final bool isPalmer = localSettings.dentalNotation == "p";
    final bool isISO = localSettings.dentalNotation == "i";

    return Container(
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        border: Border(
          bottom: (upper && isPalmer) ? borderSide : BorderSide.none,
          top: (upper == false && isPalmer) ? borderSide : BorderSide.none,
          left: (left && isPalmer) ? borderSide : BorderSide.none,
          right: (left == false && isPalmer) ? borderSide : BorderSide.none,
        ),
      ),
      width: isPalmer ? 20 : 25,
      height: isPalmer ? 20 : 25,
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 0),
      child: Center(
        child: Text(
          isPalmer ? tooth : isISO ? iso : _isoToUniversal(iso),
          softWrap: false,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

String _isoToUniversal(String iso) {
  if (iso.length != 2) {
    throw ArgumentError('ISO code must be 2 digits');
  }

  int quadrant = int.parse(iso[0]);
  int position = int.parse(iso[1]);

  // Permanent teeth (quadrants 1–4)
  if (quadrant >= 1 && quadrant <= 4) {
    if (position < 1 || position > 8) {
      throw ArgumentError('Invalid position for permanent teeth');
    }
    switch (quadrant) {
      case 1: // Upper right
        return '${9 - position}';
      case 2: // Upper left
        return '${8 + position}';
      case 3: // Lower left
        return '${17 + (8 - position)}';
      case 4: // Lower right
        return '${24 + position}';
    }
  }

  // Primary teeth (quadrants 5–8)
  if (quadrant >= 5 && quadrant <= 8) {
    if (position < 1 || position > 5) {
      throw ArgumentError('Invalid position for primary teeth');
    }

    // Universal letters for primary teeth
    const primaryUniversal = [
      'E', 'D', 'C', 'B', 'A', // Upper right
      'F', 'G', 'H', 'I', 'J', // Upper left
      'O', 'N', 'M', 'L', 'K', // Lower left
      'P', 'Q', 'R', 'S', 'T', // Lower right
    ];

    int index;
    switch (quadrant) {
      case 5: // Upper right
        index = position - 1;
        break;
      case 6: // Upper left
        index = 5 + (position - 1);
        break;
      case 7: // Lower left
        index = 10 + (position - 1);
        break;
      case 8: // Lower right
        index = 15 + (position - 1);
        break;
      default:
        throw ArgumentError('Invalid quadrant');
    }
    return primaryUniversal[index];
  }

  throw ArgumentError('Invalid quadrant in ISO code');
}
