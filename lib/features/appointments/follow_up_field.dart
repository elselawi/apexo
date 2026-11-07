import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show DF, globalSettings;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showDatePicker;

/// **Next follow-up** — the one field of a patient that looks forward.
///
/// A dentist finishes the notes and says "come back in two weeks, bring the
/// X-ray"; the row is therefore one thought, not three: the day (the band's own
/// date picker, so it behaves and reads exactly like a visit's), the intervals a
/// practice actually uses, which set that day in one click, and the note that
/// says what the visit is *for*.
///
/// The value belongs to the **patient**, so the two places this field is drawn —
/// the visit's operative record and the patient's own band — are two views of one
/// record. Both read the store, so a promise written in one shows in the other.
///
/// **The row edits a draft, and saving is an act.** A note is text, and text is
/// written a letter at a time: committing every keystroke to the patient would
/// fill the sync queue with half-typed words and leave a half-typed note behind
/// on any interruption. So the day, the note and their removal are gathered here
/// and written together by **Save**, with **Cancel** to drop the draft and
/// **Clear** to take the promise back — the same grammar, and the same buttons,
/// as the visit band's footer.
class FollowUpField extends StatefulWidget {
  const FollowUpField({
    super.key,
    required this.patientID,
    required this.anchor,
    this.draft,
    this.onChanged,
    this.enabled = true,
    this.onCollapse,
  });

  final String patientID;

  /// The day the presets count from.
  ///
  /// In a visit's operative record that is the **visit's** day — "come back in
  /// two weeks" means two weeks after the treatment, and notes are usually
  /// written the same day but not always. On the patient's own record it is
  /// today, because there is no visit to count from.
  final DateTime anchor;

  /// An optional draft owned by the surrounding visit session, so its Save can
  /// keep the patient-owned follow-up with the rest of the form.
  final FollowUpDraft? draft;

  /// Called after a write or a dropped draft, for a surface that has something
  /// of its own to say about it (the visit's dirty state, a band that folds).
  final VoidCallback? onChanged;

  /// Whether the row takes edits. Scheduling permission is also required;
  /// setting this to true never grants access on its own.
  final bool enabled;

  /// Folds the row again, for a surface that opened it on purpose — the
  /// patient's own band, whose folded button is the way in and must be the way
  /// back out. Null where the row is part of a form and is always shown.
  final VoidCallback? onCollapse;

  @override
  State<FollowUpField> createState() => _FollowUpFieldState();
}

