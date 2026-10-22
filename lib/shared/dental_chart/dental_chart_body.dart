import 'package:apexo/common_widgets/teeth_selector/teeth_selector.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The teeth of a [DentalChartSession], with everything editing them needs.
///
/// Shared by the two places a chart is drawn — the floating window, and the
/// section a panel shows in place of it on a small screen — so both always show
/// the same chart and write to the same draft.
class DentalChartBody extends StatelessWidget {
  const DentalChartBody({super.key, required this.session});

  final DentalChartSession session;

  @override
  Widget build(BuildContext context) {
    // Notes are edited in place, so the chart listens to its own session: a
    // panel's store stream cannot announce an edit to a draft that is not
    // stored yet.
    return StreamBuilder<int>(
      stream: session.revision.stream,
      builder: (context, _) {
        // Noted teeth are already drawn from the current notes; showing them
        // again as "old" notes would double every one of them.
        final oldNotes = Map<String, String>.from(session.oldNotes())
          ..removeWhere((iso, _) => session.teeth.containsKey(iso));

        return TeethSelector(
          type: session.type,
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
      },
    );
  }
}
