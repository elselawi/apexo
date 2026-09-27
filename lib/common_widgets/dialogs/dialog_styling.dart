import 'package:fluent_ui/fluent_ui.dart';

ContentDialogThemeData dialogStyling(BuildContext context, bool danger,
    [bool withLowerPadding = false]) {
  return ContentDialogThemeData(
      actionsDecoration: BoxDecoration(
          color: FluentTheme.of(context).menuColor,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          boxShadow: [
            BoxShadow(
              color: (danger ? Colors.red : Colors.grey).withValues(alpha: 0.2),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 1),
            )
          ]),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        color: FluentTheme.of(context).micaBackgroundColor,
      ),
      titleStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      padding: EdgeInsets.fromLTRB(20, 20, 20, withLowerPadding ? 20 : 0));
}
