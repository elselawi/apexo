import 'dart:math' as math;

import 'package:apexo/features/appointments/follow_up_card.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The patient's follow-up on the visit scope bar; clicking opens [FollowUpCard].
class FollowUpScopeDot extends StatefulWidget {
  const FollowUpScopeDot({
    super.key,
    required this.patient,
    required this.date,
    this.onBook,
  });

  final Patient patient;

  /// The day the patient was asked to come back.
  final DateTime date;

  /// Books the visit for that day; null when the account cannot create visits.
  final VoidCallback? onBook;

  @override
  State<FollowUpScopeDot> createState() => _FollowUpScopeDotState();
}

class _FollowUpScopeDotState extends State<FollowUpScopeDot> {
  final OverlayPortalController _hover = OverlayPortalController();

  // The dot's width: dashed lead-in, circle and day, as the visit dots have.
  static const double width = 58.0;
  static const double _trackY = 14.0;
  static const double _size = 21.0;

  bool _hovered = false;

  void _setHover(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
    if (value && !_hover.isShowing) {
      _hover.show();
    } else if (!value && _hover.isShowing) {
      _hover.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    final label = txt('followUpOn')
        .replaceAll('{date}', DF.commonDate(widget.date))
        .replaceAll('📅 ', '');

    return OverlayPortal(
      controller: _hover,
      overlayChildBuilder: (overlayContext) =>
          _buildHoverOverlay(overlayContext),
      child: FollowUpCardTarget(
        patient: widget.patient,
        date: widget.date,
        onOpened: () {
          if (_hover.isShowing) _hover.hide();
        },
        onBook: widget.onBook,
        builder: (context, open) => Semantics(
          button: true,
          label: '${txt('followUp')} · $label',
          child: MouseRegion(
            onEnter: (_) => _setHover(true),
            onExit: (_) => _setHover(false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: open,
              child: SizedBox(
                width: width,
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PositionedDirectional(
                      start: 0,
                      top: _trackY - 0.5,
                      width: 13,
                      height: 1,
                      child: CustomPaint(
                        painter: _DashedLeadIn(
                          color: accent.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      start: 13,
                      top: _trackY - _size / 2,
                      width: _size,
                      height: _size,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        scale: _hovered ? 1.12 : 1.0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF23B3BF), accent],
                            ),
                            border: Border.all(
                              color: dark
                                  ? theme.resources.solidBackgroundFillColorBase
                                  : Colors.white,
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(
                                    alpha: _hovered ? 0.60 : 0.45),
                                blurRadius: _hovered ? 13 : 9,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              WindowsIcons.walk_solid,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // The day, exactly where the visit dots put theirs.
                    PositionedDirectional(
                      start: 0,
                      top: 25,
                      width: width,
                      height: 14,
                      child: IgnorePointer(
                        child: Center(
                          child: Text(
                            DF.allNumbers(widget.date),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHoverOverlay(BuildContext overlayContext) {
    final dotBox = context.findRenderObject() as RenderBox?;
    final overlayBox = Overlay.maybeOf(overlayContext)
        ?.context
        .findRenderObject() as RenderBox?;
    if (dotBox == null ||
        !dotBox.attached ||
        overlayBox == null ||
        !overlayBox.attached) {
      return const SizedBox.shrink();
    }

    final dotTopLeft = dotBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    const cardWidth = 262.0;
    final centerX =
        dotTopLeft.dx + (width - 13) / 2; // the circle, not the whole hit box
    final left = (centerX - cardWidth / 2)
        .clamp(8.0, math.max(8.0, overlayBox.size.width - cardWidth - 8.0))
        .toDouble();
    final tailOffset =
        (centerX - left).clamp(20.0, cardWidth - 20.0).toDouble();
    final top = math.min(
      dotTopLeft.dy + 34,
      math.max(8.0, overlayBox.size.height - 150.0),
    );

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: IgnorePointer(
        child: _FollowUpHoverCard(
          key: const ValueKey('follow-up-hover-card'),
          patient: widget.patient,
          date: widget.date,
          tailCenterX: tailOffset,
        ),
      ),
    );
  }
}

/// A dashed run of the timeline that has not been walked yet.
class _DashedLeadIn extends CustomPainter {
  const _DashedLeadIn({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + 4, size.width), size.height / 2),
        paint,
      );
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashedLeadIn oldDelegate) => oldDelegate.color != color;
}

class _FollowUpHoverCard extends StatelessWidget {
  const _FollowUpHoverCard({
    super.key,
    required this.patient,
    required this.date,
    required this.tailCenterX,
  });

  final Patient patient;
  final DateTime date;
  final double tailCenterX;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const accent = kFollowUpAccent;
    final phone = patient.phone.isEmpty
        ? null
        : patient.phone.first.toInternationalFormat();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            decoration: BoxDecoration(
              color: theme.menuColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accent.withValues(alpha: dark ? 0.55 : 0.38),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: dark ? 0.16 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FollowUpBadge(date: date),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(WindowsIcons.walk_solid,
                        size: 13, color: accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        DF.commonDate(date).replaceAll('📅 ', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.bodyStrong?.copyWith(
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                if (phone != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(WindowsIcons.phone, size: 12, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: theme.typography.caption?.copyWith(
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  txt('followUpContactHint'),
                  style: theme.typography.caption?.copyWith(
                    fontSize: 9.5,
                    color: theme.inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: tailCenterX - 7,
          child: CustomPaint(
            size: const Size(14, 7),
            painter: _TailPainter(
              fill: theme.menuColor,
              border: accent.withValues(alpha: dark ? 0.55 : 0.38),
            ),
          ),
        ),
      ],
    );
  }
}

/// The little tail that ties a hover card to the dot it belongs to.
class _TailPainter extends CustomPainter {
  const _TailPainter({required this.fill, required this.border});

  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.border != border;
}
