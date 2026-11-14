import 'dart:async';

import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show globalSettings;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/shared/dental_chart/dental_chart_overlay.dart';
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

/// Drawn under the chart's teeth: attached to the visit's panel it pins the post-op
/// record; otherwise it opens the visit's other windows.
class AppointmentChartFooter extends StatelessWidget {
  const AppointmentChartFooter({
    super.key,
    required this.appointment,
    required this.session,
    this.attached = false,
  });

  final Appointment appointment;
  final DentalChartSession session;

  /// Whether the visit is drawn beside its patient, so the post-op record belongs here.
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
        // The panel showing this visit; with none, the chart stands alone and
        // the footer opens windows.
        final panel = PanelsManager.active()
            .where((panel) => identical(panel.attached, visitSession))
            .firstOrNull;
        if (attached && panel != null) {
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
          // Floating on the chart, that surface owns how tall the card may
          // grow; anywhere else the card keeps its resting ceiling.
          final floating = DentalChartCardScope.maybeOf(context);
          // The visit's attachments, the same ones the visit band's tray lists.
          final attachments = <PanelWindow>[
            for (final window in visitSession?.windows ?? const <PanelWindow>[])
              if (window.attachedTo == PanelWindow.bandAttachment) window,
          ];
          final card = Padding(
            // The tail sits in this padding's top gap, above the card.
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
                  // Padding lives on the two parts so the tray's divider spans the card.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Only the fields scroll; the attachments stay visible at the card's foot.
                      if (canViewPostOp(appointment))
                        Flexible(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  8, 6, 8, 8),
                              child: AppointmentOperativeForm(
                                // Keyed by visit so the fields never keep the previous visit's values.
                                key: ValueKey(
                                    'visit-operative-${appointment.id}'),
                                appointment,
                                followUpDraft: visitSession?.followUpDraft,
                                onEdited: visitSession?.refreshDirty,
                                // The card's foot hosts it, beside the tools.
                                dictation: false,
                              ),
                            ),
                          ),
                        ),
                      StreamBuilder<int>(
                        stream: panel.workspace.revision.stream,
                        builder: (context, _) => _visitTools(
                          panel,
                          attachments,
                          onEdited: visitSession?.refreshDirty,
                        ),
                      ),
                    ],
                  ),
                ),
                // The tail points at the teeth while the card is a bubble; a
                // card that has taken the surface is a sheet and loses it.
                Positioned(
                  top: -5,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: floating == null
                        ? _tail(background, border)
                        : FadeTransition(
                            opacity: ReverseAnimation(floating.expansion),
                            child: _tail(background, border),
                          ),
                  ),
                ),
              ],
            ),
          );
          return floating == null
              ? ConstrainedBox(
                  constraints: const BoxConstraints(
                      maxHeight: kDentalChartCardMaxHeight),
                  child: card,
                )
              : card;
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

  /// The little pointer from the card up to the teeth.
  Widget _tail(Color background, Color border) => CustomPaint(
        size: const Size(14, 6),
        painter: _ChartCardTail(background: background, border: border),
      );

  // The band's tray again, plus the dictation that fills the record: same
  // windows, same attached slot, so each editor opens in one place.
  Widget _visitTools(
    Panel panel,
    List<PanelWindow> windows, {
    VoidCallback? onEdited,
  }) {
    return MStreamBuilder<Object?>(
      // Dictation needs both the AI setting and a network, and both are live.
      streams: [
        network.isOnline.stream,
        globalSettings.observableMap.stream,
      ],
      builder: (context, _) {
        // The dictation writes the same fields the form does, so it takes the
        // same permission.
        final voice = canViewPostOp(appointment)
            ? operativeVoiceAction(
                appointment,
                onEdited: onEdited,
                compact: true,
              )
            : null;
        if (windows.isEmpty && voice == null) return const SizedBox.shrink();
        return WindowAttachments(
          key: WK.visitChartAttachments,
          windows: windows,
          accent: PanelAccents.appointment,
          marker: windows.isNotEmpty,
          trailing: voice,
          // The card pads its fields; the tray adds only the divider above it.
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
      },
    );
  }

  // Standalone path only: beside the patient the tray toggles attached windows.
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
