// Flutter ships no `ku` localization data, so `FluentApp` would otherwise
// fall back to LTR widgets and print "not supported by all delegates".

import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/cupertino.dart" show CupertinoLocalizations;
import "package:flutter/foundation.dart" show SynchronousFuture;
import "package:flutter_localizations/flutter_localizations.dart";

/// The delegates to hand to `FluentApp.localizationsDelegates`.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  _KuWidgetsLocalizationsDelegate(),
  _KuMaterialLocalizationsDelegate(),
  _KuCupertinoLocalizationsDelegate(),
];

class _KuWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _KuWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == "ku";

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture(const _KuWidgetsLocalizations());

  @override
  bool shouldReload(_KuWidgetsLocalizationsDelegate old) => false;

  @override
  String toString() => "KuWidgetsLocalizations.delegate";
}

class _KuMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _KuMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == "ku";

  /// Arabic is Flutter's closest data set for Kurdish (same script, RTL).
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale("ar"));

  @override
  bool shouldReload(_KuMaterialLocalizationsDelegate old) => false;

  @override
  String toString() => "KuMaterialLocalizations.delegate";
}

class _KuCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _KuCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == "ku";

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale("ar"));

  @override
  bool shouldReload(_KuCupertinoLocalizationsDelegate old) => false;

  @override
  String toString() => "KuCupertinoLocalizations.delegate";
}

class _KuWidgetsLocalizations extends GlobalWidgetsLocalizations {
  const _KuWidgetsLocalizations() : super(TextDirection.rtl);

  @override
  String get copyButtonLabel => "کۆپیکردن";

  @override
  String get cutButtonLabel => "بڕین";

  @override
  String get lookUpButtonLabel => "گەڕان لە فەرهەنگ";

  @override
  String get noResultsFound => "هیچ ئەنجامێک نەدۆزرایەوە";

  @override
  String get pasteButtonLabel => "لکاندن";

  @override
  String get radioButtonUnselectedLabel => "هەڵنەبژێردراو";

  @override
  String get reorderItemDown => "جووڵاندن بۆ خوارەوە";

  @override
  String get reorderItemLeft => "جووڵاندن بۆ چەپ";

  @override
  String get reorderItemRight => "جووڵاندن بۆ ڕاست";

  @override
  String get reorderItemToEnd => "جووڵاندن بۆ کۆتایی";

  @override
  String get reorderItemToStart => "جووڵاندن بۆ سەرەتا";

  @override
  String get reorderItemUp => "جووڵاندن بۆ سەرەوە";

  @override
  String get searchResultsFound => "ئەنجامی گەڕان دۆزرایەوە";

  @override
  String get searchWebButtonLabel => "گەڕان لە وێبدا";

  @override
  String get selectAllButtonLabel => "هەموو هەڵبژێرە";

  @override
  String get shareButtonLabel => "هاوبەشکردن";
}
