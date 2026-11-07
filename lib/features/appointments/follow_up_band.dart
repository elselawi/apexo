import 'dart:async';

import 'package:apexo/common_widgets/contact_buttons.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/features/appointments/follow_up_card.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The day's follow-ups. A follow-up has no hour, so it cannot be a timeline
/// block or an agenda row and floats over the day instead.
class FollowUpBand extends StatefulWidget {
  const FollowUpBand({
    super.key,
    required this.followUps,
    this.onBook,
    this.draggable = false,
  });

  final List<FollowUpDue> followUps;

  /// Books the follow-up's visit; a null `at` means the follow-up's own day.
  final void Function(FollowUpDue followUp, {DateTime? at})? onBook;

  /// Whether the faces can be dragged onto a timeline.
  final bool draggable;

  @override
  State<FollowUpBand> createState() => _FollowUpBandState();
}

class _FollowUpBandState extends State<FollowUpBand> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    // An optional feature: nothing to draw until the clinic turns it on.
    if (!followUpsEnabled || widget.followUps.isEmpty) {
      return const SizedBox.shrink();
    }
    final today = dayOnly(DateTime.now());
    final onDay = <FollowUpDue>[];
    final overdue = <FollowUpDue>[];
    for (final followUp in widget.followUps) {
      (followUp.date.isBefore(today) ? overdue : onDay).add(followUp);
    }
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    final background = Color.alphaBlend(
      accent.withValues(alpha: dark ? 0.10 : 0.05),
      Color.alphaBlend(
        theme.cardColor,
        theme.resources.solidBackgroundFillColorBase,
      ),
    ).withValues(alpha: 0.97);

    return Container(
      key: WK.followUpBand,
      constraints: const BoxConstraints(maxWidth: 760),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.42 : 0.16),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: accent.withValues(alpha: dark ? 0.20 : 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      // One state at a time: hidden faces must not stay draggable or focusable.
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.bottomCenter,
            children: [...previous, if (current != null) current],
          ),
          child: _expanded
              ? KeyedSubtree(
                  key: const ValueKey('follow-ups-sheet'),
                  child: _sheet(context, onDay, overdue),
                )
              : KeyedSubtree(
                  key: const ValueKey('follow-ups-folded'),
                  child: _folded(context, onDay, overdue),
                ),
        ),
      ),
    );
  }

  /// Folded: who is due, and their faces.
  Widget _folded(
    BuildContext context,
    List<FollowUpDue> onDay,
    List<FollowUpDue> overdue,
  ) {
    const accent = kFollowUpAccent;
    final overduePatientIDs = {
      for (final followUp in overdue) followUp.patient.id,
    };
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 6, 6),
      child: Row(
        children: [
          _header(context),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 30,
            color: accent.withValues(alpha: 0.22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FaceStrip(
              followUps: [...onDay, ...overdue],
              faceBuilder: (followUp) => _face(
                followUp,
                overdue: overduePatientIDs.contains(followUp.patient.id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final dark = FluentTheme.of(context).brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    return Tooltip(
      message: txt('followUpsDue'),
      child: HoverButton(
        key: WK.followUpsBandToggle,
        onPressed: _toggle,
        builder: (context, states) {
          final hovered = states.contains(WidgetState.hovered);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsetsDirectional.fromSTEB(6, 3, 8, 3),
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: hovered ? (dark ? 0.24 : 0.13) : 0.0,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: dark ? 0.24 : 0.13),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(WindowsIcons.walk_solid,
                      size: 15, color: accent),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Txt(
                      txt('followUpsDue'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _count(context),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _count(BuildContext context) {
    const accent = kFollowUpAccent;
    final dark = FluentTheme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 0),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.26 : 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${widget.followUps.length}',
        style: const TextStyle(
          fontSize: 10,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }

  Widget _sheet(
    BuildContext context,
    List<FollowUpDue> onDay,
    List<FollowUpDue> overdue,
  ) {
    const accent = kFollowUpAccent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(9, 5, 9, 5),
          child: _header(context),
        ),
        Container(height: 1, color: accent.withValues(alpha: 0.18)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 232),
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 3, 6, 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final followUp in onDay) _row(followUp, overdue: false),
                if (overdue.isNotEmpty) _overdueDivider(),
                for (final followUp in overdue) _row(followUp, overdue: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _overdueDivider() {
    const accent = kFollowUpAccent;
    return Padding(
      key: WK.followUpsOverdueDivider,
      padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 10, 5),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: accent.withValues(alpha: 0.22),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
            child: Txt(
              txt('overdue'),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.red,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: accent.withValues(alpha: 0.22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(FollowUpDue followUp, {required bool overdue}) {
    final theme = FluentTheme.of(context);
    const accent = kFollowUpAccent;
    final canEdit = login.perm(Perm.appointments).some;
    final onBook = canEdit ? widget.onBook : null;
    final patient = followUp.patient;
    final note = patient.followUpNote;
    void openRecord() => unawaited(
          openPatient(patients.get(patient.id) ?? patient),
        );

    return Padding(
      key: WK.followUpRow(patient.id),
      padding: const EdgeInsetsDirectional.only(bottom: 2),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 3, 6, 3),
        child: Row(
          children: [
            _draggable(
              followUp,
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: openRecord,
                  child: ItemAvatar(item: patient, radius: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: openRecord,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        patient.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            theme.typography.bodyStrong?.copyWith(fontSize: 12),
                      ),
                      // With no note the label itself says "overdue", so the
                      // chip is only drawn beside a note.
                      Row(
                        children: [
                          if (overdue && note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 5),
                              child: Container(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    4, 0, 4, 0),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.13),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  txt('overdue'),
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    height: 1.6,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              note.isEmpty
                                  ? followUpRelativeLabel(followUp.date)
                                  : note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: note.isEmpty
                                    ? (overdue ? Colors.red : accent)
                                    : theme.typography.caption?.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (patient.phone.isNotEmpty)
              PhoneNumberButton(phoneNumbers: patient.phone),
            if (patient.email.isNotEmpty) ...[
              const SizedBox(width: 4),
              EmailButton(email: patient.email),
            ],
            if (onBook != null) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: txt('bookFollowUp'),
                child: IconButton(
                  style: darkIconButtonStyle(context),
                  onPressed: () => onBook(followUp),
                  icon: const Icon(WindowsIcons.subscription_add, size: 15),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Tooltip(
              message: txt('clearFollowUp'),
              child: IconButton(
                key: WK.followUpRemove,
                style: darkIconButtonStyle(context),
                onPressed: canEdit ? () => setFollowUp(patient.id, null) : null,
                icon: const Icon(WindowsIcons.delete, size: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _face(FollowUpDue followUp, {required bool overdue}) {
    final face = FollowUpCardTarget(
      key: WK.followUpAvatar(followUp.patient.id),
      patient: followUp.patient,
      date: followUp.date,
      onBook: widget.onBook == null || login.perm(Perm.appointments).none
          ? null
          : () => widget.onBook!(followUp),
      builder: (context, open) => _FollowUpFace(
        patient: followUp.patient,
        date: followUp.date,
        overdue: overdue,
        onTap: open,
      ),
    );
    return _draggable(followUp, face);
  }

  Widget _draggable(FollowUpDue followUp, Widget child) {
    if (!widget.draggable || login.perm(Perm.appointments).none) return child;
    return Draggable<FollowUpDue>(
      data: followUp,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _FollowUpDragFeedback(followUp: followUp),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}

class _FaceStrip extends StatefulWidget {
  const _FaceStrip({required this.followUps, required this.faceBuilder});

  final List<FollowUpDue> followUps;
  final Widget Function(FollowUpDue followUp) faceBuilder;

  @override
  State<_FaceStrip> createState() => _FaceStripState();
}

class _FaceStripState extends State<_FaceStrip> {
  final ScrollController _scroll = ScrollController();
  bool _atStart = true;
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant _FaceStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.followUps.length != widget.followUps.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_sync);
    _scroll.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final atStart = position.pixels <= 0.5;
    final atEnd = position.pixels >= position.maxScrollExtent - 0.5;
    if (atStart == _atStart && atEnd == _atEnd) return;
    setState(() {
      _atStart = atStart;
      _atEnd = atEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final fadeStart = !_atStart;
    final fadeEnd = !_atEnd;
    final strip = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      // Room so the scroll viewport never clips a face's hover ring.
      padding: const EdgeInsetsDirectional.fromSTEB(0, 2, 6, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final followUp in widget.followUps)
            Padding(
              key: ValueKey(followUp.patient.id),
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: widget.faceBuilder(followUp),
            ),
        ],
      ),
    );
    if (!fadeStart && !fadeEnd) return strip;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final width = bounds.width;
        final stop = width > 0 ? (22.0 / width).clamp(0.03, 0.25) : 0.1;
        return LinearGradient(
          begin: AlignmentDirectional.centerStart.resolve(direction),
          end: AlignmentDirectional.centerEnd.resolve(direction),
          colors: [
            fadeStart ? Colors.transparent : Colors.white,
            Colors.white,
            Colors.white,
            fadeEnd ? Colors.transparent : Colors.white,
          ],
          stops: [
            0.0,
            fadeStart ? stop : 0.0,
            fadeEnd ? 1.0 - stop : 1.0,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: strip,
    );
  }
}

class _FollowUpFace extends StatefulWidget {
  const _FollowUpFace({
    required this.patient,
    required this.date,
    required this.overdue,
    required this.onTap,
  });

  final Patient patient;
  final DateTime date;
  final bool overdue;
  final VoidCallback onTap;

  @override
  State<_FollowUpFace> createState() => _FollowUpFaceState();
}

class _FollowUpFaceState extends State<_FollowUpFace> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const accent = kFollowUpAccent;
    final ringColor = widget.overdue ? Colors.red : accent;
    return Tooltip(
      message: widget.patient.followUpNote.isEmpty
          ? '${widget.patient.title} · ${followUpRelativeLabel(widget.date)}'
          : '${widget.patient.title} · ${followUpRelativeLabel(widget.date)}\n'
              '${widget.patient.followUpNote}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            scale: _hovered ? 1.08 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: ringColor.withValues(alpha: _hovered ? 0.9 : 0.55),
                  width: _hovered ? 2 : 1.5,
                ),
                boxShadow: [
                  if (_hovered)
                    BoxShadow(
                      color: ringColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: ItemAvatar(item: widget.patient, radius: 14),
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowUpDragFeedback extends StatelessWidget {
  const _FollowUpDragFeedback({required this.followUp});

  final FollowUpDue followUp;

  @override
  Widget build(BuildContext context) {
    const accent = kFollowUpAccent;
    return Transform.translate(
      // A face is dragged from under the pointer, not by its corner.
      offset: const Offset(-14, -18),
      child: Directionality(
        textDirection: Directionality.of(context),
        child: DefaultTextStyle(
          style: const TextStyle(),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 10, 4),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ItemAvatar(item: followUp.patient, radius: 12),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    followUp.patient.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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
