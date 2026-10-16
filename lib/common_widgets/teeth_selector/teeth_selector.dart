import 'package:apexo/common_widgets/teeth_selector/opg_dental_chart.dart';
import 'package:apexo/common_widgets/teeth_selector/tooth_history.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:fluent_ui/fluent_ui.dart';

class TeethSelector extends StatefulWidget {
  const TeethSelector({
    super.key,
    this.currentNotes = const {},
    this.oldNotes = const {},
    this.extraNotes = const {},
    this.leftString = "Left",
    this.rightString = "Right",
    this.textStyle,
    this.tooltipTextStyle,
    this.showPrimary = false,
    this.history = const [],
    this.historyTitle = 'toothHistory',
    this.onOpenAppointment,
    required this.notation,
    required this.onNote,
    this.onExtraNote,
    required this.type,
  });
  final Map<String, String> currentNotes;
  final Map<String, String> oldNotes;
  final Map<String, String> extraNotes;
  final String leftString;
  final String rightString;
  final void Function(String tooth, String? note) onNote;
  final void Function(String tooth, String extraNote)? onExtraNote;
  final String Function(String isoString) notation;
  final TextStyle? textStyle;
  final TextStyle? tooltipTextStyle;
  final bool showPrimary;
  final List<ToothHistory> history;
  final String historyTitle;
  final ValueChanged<String>? onOpenAppointment;
  final StateType type;

  @override
  State<TeethSelector> createState() => _TeethSelectorState();
}

class _TeethSelectorState extends State<TeethSelector> {
  bool showPermanent = true;
  bool showPrimary = false;
  late final Map<String, String> _extraNotes;

  @override
  void initState() {
    _extraNotes = Map<String, String>.from(widget.extraNotes);
    // For "other" treatments, pre-fill the extra note with the custom text
    for (final entry in widget.currentNotes.entries) {
      if (txOptions.where((x) => x.label == entry.value).isEmpty &&
          entry.value.isNotEmpty &&
          !_extraNotes.containsKey(entry.key)) {
        _extraNotes[entry.key] = entry.value;
      }
    }
    showPrimary = widget.showPrimary ||
        [...widget.currentNotes.keys, ...widget.oldNotes.keys].any((iso) =>
            iso.startsWith("5") ||
            iso.startsWith("6") ||
            iso.startsWith("7") ||
            iso.startsWith("8"));
    super.initState();
  }

  @override
  void didUpdateWidget(covariant TeethSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _extraNotes
      ..clear()
      ..addAll(widget.extraNotes);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < kOpgViewportMinWidth;
    // A narrow chart only has room for one dentition, so there the switches
    // read as a single choice between the permanent teeth and the primary ones.
    final primaryShown = compact ? showPrimary && !showPermanent : showPrimary;
    return OpgDentalChart(
      isCompactArch: compact,
      currentNotes: widget.currentNotes,
      oldNotes: widget.oldNotes,
      extraNotes: _extraNotes,
      leftString: widget.leftString,
      rightString: widget.rightString,
      textStyle: widget.textStyle,
      showPermanent: compact ? !primaryShown : showPermanent,
      showPrimary: compact ? primaryShown : showPrimary,
      onShowPermanentChanged: (checked) => setState(() {
        // One dentition is on show at a time: picking this one drops the other,
        // and switching this one off hands the chart to the other.
        showPermanent = checked;
        showPrimary = !checked;
      }),
      onShowPrimaryChanged: (checked) => setState(() {
        showPrimary = checked;
        showPermanent = !checked;
      }),
      history: widget.history,
      historyTitle: widget.historyTitle,
      onOpenAppointment: widget.onOpenAppointment,
      notation: widget.notation,
      type: widget.type,
      onNote: (iso, tooth) {
        setState(() {
          widget.onNote(iso, tooth);
          if (tooth == null) _extraNotes.remove(iso);
        });
      },
      onExtraNote: (iso, text) {
        setState(() => _extraNotes[iso] = text);
        widget.onExtraNote?.call(iso, text);
      },
    );
  }
}
