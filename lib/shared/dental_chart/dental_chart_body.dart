import 'package:apexo/common_widgets/teeth_selector/opg_dental_chart.dart';
import 'package:apexo/common_widgets/teeth_selector/teeth_selector.dart';
import 'package:apexo/shared/dental_chart/dental_chart_overlay.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The teeth of a [DentalChartSession], drawn both in the floating window and in
/// a small-screen panel; scope transitions animate only the teeth, not the chrome.
class DentalChartBody extends StatelessWidget {
  const DentalChartBody({super.key, required this.session, this.overlay});

  final DentalChartSession session;

  /// A floating card over the teeth, rather than a separate window surface.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    // Notes are edited in place, and a panel's store stream cannot announce an
    // edit to a draft that is not stored yet, so listen to the session itself.
    return StreamBuilder<int>(
      stream: session.revision.stream,
      builder: (context, _) {
        // Noted teeth are already drawn as current, so drop them from old notes
        // to avoid doubling them.
        final oldNotes = Map<String, String>.from(session.oldNotes())
          ..removeWhere((iso, _) => session.teeth.containsKey(iso));

        final chart = TeethSelector(
          type: session.type,
          // session.id is the record scope (`patient:<id>` / `appointment:<id>`),
          // which is what tints the chart like the panel or window it sits in.
          tint: PanelAccents.ofScope(session.id),
          fillCompactHeight: overlay != null,
          historyTitle: session.historyTitle,
          history: session.history(),
          onOpenAppointment: session.onOpenAppointment,
          onNote: (iso, note) {
            if (note != null) {
              session.teeth[iso] = note;
            } else {
              session.teeth.remove(iso);
              session.extraNotes.remove(iso);
            }
            session.changed();
          },
          onExtraNote: (iso, extra) {
            session.extraNotes[iso] = extra;
            session.changed();
          },
          extraNotes: session.extraNotes,
          notation: (isoString) => isoToTextualNotation(isoString),
          rightString: txt('right'),
          leftString: txt('left'),
          currentNotes: session.teeth,
          oldNotes: oldNotes,
          showPrimary: session.showPrimary,
        );
        final direction = session.navigationDirection *
            (Directionality.of(context) == TextDirection.rtl ? -1 : 1);
        final animatedChart = ClipRect(
          child: TweenAnimationBuilder<double>(
            key: ObjectKey(session),
            tween: Tween(begin: 0, end: 1),
            duration: direction == 0 || MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: FractionalTranslation(
                key: const ValueKey('dental-chart-scope-slide'),
                translation: Offset(direction * 0.06 * (1 - value), 0),
                child: child,
              ),
            ),
            child: chart,
          ),
        );
        final floatingCard = overlay;
        final chartBody = floatingCard == null
            ? animatedChart
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= kOpgViewportMinWidth) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(child: animatedChart),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight,
                          ),
                          child: SingleChildScrollView(child: floatingCard),
                        ),
                      ],
                    );
                  }
                  return DentalChartOverlay(
                    chart: animatedChart,
                    card: floatingCard,
                  );
                },
              );
        final header = session.header?.call(session);
        if (header == null) return chartBody;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            if (floatingCard == null) chartBody else Flexible(child: chartBody),
          ],
        );
      },
    );
  }
}
