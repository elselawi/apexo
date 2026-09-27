import "package:fluent_ui/fluent_ui.dart";

final colorsWithoutYellow = Colors.accentColors
    .where((e) => Colors.accentColors.indexOf(e) > 0)
    .toList()
    .reversed
    .toList();