class _FollowUpFieldState extends State<FollowUpField> {
  /// The type a chip wears, measured as well as drawn: [_longPresetsFit] has to
  /// weigh the very glyphs the wrap will lay out.
  static const _chipTextStyle = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
  );

  final TextEditingController _note = TextEditingController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// The promise as the store holds it — what the draft is measured against,
  /// and what Cancel goes back to.
  DateTime? _savedDay;
  String _savedNote = '';

  /// The promise as the row is editing it.
  DateTime? _day;

  bool _loaded = false;

  /// Guards the controller listener while this state is the one writing it.
  bool _writingNote = false;

  bool get _enabled => widget.enabled && login.perm(Perm.appointments).some;

  bool get _dirty {
    final day = _day;
    final saved = _savedDay;
    final sameDay = day == null
        ? saved == null
        : saved != null && sameCalendarDay(day, saved);
    return !sameDay || _note.text.trim() != _savedNote;
  }

  @override
  void initState() {
    super.initState();
    _pull(notify: false);
    widget.draft?.addListener(_onDraftChanged);
    _note.addListener(_onNoteTyped);
    // The promise can also change without this row: the day's band, the history
    // card, another window, a record synchronized down from the server.
    _subscriptions
      ..add(patients.observableMap.stream.listen((_) => _pull()))
      ..add(followUpRevision.stream.listen((_) => _pull()));
  }

  @override
  void didUpdateWidget(covariant FollowUpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientID != widget.patientID ||
        oldWidget.draft != widget.draft) {
      oldWidget.draft?.removeListener(_onDraftChanged);
      _loaded = false;
      _savedDay = null;
      _savedNote = '';
      _day = null;
      _setNoteText('');
      // A rebuild is already on its way; asking for another one is not.
      _pull(notify: false);
      widget.draft?.addListener(_onDraftChanged);
    }
  }

  @override
  void dispose() {
    widget.draft?.removeListener(_onDraftChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _note.dispose();
    super.dispose();
  }

  /// Takes the stored promise in as the baseline, and — while the draft carries
  /// nothing of the user's — as the draft too.
  void _pull({bool notify = true}) {
    final patient = patients.get(widget.patientID);
    final day = patient?.followUpDay;
    final note = patient?.followUpNote ?? '';
    final saved = _savedDay;
    final sameDay = day == null
        ? saved == null
        : saved != null && sameCalendarDay(day, saved);
    if (_loaded && sameDay && note == _savedNote) return;

    // Whether the user has work in the draft is measured against the baseline
    // this pull is about to replace, not the one it brings: a clean draft
    // follows the store, a draft in flight keeps what was typed into it.
    final pendingDraft = widget.draft;
    final restoreDraft = !_loaded &&
        pendingDraft?.isDirty == true &&
        pendingDraft?.patientID == widget.patientID;
    final dirty = _dirty;
    _savedDay = day;
    _savedNote = note;
    if (!_loaded || !dirty) {
      if (restoreDraft) {
        _day = pendingDraft!.day;
        _setNoteText(pendingDraft.note);
      } else {
        _day = day;
        _setNoteText(note);
      }
    }
    _loaded = true;
    _syncDraft();
    if (notify && mounted) setState(() {});
  }

  /// Re-reads the promise as it stands **now** — the write is synchronous, so
  /// the baseline never lags a frame behind the value that was just written.
  void _adoptStored() {
    final patient = patients.get(widget.patientID);
    setState(() {
      _savedDay = patient?.followUpDay;
      _savedNote = patient?.followUpNote ?? '';
      _day = _savedDay;
      _setNoteText(_savedNote);
    });
    _syncDraft();
  }

  void _setNoteText(String text) {
    if (_note.text == text) return;
    _writingNote = true;
    _note.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _writingNote = false;
  }

  void _onNoteTyped() {
    if (_writingNote || !mounted) return;
    setState(() {});
    _syncDraft();
  }

  void _onDraftChanged() {
    final draft = widget.draft;
    if (draft == null || !mounted) return;
    if (draft.isDirty && draft.patientID != widget.patientID) return;
    final patient = patients.get(widget.patientID);
    final day = draft.isDirty ? draft.day : patient?.followUpDay;
    final note = draft.isDirty ? draft.note : patient?.followUpNote ?? '';
    final savedDay = draft.isDirty ? _savedDay : patient?.followUpDay;
    final savedNote = draft.isDirty ? _savedNote : patient?.followUpNote ?? '';
    if (_day == day &&
        _note.text == note &&
        _savedDay == savedDay &&
        _savedNote == savedNote) {
      return;
    }
    setState(() {
      _savedDay = savedDay;
      _savedNote = savedNote;
      _day = day;
      _setNoteText(note);
    });
  }

  void _save() {
    if (!_enabled || !_dirty) return;
    setFollowUp(widget.patientID, _day, note: _note.text);
    _adoptStored();
    widget.onChanged?.call();
  }

  void _cancel() {
    if (!_dirty) return;
    setState(() {
      _day = _savedDay;
      _setNoteText(_savedNote);
    });
    _syncDraft();
    widget.onChanged?.call();
  }

  /// Takes the promise back at once: the same act as the day's band's trash, so
  /// it can never be left waiting on a Save the user forgot to press.
  void _clear() {
    if (!_enabled) return;
    setFollowUp(widget.patientID, null);
    _adoptStored();
    widget.onChanged?.call();
  }

  Future<void> _pickDate(DateTime from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from,
      firstDate: DateTime(from.year - 1),
      lastDate: DateTime(from.year + 10),
    );
    if (picked != null && mounted) _setDay(picked);
  }

  void _setDay(DateTime day) {
    setState(() => _day = dayOnly(day));
    _syncDraft();
  }

  void _syncDraft() {
    final draft = widget.draft;
    if (draft == null) return;
    if (_dirty) {
      draft.stage(
        patientID: widget.patientID,
        day: _day,
        note: _note.text,
      );
    } else {
      draft.clear(forPatientID: widget.patientID);
    }
  }

  /// A preset's own day, in the user's language and calendar — the tooltip that
  /// explains what "3m" will actually pick.
  String _dayLabel(DateTime day) =>
      DF.commonDate(day).replaceAll('📅 ', '').trim();

  @override
  Widget build(BuildContext context) => MStreamBuilder<Object?>(
        streams: [
          locale.selected.stream,
          // Optional feature: the row leaves the moment the clinic turns it off.
          globalSettings.observableMap.stream,
        ],
        builder: (context, _) =>
            followUpsEnabled ? _buildField(context) : const SizedBox.shrink(),
      );

  Widget _buildField(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    final anchor = dayOnly(widget.anchor);
    final day = _day;
    final dirty = _dirty;

    return Container(
      key: WK.fieldAppointmentFollowUp,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: day != null ? (dark ? 0.13 : 0.06) : 0.03,
        ),
        borderRadius: BorderRadius.circular(8),
        // A draft in flight is the one state that must not be missed: the row
        // stays outlined in the follow-up colour until it is saved or dropped.
        border: Border.all(
          color: accent.withValues(
            alpha: dirty ? 0.62 : (day != null ? 0.42 : 0.20),
          ),
          width: dirty ? 1.3 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(WindowsIcons.walk_solid,
                        size: 11, color: accent),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Txt(
                        txt('nextFollowUp'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.caption?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: day != null ? accent : theme.inactiveColor,
                        ),
                      ),
                    ),
                    if (day != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding:
                              const EdgeInsetsDirectional.fromSTEB(5, 1, 5, 1),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: dark ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Txt(
                            followUpRelativeLabel(day),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (widget.onCollapse != null && _savedDay == null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: Tooltip(
                          message: txt('close'),
                          child: HoverButton(
                            key: WK.followUpCollapse,
                            onPressed: widget.onCollapse,
                            focusEnabled: false,
                            builder: (context, states) => Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: states.contains(WidgetState.hovered)
                                    ? accent.withValues(
                                        alpha: dark ? 0.26 : 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Icon(
                                FluentIcons.chevron_up,
                                size: 9,
                                color: accent.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                // Either a day is set — and the row is that day and what the
                // visit is for — or none is, and the row offers the intervals
                // that set one. The presets have done their job once a date is
                // chosen, so they step aside instead of crowding the answer.
                if (day != null) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: DateTimePicker(
                        key: WK.fieldAppointmentFollowUpDate,
                        initValue: day,
                        showButton: false,
                        enabled: _enabled,
                        textAlignment: AlignmentDirectional.centerStart,
                        textStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: dark ? Colors.white : accent,
                        ),
                        onChange: _setDay,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  _noteField(context),
                ] else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // "10d" is a compromise, not a preference: a row wide
                      // enough to say "10 days" says it. Measured rather than
                      // guessed — the same chips are 190px in English and 260
                      // in Arabic.
                      final long = _longPresetsFit(
                        context,
                        constraints.maxWidth,
                        showDateChip: true,
                      );
                      return Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _chip(
                            key: WK.fieldAppointmentFollowUpDate,
                            label: txt('chooseFollowUpDate'),
                            icon: WindowsIcons.calendar,
                            onPressed:
                                _enabled ? () => _pickDate(anchor) : null,
                          ),
                          for (final preset in kFollowUpPresets)
                            Tooltip(
                              message: _dayLabel(preset.from(anchor)),
                              child: _chip(
                                key: WK.followUpPreset(preset.label),
                                label: long ? preset.longLabel : preset.label,
                                onPressed: _enabled
                                    ? () => _setDay(preset.from(anchor))
                                    : null,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  /// Whether every interval, spelled out, fits on one line of the width the row
  /// was given — the date chip included, since it is the first thing a dentist
  /// reaches for.
  bool _longPresetsFit(
    BuildContext context,
    double maxWidth, {
    required bool showDateChip,
  }) {
    if (!maxWidth.isFinite) return true;
    final labels = <String>[
      if (showDateChip) txt('chooseFollowUpDate'),
      for (final preset in kFollowUpPresets) preset.longLabel,
    ];
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var total = 0.0;
    for (var i = 0; i < labels.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: labels[i], style: _chipTextStyle),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      // The chip's padding and border — plus the calendar a chip with an icon
      // carries — and the gap the wrap puts between two of them.
      total += painter.width + (i == 0 && showDateChip ? 32 : 18);
      painter.dispose();
      if (i > 0) total += 4;
    }
    return total <= maxWidth;
  }

  /// What the visit is for, as the patient will hear it when the clinic calls.
  ///
  /// Borderless inside the row, so the day above it and the note under it read
  /// as one thought; the mic-less Cupertino field is what the rest of the app
  /// uses for an inline line of text.
  Widget _noteField(BuildContext context) {
    final theme = FluentTheme.of(context);
    const accent = kFollowUpAccent;
    return CupertinoTextField(
      key: WK.fieldFollowUpNote,
      controller: _note,
      enabled: _enabled,
      maxLines: 1,
      placeholder: txt('followUpNotePlaceholder'),
      padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 8, 5),
      style: TextStyle(
        fontSize: 11,
        height: 1.35,
        color: theme.typography.body?.color,
      ),
      placeholderStyle: TextStyle(
        fontSize: 11,
        color: theme.inactiveColor,
      ),
      cursorColor: accent,
      prefix: const Padding(
        padding: EdgeInsetsDirectional.only(start: 8),
        child: Icon(WindowsIcons.quick_note, size: 13, color: accent),
      ),
      // The note is one thought: Enter finishes the row the way Save does.
      onSubmitted: (_) => _save(),
    );
  }

  /// The row's actions, in the visit band's own grammar: a standard button per
  /// act, and the one that keeps the draft filled in the follow-up colour.
  ///
  /// Silent until there is something to do — a promise to take back, or a draft
  /// to keep — so an empty row is not a row of dead buttons.
  Widget _footer(BuildContext context) {
    const accent = kFollowUpAccent;
    final theme = FluentTheme.of(context);
    final dirty = _dirty;
    final removable = _savedDay != null;
    if (!dirty && !removable) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 8, 6),
      decoration: BoxDecoration(
        // A footer of its own, as on the visit band: the eye reads "actions",
        // not one more row of the form.
        color:
            Color.alphaBlend(accent.withValues(alpha: 0.08), theme.menuColor),
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.22))),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          if (removable)
            Button(
              key: WK.clearFollowUp,
              onPressed: _enabled ? _clear : null,
              child: ButtonContent(
                WindowsIcons.delete,
                txt('delete'),
                size: 11,
              ),
            ),
          if (dirty) ...[
            Button(
              key: WK.followUpCancel,
              onPressed: _cancel,
              child: ButtonContent(
                WindowsIcons.chrome_close,
                txt('cancel'),
                size: 11,
              ),
            ),
            FilledButton(
              key: WK.followUpSave,
              onPressed: _enabled ? _save : null,
              child: ButtonContent(WindowsIcons.save, txt('save'), size: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
    IconData? icon,
  }) {
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    return HoverButton(
      key: key,
      onPressed: onPressed,
      focusEnabled: false,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) && onPressed != null;
        final foreground = onPressed != null
            ? accent
            : theme.inactiveColor.withValues(alpha: 0.6);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          height: 26,
          padding: EdgeInsetsDirectional.fromSTEB(
            icon == null ? 8 : 6,
            0,
            8,
            0,
          ),
          decoration: BoxDecoration(
            color: accent.withValues(
              alpha: hovered ? (dark ? 0.24 : 0.14) : 0.06,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: accent.withValues(alpha: hovered ? 0.5 : 0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 11, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                maxLines: 1,
                style: _chipTextStyle.copyWith(color: foreground),
              ),
            ],
          ),
        );
      },
    );
  }
}
