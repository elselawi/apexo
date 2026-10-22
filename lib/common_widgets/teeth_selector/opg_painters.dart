part of 'opg_dental_chart.dart';

class _OpgBackdropPainter extends CustomPainter {
  const _OpgBackdropPainter({
    required this.darkMode,
    required this.isPrimary,
  });

  final bool darkMode;
  final bool isPrimary;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final boneLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = darkMode
          ? const Color(0xFF283A52).withValues(alpha: 0.45)
          : const Color(0xFFCBD5E1).withValues(alpha: 0.65);

    final upperCejY = isPrimary ? h * 0.24 : h * 0.25;
    final lowerCejY = isPrimary ? h * 0.72 : h * 0.70;

    final upperCrest = Path()
      ..moveTo(8, upperCejY - 4)
      ..quadraticBezierTo(w * 0.5, upperCejY + 6, w - 8, upperCejY - 4);
    canvas.drawPath(upperCrest, boneLinePaint);

    final lowerCrest = Path()
      ..moveTo(8, lowerCejY + 4)
      ..quadraticBezierTo(w * 0.5, lowerCejY - 6, w - 8, lowerCejY + 4);
    canvas.drawPath(lowerCrest, boneLinePaint);

    if (!isPrimary) {
      final sinusPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = darkMode
            ? const Color(0xFF1E2D42).withValues(alpha: 0.55)
            : const Color(0xFFD8E2EE).withValues(alpha: 0.75);

      final rightSinus = Path()
        ..moveTo(w * 0.05, h * 0.06)
        ..quadraticBezierTo(w * 0.16, h * 0.20, w * 0.29, h * 0.08);
      final leftSinus = Path()
        ..moveTo(w * 0.71, h * 0.08)
        ..quadraticBezierTo(w * 0.84, h * 0.20, w * 0.95, h * 0.06);
      canvas.drawPath(rightSinus, sinusPaint);
      canvas.drawPath(leftSinus, sinusPaint);

      // Inferior alveolar nerve (mandibular canal) running below the lower
      // molars and curving up between the apices of the two premolars (45/44
      // on the right, 35/34 on the left) to open at the mental foramen.
      final rightIanUpper = Path()
        ..moveTo(w * 0.02, h * 0.89)
        ..cubicTo(
          w * 0.10,
          h * 0.96,
          w * 0.22,
          h * 0.95,
          w * 0.275,
          h * 0.87,
        );
      final rightIanLower = Path()
        ..moveTo(w * 0.02, h * 0.92)
        ..cubicTo(
          w * 0.10,
          h * 0.985,
          w * 0.23,
          h * 0.975,
          w * 0.285,
          h * 0.89,
        );
      final rightForamen = Path()
        ..addOval(Rect.fromCenter(
          center: Offset(w * 0.28, h * 0.875),
          width: 7.5,
          height: 5.5,
        ));

      final leftIanUpper = Path()
        ..moveTo(w * 0.98, h * 0.89)
        ..cubicTo(
          w * 0.90,
          h * 0.96,
          w * 0.78,
          h * 0.95,
          w * 0.725,
          h * 0.87,
        );
      final leftIanLower = Path()
        ..moveTo(w * 0.98, h * 0.92)
        ..cubicTo(
          w * 0.90,
          h * 0.985,
          w * 0.77,
          h * 0.975,
          w * 0.715,
          h * 0.89,
        );
      final leftForamen = Path()
        ..addOval(Rect.fromCenter(
          center: Offset(w * 0.72, h * 0.875),
          width: 7.5,
          height: 5.5,
        ));

      canvas.drawPath(rightIanUpper, sinusPaint);
      canvas.drawPath(rightIanLower, sinusPaint);
      canvas.drawPath(rightForamen, sinusPaint);
      canvas.drawPath(leftIanUpper, sinusPaint);
      canvas.drawPath(leftIanLower, sinusPaint);
      canvas.drawPath(leftForamen, sinusPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OpgBackdropPainter oldDelegate) =>
      oldDelegate.darkMode != darkMode || oldDelegate.isPrimary != isPrimary;
}

/// The compact arch's backdrop: the line the two jaws part along and the
/// midline between the patient's two sides, which together split the mouth
/// into its four quadrants.
class _CompactArchPainter extends CustomPainter {
  const _CompactArchPainter({required this.darkMode});

  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final dividerColor = darkMode
        ? const Color(0xFF334766).withValues(alpha: 0.75)
        : const Color(0xFF9EB0C7).withValues(alpha: 0.6);

    final dividerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = dividerColor;
    final dividerY = size.height / 2;
    canvas.drawPath(
      Path()
        ..moveTo(0, dividerY - 1.5)
        ..quadraticBezierTo(
            size.width / 2, dividerY + 1.5, size.width, dividerY - 1.5),
      dividerPaint,
    );
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      dividerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CompactArchPainter oldDelegate) =>
      oldDelegate.darkMode != darkMode;
}

class _OcclusalCurvePainter extends CustomPainter {
  const _OcclusalCurvePainter({
    required this.color,
    required this.isPrimary,
  });

  final Color color;
  final bool isPrimary;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;

    final path = Path()
      ..moveTo(4, midY - 2)
      ..quadraticBezierTo(w * 0.5, midY + 3, w - 4, midY - 2);
    canvas.drawPath(path, paint);

    canvas.drawLine(
      Offset(w * 0.5, 0),
      Offset(w * 0.5, h),
      paint..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _OcclusalCurvePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isPrimary != isPrimary;
}

/// Anatomically distinct labial/buccal tooth painter for OPG panoramic view.
///
/// Preserves the rich, luminous tooth shading of the original OPG design
/// while rendering crisp, anatomically clipped visual drawings for every
/// treatment type. Operations from earlier appointments are drawn in a neutral
/// radiographic grey/silver palette, whereas operations registered in the
/// current record are drawn in their vibrant treatment colors.
