// Flutter ships no `ku` localization data; without these, `FluentApp` falls
// back to LTR widgets and logs an unsupported-locale warning.

import "package:cupertino_ui/cupertino_ui.dart" as cupertino_ui;
import "package:fluent_ui/fluent_ui.dart" hide MaterialLocalizations;
import "package:flutter/cupertino.dart" show CupertinoLocalizations;
import "package:flutter/foundation.dart" show SynchronousFuture;
import "package:flutter/material.dart" show MaterialLocalizations;
import "package:flutter_localizations/flutter_localizations.dart";
import "package:material_ui/material_ui.dart" as material_ui;

/// The delegates to hand to `FluentApp.localizationsDelegates`.
///
/// `FluentApp` appends the Material and Cupertino delegates from the decoupled
/// `material_ui` and `cupertino_ui` packages, so the Kurdish data is supplied
/// for those types too. Flutter's own Material data is declared here because
/// `FluentApp` no longer does it and the app still contains Flutter Material
/// widgets.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  _KuWidgetsLocalizationsDelegate(),
  _KuMaterialLocalizationsDelegate(),
  _KuCupertinoLocalizationsDelegate(),
  _KuMaterialUiLocalizationsDelegate(),
  _KuCupertinoUiLocalizationsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
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

class _KuMaterialUiLocalizationsDelegate
    extends LocalizationsDelegate<material_ui.MaterialLocalizations> {
  const _KuMaterialUiLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == "ku";

  /// Arabic is Flutter's closest data set for Kurdish (same script, RTL).
  @override
  Future<material_ui.MaterialLocalizations> load(Locale locale) =>
      material_ui.GlobalMaterialLocalizations.delegate.load(
        const Locale("ar"),
      );

  @override
  bool shouldReload(_KuMaterialUiLocalizationsDelegate old) => false;

  @override
  String toString() => "KuMaterialUiLocalizations.delegate";
}

class _KuCupertinoUiLocalizationsDelegate
    extends LocalizationsDelegate<cupertino_ui.CupertinoLocalizations> {
  const _KuCupertinoUiLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == "ku";

  /// Arabic is Flutter's closest data set for Kurdish (same script, RTL).
  @override
  Future<cupertino_ui.CupertinoLocalizations> load(Locale locale) =>
      cupertino_ui.GlobalCupertinoLocalizations.delegate
          .load(const Locale("ar"));

  @override
  bool shouldReload(_KuCupertinoUiLocalizationsDelegate old) => false;

  @override
  String toString() => "KuCupertinoUiLocalizations.delegate";
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
