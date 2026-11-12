import 'package:fluent_ui/fluent_ui.dart';

/// The height of the app's form text fields.
///
/// A `CupertinoTextField` draws 17px text with 7px padding and a 1px border
/// per side, which measures 38px at the default text scale.
const double kTextFieldHeight = 38;

/// A [ComboBox] that matches the height of the text fields in the same form.
///
/// fluent_ui sizes the closed combo box from its text alone, so on desktop it
/// is only 26px tall while the text fields beside it are 38px. Applying the
/// field height as a minimum centres the label and still lets the control grow
/// when the user scales text up.
class AppComboBox<T> extends ComboBox<T> {
  const AppComboBox({
    required super.items,
    super.key,
    super.selectedItemBuilder,
    super.value,
    super.placeholder,
    super.disabledPlaceholder,
    super.onChanged,
    super.onTap,
    super.onOpen,
    super.onClose,
    super.elevation,
    super.style,
    super.icon,
    super.iconDisabledColor,
    super.iconEnabledColor,
    super.iconSize,
    super.isExpanded,
    super.focusColor,
    super.focusNode,
    super.autofocus,
    super.popupColor,
    super.popupConstraints,
  });

  @override
  State<ComboBox<T>> createState() => _AppComboBoxState<T>();
}

class _AppComboBoxState<T> extends ComboBoxState<T> {
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kTextFieldHeight),
      child: super.build(context),
    );
  }
}
