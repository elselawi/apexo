import 'dart:async';

import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_accent.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/window_attachments.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// What a visit's chart carries under its teeth.
///
/// Two states, one widget, because they are the same question — *what else does
/// this visit have?* — answered for two places:
///
/// * **Beside the patient** the visit's chart is its workspace, so its **post-op
///   record** is pinned at the chart's foot (floating over it on narrow screens):
///   the notes, the prescriptions and the
///   money are part of the visit, not a window to open. Its labwork order and
///   photos hang off that card — and off the visit's band, which draws the same
///   attachment tray — so either surface is one click from them.
/// * **On its own** (a patient this account may not see, or one that is gone)
///   there is no band, no patient panel and no chart to hang things off, so the
///   footer is the way to the visit's other windows: the same attachment chips,
///   opening standalone windows.
class AppointmentChartFooter extends StatelessWidget {
  const AppointmentChartFooter({
    super.key,
    required this.appointment,
    required this.session,
    this.attached = false,
  });

  final Appointment appointment;
  final DentalChartSession session;

  /// Whether the visit is drawn beside its patient — the chart is then its
  /// workspace, and the post-op record belongs here.
  final bool attached;

  @override
  Widget build(BuildContext context) {
    final visitSession = appointmentSessions.get(appointment.id);
    return MStreamBuilder<Object?>(
      streams: [
        PanelsManager.active.stream,
        appointments.observableMap.stream,
        locale.selected.stream,
        if (visitSession != null) visitSession.hasUnsavedChanges.stream,
      ],
      builder: (context, _) {
        // The panel that carries this visit, if one does. With no panel behind it
        // the chart is standing on its own, and its footer opens windows instead.
        final panel = PanelsManager.active()
            .where((panel) => identical(panel.attached, visitSession))
            .firstOrNull;
        if (attached && panel != null) {
          // The post-op record is a **card under the chart**, not another row of
          // the chart: its depth, its tint and its little tail say it is about
          // these teeth without pretending to be part of the teeth editor (the
          // design brief). Capped so a long note never eats the chart.
          const accent = PanelAccents.appointment;
          final theme = FluentTheme.of(context);
          final background = Color.alphaBlend(
            accent.withValues(alpha: 0.035),
            Color.alphaBlend(
              theme.cardColor,
              theme.resources.solidBackgroundFillColorBase,
            ),
          ).withValues(alpha: 0.96);
          final border = accent.withValues(alpha: 0.30);
          // The visit's parts — its labwork order and photos — as the band lists
          // them: one list, drawn on both surfaces.
          final attachments = <PanelWindow>[
            for (final window in visitSession?.windows ?? const <PanelWindow>[])
              if (window.attachedTo == PanelWindow.bandAttachment) window,
          ];
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            // The tail is drawn above the card, in the gap this padding leaves
            // between the teeth and their post-op record.
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.10),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    // The card's own padding belongs to its two parts — the
                    // fields' and the attachment tray's — so the tray's divider
                    // runs the width of the card.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Only the fields scroll, and only when the note is
                        // long: the attachments stay at the card's foot where
                        // they can be seen without scrolling for them.
                        if (canViewPostOp(appointment))
                          Flexible(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    8, 6, 8, 8),
                                child: AppointmentOperativeForm(
                                  // A different visit is a different post-op
                                  // record: its fields must never be the previous
                                  // visit's values behind a new title.
                                  key: ValueKey(
                                      'visit-operative-${appointment.id}'),
                                  appointment,
                                  onEdited: visitSession?.refreshDirty,
                                ),
                              ),
                            ),
                          ),
                        StreamBuilder<int>(
                          stream: panel.workspace.revision.stream,
                          builder: (context, _) =>
                              _attachmentsOf(panel, attachments) ??
                              const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -5,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: CustomPaint(
                        size: const Size(14, 6),
                        painter: _ChartCardTail(
                          background: background,
                          border: border,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final windows = <PanelWindow>[
          for (final entry in appointmentWindows(appointment))
            if (entry != AppointmentWindow.dentalChart)
              PanelWindow(
                id: entry.id,
                title: entry.titleKey,
                icon: entry.icon,
                onlyIfSaved: entry == AppointmentWindow.gallery,
                body: const SizedBox.shrink(),
              ),
        ];
        return StreamBuilder<int>(
          stream: panel?.workspace.revision.stream,
          builder: (context, _) => WindowAttachments(
            windows: windows,
            accent: PanelAccents.appointment,
            marker: false,
            keyForWindow: (window) =>
                ValueKey('chart-tool-${session.id}-${window.id}'),
            isOpen: (window) => _standalone(window) != null,
            enabled: (window) =>
                !window.onlyIfSaved || appointments.get(appointment.id) != null,
            onToggle: (window) => _toggle(window),
          ),
        );
      },
    );
  }

  /// The visit's window standing on its own, if it is up.
  FloatingWindow? _standalone(PanelWindow window) => WindowsManager.open()
      .where((floating) =>
          floating.window.id == window.id &&
          floating.scope == 'appointment:${appointment.id}')
      .firstOrNull;

  /// The visit's attachments at the foot of the post-op card: the same tray the
  /// band draws, so the bubble inside the chart offers them too.
  ///
  /// Their windows live in the row's attached slot, exactly as the band's tray
  /// puts them there — one record, one place its editors open.
  Widget? _attachmentsOf(Panel panel, List<PanelWindow> windows) {
    if (windows.isEmpty) return null;
    return WindowAttachments(
      key: WK.visitChartAttachments,
      windows: windows,
      accent: PanelAccents.appointment,
      // The card's own padding holds the fields off its edges; the tray only adds
      // the divider above it.
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 7),
      keyForWindow: (window) =>
          WK.attachmentToggle(window.id, owner: kDentalChartWindowId),
      isOpen: (window) =>
          panel.workspace.isOpen(window.id, slot: kAttachedSlot),
      enabled: (window) =>
          !window.onlyIfSaved || appointments.get(appointment.id) != null,
      onToggle: (window) =>
          panel.workspace.toggle(window.id, slot: kAttachedSlot),
    );
  }

  /// Shows or hides one of the visit's tools, wherever the visit is drawn.
  ///
  /// Beside the patient the visit has no window of its own to put these in — the
  /// band's tray and this card's draw the same windows — so this path is only the
  /// standalone one.
  void _toggle(PanelWindow window) {
    final floating = _standalone(window);
    if (floating != null) {
      WindowsManager.close(floating);
      return;
    }
    final entry =
        appointmentWindows(appointment).firstWhere((e) => e.id == window.id);
    unawaited(openAppointment(appointment, entry));
  }
}

/// The small tail on top of the post-op card, pointing up at the teeth it
/// describes — the same gesture as the visit band's tail under the patient name.
class _ChartCardTail extends CustomPainter {
  const _ChartCardTail({required this.background, required this.border});

  final Color background;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final tail = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(tail, Paint()..color = background);
    final edge = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(
      edge,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ChartCardTail oldDelegate) =>
      oldDelegate.background != background || oldDelegate.border != border;
}
