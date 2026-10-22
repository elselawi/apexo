import "dart:async";
import "package:apexo/core/reactive/observable.dart";
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

  /// The language on screen, owned here rather than in the settings store.
  ///
  /// Every `txt()` and every [Txt] needs the language and nothing else this
  /// module holds. Reading it from `LocalSettings` made the 113 files that
  /// translate a string depend on the whole settings store — and, through it,
  /// on the application binding and every feature behind it. A service that owns
  /// a language must not know what a store is.
  ///
  /// The store still persists the choice: it pushes it here when it loads and
  /// when the user picks another language (`LocalSettings.selectedLocale`).
  final selected = ObservableState<int>(0);

  En get s => list[selected()];

  /// Selects the language at [index], clamped to the languages that exist — a
  /// preference written by a build with more languages must not crash `txt()`.
  void select(int index) {
    final next = index < 0
        ? 0
        : (index >= list.length ? list.length - 1 : index);
    if (next == selected()) return;
    selected(next);
  }

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
        // The language alone: a text widget has no business rebuilding when the
        // calendar system or the money format changes.
        stream: locale.selected.stream,
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
