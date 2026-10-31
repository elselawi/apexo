import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart'
    show showTimePicker, showDatePicker, TimeOfDay;

/// Locales whose CLDR time pattern is 24-hour, requiring an English override
/// when 12-hour mode is selected in settings.
const _localesWith24HourCldr = {"es", "el", "fa", "fr", "tr", "it"};

Future<TimeOfDay?> showAppTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  final use24HourFormat = DF.is24Hour;
  final forceTwelveHourEnglish =
      !use24HourFormat && _localesWith24HourCldr.contains(locale.s.$code);

  return showTimePicker(
    context: context,
    initialTime: initialTime,
    helpText: txt("selectTime"),
    cancelText: txt("cancel"),
    confirmText: txt("ok"),
    hourLabelText: txt("hour"),
    minuteLabelText: txt("minute"),
    builder: (context, child) {
      final dialog = MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(alwaysUse24HourFormat: use24HourFormat),
        child: child!,
      );
      if (!forceTwelveHourEnglish) return dialog;
      return Localizations.override(
        context: context,
        locale: const Locale("en"),
        child: dialog,
      );
    },
  );
}

class DateTimePicker extends StatefulWidget {
  const DateTimePicker({
    super.key,
    required this.initValue,
    required this.onChange,
    this.pickTime = false,
    this.buttonIcon = FluentIcons.time_entry,
    this.buttonText = "changeDate",
    this.showButton = true,
    this.enabled = true,
    this.textStyle,
    this.textAlignment = AlignmentDirectional.center,
  });
  final DateTime initValue;
  final bool pickTime;
  final bool showButton;
  final String buttonText;
  final IconData buttonIcon;
  final void Function(DateTime value) onChange;
  final TextStyle? textStyle;

  /// Where the date sits in the space the picker leaves for it. A picker that
  /// is one field of a row starts its date at the field's own edge — beside the
  /// glyph the date carries — rather than floating it in a box wider than the
  /// text.
  final AlignmentGeometry textAlignment;

  final bool enabled;

  @override
  State<DateTimePicker> createState() => DateTimePickerState();
}

class DateTimePickerState extends State<DateTimePicker> {
  late DateTime value;

  @override
  void initState() {
    super.initState();
    value = widget.initValue;
  }

  @override
  void didUpdateWidget(covariant DateTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The field is also a view of a record that another control can switch: the
    // chart's scope bar can put another visit behind the same band, and the date
    // on screen must be that visit's the moment it does. `initValue` is the only
    // source of truth — the picker's own `value` is just the last thing it drew.
    if (widget.initValue != oldWidget.initValue) {
      value = widget.initValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = FluentTheme.of(context).menuColor;
    return GestureDetector(
      onTap: pick,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 5),
        decoration: BoxDecoration(
            color: widget.enabled ? color : color.toAccentColor().dark,
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(5)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The date shortens before the row overflows: a window is as narrow
            // as its panel, and the button beside it does not shrink.
            Flexible(
              child: SizedBox(
                  height: 34,
                  child: Align(
                      alignment: widget.textAlignment,
                      child: Txt(
                        widget.pickTime ? DF.time(value) : DF.commonDate(value),
                        style: widget.textStyle,
                        overflow: TextOverflow.ellipsis,
                      ))),
            ),
            if (widget.showButton && widget.enabled)
              IconButton(
                onPressed: pick,
                icon: ButtonContent(widget.buttonIcon, txt(widget.buttonText)),
              )
          ],
        ),
      ),
    );
  }

  Future<void> pick() async {
    if (!widget.enabled) return;
    DateTime selected = value;

    if (widget.pickTime) {
      final TimeOfDay time = await showAppTimePicker(
            context,
            initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
          ) ??
          TimeOfDay(hour: selected.hour, minute: selected.minute);
      selected = DateTime(
          selected.year, selected.month, selected.day, time.hour, time.minute);
    } else {
      selected = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime.now().subtract(const Duration(days: 9999)),
            lastDate: DateTime.now().add(const Duration(days: 9999)),
          ) ??
          selected;
    }

    if (!mounted) return;
    setState(() {
      widget.onChange(selected);
      value = selected;
    });
  }
}
