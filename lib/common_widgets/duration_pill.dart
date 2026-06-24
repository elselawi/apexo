import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A pill-shaped widget that displays an appointment's duration and allows
/// cycling through preset durations via a flyout menu.
class DurationPill extends StatefulWidget {
  final Appointment item;
  final Color color;
  final void Function(int duration) onSet;
  final bool isCompact;
  final bool disabled;

  const DurationPill({
    super.key,
    required this.item,
    required this.onSet,
    this.isCompact = true,
    this.color = Colors.grey,
    this.disabled = false,
  });

  @override
  State<DurationPill> createState() => _DurationPillState();
}

class _DurationPillState extends State<DurationPill> {
  final _durationFlyout = FlyoutController();
  static const _durations = [15, 30, 45, 60, 90, 120];

  @override
  void dispose() {
    _durationFlyout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _durationFlyout,
      child: GestureDetector(
        onTap: widget.disabled
            ? null
            : () => _durationFlyout.showFlyout(
                  builder: (ctx) => MenuFlyout(
                    items: [
                      MenuFlyoutItem(
                        text: Text(txt("duration"),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
                        leading: Icon(FluentIcons.clock,
                            size: 14, color: FluentTheme.of(ctx).inactiveColor),
                        onPressed: null,
                      ),
                      ..._durations.map((d) {
                        final sel = d == widget.item.duration;
                        return MenuFlyoutItem(
                          selected: sel,
                          leading: sel
                              ? Icon(FluentIcons.accept,
                                  size: 14, color: widget.color)
                              : null,
                          text: Text("$d ${txt("minutes")}"),
                          onPressed: () {
                            widget.onSet(d);
                            _durationFlyout.close();
                            setState(() {});
                          },
                        );
                      }),
                    ],
                  ),
                ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: widget.isCompact ? 5 : 8,
                vertical: widget.isCompact ? 2 : 8),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: FluentTheme.of(context)
                      .shadowColor
                      .withValues(alpha: 0.2),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                )
              ],
            ),
            child: Row(
              spacing: 5,
              children: [
                Icon(
                  FluentIcons.skype_circle_clock,
                  color: Colors.white,
                  size: widget.isCompact ? 11 : 18,
                ),
                Text(
                  "${widget.item.duration} ${txt(widget.isCompact ? "min" : "minutes")}",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
