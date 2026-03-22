import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart'
    show showTimePicker, showDatePicker, TimeOfDay;
import 'package:intl/intl.dart';

class DateTimePicker extends StatefulWidget {
  final DateTime initValue;
  final bool pickTime;
  final bool showButton;
  final String format;
  final String buttonText;
  final IconData buttonIcon;
  final void Function(DateTime value) onChange;
  final TextStyle? textStyle;
  final bool enabled;
  const DateTimePicker({
    super.key,
    required this.initValue,
    required this.onChange,
    this.pickTime = false,
    this.format = "dd/MM/yyyy",
    this.buttonIcon = FluentIcons.time_entry,
    this.buttonText = "Change date",
    this.showButton = true,
    this.enabled = true,
    this.textStyle,
  });

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
            SizedBox(
                height: 34,
                child: Center(
                    child: Txt(
                  DateFormat(widget.format, locale.s.$code).format(value),
                  style: widget.textStyle,
                ))),
            if (widget.showButton)
              Button(
                onPressed: pick,
                child: ButtonContent(widget.buttonIcon, widget.buttonText),
              )
          ],
        ),
      ),
    );
  }

  pick() async {
    if (!widget.enabled) return;
    DateTime selected = value;

    if (widget.pickTime) {
      TimeOfDay time = await showTimePicker(
            context: context,
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

    setState(() {
      widget.onChange(selected);
      value = selected;
    });
  }
}
