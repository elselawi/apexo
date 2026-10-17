import "dart:async";
import "package:apexo/features/settings/settings_stores.dart";
import "package:apexo/services/localization/ar.dart";
import "package:apexo/services/localization/el.dart";
import "package:apexo/services/localization/en.dart";
import "package:apexo/services/localization/es.dart";
import "package:apexo/services/localization/fa.dart";
import "package:apexo/services/localization/fr.dart";
import "package:apexo/services/localization/intl_data.dart";
import "package:apexo/services/localization/it.dart";
import "package:apexo/services/localization/ku.dart";
import "package:apexo/services/localization/tr.dart";
import "package:apexo/services/localization/ur.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:intl/date_symbol_data_local.dart";

class _Localization {
  _Localization() {
    unawaited(initializeDateFormatting());
    ensureCustomIntlLocalesInitialized();
  }

  List<En> list = [En(), Ar(), Es(), El(), Fa(), Ku(), Fr(), Tr(), It(), Ur()];
  En get s => list[localSettings.selectedLocale];
  bool get isRtl => s.$direction == TextDirection.rtl;
}

final locale = _Localization();

String txt(String input) {
  final term = locale.s.dictionary[input];
  if (term != null) {
    return term;
  }
  return input;
}

class Txt extends Text {
  const Txt(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: localSettings.stream,
        builder: (context, snapshot) {
          return Text(
            data ?? "",
            key: key,
            style: style,
            locale: this.locale,
            textScaler: textScaler,
            semanticsLabel: semanticsLabel,
            textAlign: textAlign,
            textDirection: textDirection,
            softWrap: softWrap,
            overflow: overflow,
            maxLines: maxLines,
            strutStyle: strutStyle,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior,
            selectionColor: selectionColor,
          );
        });
  }
}
