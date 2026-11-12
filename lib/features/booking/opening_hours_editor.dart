import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/features/booking/booking_labels.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Seven day rows of editable intervals plus the closed-date list. Validation
/// mirrors the Worker, so the server never rejects a value this editor allowed.
class OpeningHoursEditor extends StatefulWidget {
  const OpeningHoursEditor({
    super.key,
    required this.hours,
    required this.onChanged,
    required this.closedDates,
    required this.onClosedDatesChanged,
    this.enabled = true,
  });

  final BookingWeeklyHours hours;
  final ValueChanged<BookingWeeklyHours> onChanged;
  final List<String> closedDates;
  final ValueChanged<List<String>> onClosedDatesChanged;
  final bool enabled;

  @override
  State<OpeningHoursEditor> createState() => _OpeningHoursEditorState();
}

class _OpeningHoursEditorState extends State<OpeningHoursEditor> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key, String value) {
    final existing = _controllers[key];
    if (existing == null) {
      return _controllers[key] = TextEditingController(text: value);
    }
    if (existing.text != value) {
      existing.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    return existing;
  }

  BookingWeeklyHours get _hours => widget.hours;

  Map<String, List<List<String>>> _copyDays() => {
        for (final key in bookingWeekdays)
          key: _hours[key]
              .map((interval) => List<String>.from(interval))
              .toList(),
      };

  void _setInterval(String day, int index, int bound, String value) {
    final days = _copyDays();
    final intervals = days[day]!;
    if (index >= intervals.length) return;
    intervals[index][bound] = value;
    widget.onChanged(BookingWeeklyHours(days));
  }

  void _addInterval(String day) {
    final days = _copyDays();
    days[day]!.add(["09:00", "17:00"]);
    widget.onChanged(BookingWeeklyHours(days));
  }

  void _removeInterval(String day, int index) {
    final days = _copyDays();
    days[day]!.removeAt(index);
    widget.onChanged(BookingWeeklyHours(days));
  }

  void _copyToAllDays(String day) {
    final source =
        _hours[day].map((interval) => List<String>.from(interval)).toList();
    final days = {
      for (final key in bookingWeekdays)
        key: source.map((interval) => List<String>.from(interval)).toList(),
    };
    widget.onChanged(BookingWeeklyHours(days));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final error = _hours.validate("hours");
    final days = bookingWeekdaysForDisplay();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        for (final day in days) _dayRow(theme, day),
        if (error != null)
          Text(txt("bookingHoursInvalid"),
              style: const TextStyle(color: Colors.errorPrimaryColor)),
        const SizedBox(height: 10),
        Text(txt("bookingClosedDates"), style: theme.typography.bodyStrong),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final date in widget.closedDates) _closedDateChip(theme, date),
            if (widget.closedDates.length < 366)
              DateTimePicker(
                enabled: widget.enabled,
                initValue: DateTime.now(),
                onChange: (date) {
                  final value = "${date.year.toString().padLeft(4, "0")}-"
                      "${date.month.toString().padLeft(2, "0")}-"
                      "${date.day.toString().padLeft(2, "0")}";
                  if (!widget.closedDates.contains(value)) {
                    final next = [...widget.closedDates, value]..sort();
                    widget.onClosedDatesChanged(next);
                  }
                },
                buttonText: txt("add"),
                buttonIcon: FluentIcons.add,
              ),
          ],
        ),
      ],
    );
  }

  Widget _closedDateChip(FluentThemeData theme, String date) {
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 10),
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(date),
          IconButton(
            icon: const Icon(FluentIcons.clear, size: 10),
            onPressed: widget.enabled
                ? () => widget.onClosedDatesChanged(
                    widget.closedDates.where((value) => value != date).toList())
                : null,
          ),
        ],
      ),
    );
  }

  Widget _dayRow(FluentThemeData theme, String day) {
    final intervals = _hours[day];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              txt("bookingWeekdayShort${bookingWeekdayNumber(day)}"),
              style: theme.typography.bodyStrong,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (intervals.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(txt("bookingClosed"),
                      style: TextStyle(
                          color: theme.resources.textFillColorSecondary)),
                ),
              for (var intervalIndex = 0;
                  intervalIndex < intervals.length;
                  intervalIndex++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: CupertinoTextField(
                          enabled: widget.enabled,
                          placeholder: "09:00",
                          controller: _controllerFor(
                            "$day:$intervalIndex:0",
                            intervals[intervalIndex][0],
                          ),
                          onChanged: (value) =>
                              _setInterval(day, intervalIndex, 0, value),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Txt("–"),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 90,
                        child: CupertinoTextField(
                          enabled: widget.enabled,
                          placeholder: "17:00",
                          controller: _controllerFor(
                            "$day:$intervalIndex:1",
                            intervals[intervalIndex][1],
                          ),
                          onChanged: (value) =>
                              _setInterval(day, intervalIndex, 1, value),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(FluentIcons.clear, size: 10),
                        onPressed: widget.enabled
                            ? () => _removeInterval(day, intervalIndex)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (intervals.length < 4)
          IconButton(
            icon: const Icon(FluentIcons.add, size: 10),
            onPressed: widget.enabled ? () => _addInterval(day) : null,
          ),
        IconButton(
          icon: const Icon(FluentIcons.copy, size: 10),
          onPressed: widget.enabled ? () => _copyToAllDays(day) : null,
        ),
      ],
    );
  }
}

/// Small helper for callers that only need the single-line summary.
String bookingHoursSummary(BookingWeeklyHours hours, {String? startDay}) {
  final parts = <String>[];
  for (final day in bookingWeekdaysForDisplay(startDay)) {
    final intervals = hours[day];
    if (intervals.isEmpty) continue;
    parts.add("${txt("bookingWeekdayShort${bookingWeekdayNumber(day)}")} "
        "${intervals.map((interval) => "${interval[0]}–${interval[1]}").join(", ")}");
  }
  return parts.isEmpty ? txt("bookingClosed") : parts.join(" · ");
}
