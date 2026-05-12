import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/features/stats/charts_controller.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class ChartsRangeSelector extends StatelessWidget {
  const ChartsRangeSelector({
    super.key,
    required Color color,
    required TextStyle textStyle,
    required List<IconData> icons,
  })  : _color = color,
        _textStyle = textStyle,
        _icons = icons;

  final Color _color;
  final TextStyle _textStyle;
  final List<IconData> _icons;

  @override
  Widget build(BuildContext context) {
    final df =
        localSettings.dateFormat.startsWith("d") == true ? "dd/MM" : "MM/dd";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 15),
      child: MStreamBuilder(
          streams: [
            chartsCtrl.start.stream,
            chartsCtrl.end.stream,
            chartsCtrl.interval.stream
          ],
          builder: (context, snapshot) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => chartsCtrl.rangePicker(context),
                  icon: Row(
                    children: [
                      Transform.flip(
                          flipX: true,
                          child: Icon(
                            WindowsIcons.calendar_reply,
                            size: 20,
                            color: _color,
                          )),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Txt(txt("start"), style: _textStyle),
                          Txt(
                              DateFormat("$df/yyyy", locale.s.$code)
                                  .format(chartsCtrl.start()),
                              style: _textStyle),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: chartsCtrl.toggleInterval,
                  icon: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            _icons[StatsInterval.values
                                .indexOf(chartsCtrl.interval())],
                            size: 20,
                            color: _color,
                          ),
                          const SizedBox(width: 5),
                          Txt("${chartsCtrl.periods.length} ${txt(chartsCtrl.intervalString)}",
                              style: _textStyle)
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => chartsCtrl.rangePicker(context),
                  icon: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Txt(txt("end"), style: _textStyle),
                          Txt(
                              DateFormat("$df/yyyy", locale.s.$code)
                                  .format(chartsCtrl.end()),
                              style: _textStyle),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Icon(WindowsIcons.calendar_reply,
                          size: 20, color: _color),
                    ],
                  ),
                ),
              ],
            );
          }),
    );
  }
}
