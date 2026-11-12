import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show DF, globalSettings;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/ui/workspace/unsaved_dot.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showDatePicker;

/// The patient's next follow-up: one record shared by the visit's record and the
/// patient's band, edited in a draft so a half-typed note never reaches the store.
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

  /// The day presets count from: the visit's day in a visit's record, today on
  /// the patient's own band, where there is no visit to count from.
  final DateTime anchor;

  /// Optional draft owned by the surrounding visit session, saved with its form.
  final FollowUpDraft? draft;

  /// Called after a write or a dropped draft, so the owner can refresh its state.
  final VoidCallback? onChanged;

  /// Whether the row takes edits; appointment permission is required as well.
  final bool enabled;

  /// Folds the row again for a surface that opened it; null where it is always shown.
  final VoidCallback? onCollapse;

  @override
  State<FollowUpField> createState() => _FollowUpFieldState();
}

class _FollowUpFieldState extends State<FollowUpField> {
  // Label style of a chip; [_longPresetsFit] measures the glyphs with it.
  static const _chipTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  final TextEditingController _note = TextEditingController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // The stored promise: what the draft is measured against and Cancel restores.
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
    // The promise can change elsewhere: another window, or a record synced down.
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

  // Takes the stored promise as baseline, and as the draft while that draft is untouched.
  void _pull({bool notify = true}) {
    final patient = patients.get(widget.patientID);
    final day = patient?.followUpDay;
    final note = patient?.followUpNote ?? '';
    final saved = _savedDay;
    final sameDay = day == null
        ? saved == null
        : saved != null && sameCalendarDay(day, saved);
    if (_loaded && sameDay && note == _savedNote) return;

    // Dirty is measured against the baseline this pull is replacing, not the one
    // it brings: a clean draft follows the store, one in flight keeps the typing.
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

  // Re-reads the promise now; the write is synchronous, so the baseline cannot lag.
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

  // Clears at once rather than staging, so it cannot wait on a Save the user forgets.
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

  // A preset's own day, for the tooltip that shows what "3m" will pick.
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
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 8),
            decoration: topBarDecoration(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (_dirty) const UnsavedDot(),
                        const Icon(WindowsIcons.walk_solid,
                            size: 16, color: accent),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Txt(
                            txt('nextFollowUp'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                        if (day != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  5, 1, 5, 1),
                              decoration: BoxDecoration(
                                color: accent.withValues(
                                    alpha: dark ? 0.22 : 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Txt(
                                followUpRelativeLabel(day),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.onCollapse != null && _savedDay == null) ...[
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
                                size: 12,
                                color: accent.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ),
                      )
                    ],
                  ],
                ),
                const SizedBox(height: 5),
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
                          fontSize: 13,
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
                      // Long labels only if the row fits them: chip widths differ
                      // by locale, so they are measured, not guessed.
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
                          _chip(
                            key: WK.fieldAppointmentFollowUpDate,
                            label: txt('chooseFollowUpDate'),
                            icon: WindowsIcons.calendar,
                            onPressed:
                                _enabled ? () => _pickDate(anchor) : null,
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

  // Whether the spelled-out presets, date chip included, fit on one line.
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
      // Chip padding and border, plus the room the date chip's calendar icon
      // needs; the extra 4 is the gap the wrap puts between two chips.
      total += painter.width + (i == 0 && showDateChip ? 32 : 18);
      painter.dispose();
      if (i > 0) total += 4;
    }
    return total <= maxWidth;
  }

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
        fontSize: 13,
        height: 1.35,
        color: theme.typography.body?.color,
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

  Widget _footer(BuildContext context) {
    const accent = kFollowUpAccent;
    final theme = FluentTheme.of(context);
    final dirty = _dirty;
    final removable = _savedDay != null;
    if (!dirty && !removable) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 8, 6),
      decoration: BoxDecoration(
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
            IconButton(
              key: WK.clearFollowUp,
              onPressed: _enabled ? _clear : null,
              icon: ButtonContent(
                WindowsIcons.delete,
                txt('delete'),
                size: 13,
              ),
            ),
          if (dirty) ...[
            IconButton(
              key: WK.followUpCancel,
              onPressed: _cancel,
              icon: ButtonContent(
                WindowsIcons.chrome_close,
                txt('cancel'),
                size: 13,
              ),
            ),
            IconButton(
              key: WK.followUpSave,
              onPressed: _enabled ? _save : null,
              icon: ButtonContent(WindowsIcons.save, txt('save'), size: 13),
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
