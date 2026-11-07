import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PatientVisitsButton extends StatelessWidget {
  const PatientVisitsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  // below this the header has no room for the label, so only the glyph fits.
  static const double _labelBreakpoint = 1000;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _labelBreakpoint;
    return Tooltip(
      message: txt('allAppointments'),
      child: wide
          ? Button(
              key: WK.chartAllAppointments,
              onPressed: onPressed,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsetsDirectional.fromSTEB(8, 3, 10, 3),
                ),
                backgroundColor: WidgetStatePropertyAll(
                  Color.alphaBlend(
                    FluentTheme.of(context).accentColor.withValues(alpha: 0.08),
                    FluentTheme.of(context).cardColor,
                  ),
                ),
              ),
              child: ButtonContent(
                WindowsIcons.calendar,
                txt('allAppointments'),
                size: 11,
              ),
            )
          : IconButton(
              key: WK.chartAllAppointments,
              icon: const Icon(WindowsIcons.calendar, size: 14),
              onPressed: onPressed,
            ),
    );
  }
}
