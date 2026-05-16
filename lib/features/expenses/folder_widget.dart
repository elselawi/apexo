import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SupplierFolder extends StatelessWidget {
  final Expense supplier;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;

  const SupplierFolder({
    super.key,
    required this.supplier,
    required this.currency,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final due = supplier.duePayments;
    final hasDue = due > 0.01;
    final flyoutCtrl = FlyoutController();

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: CustomPaint(
          painter: FolderPainter(
            color:
                hasDue ? Colors.warningSecondaryColor : Colors.yellow.lightest,
            borderColor: theme.resources.dividerStrokeColorDefault,
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: hasDue ? 10 : 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      supplier.supplierName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasDue) ...[
                      const SizedBox(height: 4),
                      MoneyDisplay(
                        hasDue ? "${due.toStringAsFixed(2)} $currency" : "",
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: hasDue
                              ? Colors.orange
                              : theme.typography.caption?.color,
                          fontWeight:
                              hasDue ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              Positioned(
                top: 5,
                left: 2,
                child: FlyoutTarget(
                  controller: flyoutCtrl,
                  child: IconButton(
                    icon: const Icon(FluentIcons.more_vertical, size: 12),
                    onPressed: () {
                      flyoutCtrl.showFlyout(builder: (context) {
                        return MenuFlyout(
                          items: [
                            MenuFlyoutItem(
                              text: Txt(txt("rename")),
                              leading: const Icon(FluentIcons.edit),
                              onPressed: () {
                                flyoutCtrl.close();
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  onRename();
                                });
                              },
                            ),
                            MenuFlyoutItem(
                              text: Txt(txt(supplier.archived == true
                                  ? "restore"
                                  : "archive")),
                              leading: Icon(supplier.archived == true
                                  ? FluentIcons.archive_undo
                                  : FluentIcons.archive),
                              onPressed: () {
                                flyoutCtrl.close();
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  onArchive();
                                });
                              },
                            ),
                          ],
                        );
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FolderPainter extends CustomPainter {
  final Color color;
  final Color? borderColor;
  final bool isDashed;

  FolderPainter({required this.color, this.borderColor, this.isDashed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = isDashed ? PaintingStyle.stroke : PaintingStyle.fill;

    if (isDashed) {
      paint.strokeWidth = 1.5;
    }

    final path = Path();
    const radius = 8.0;
    const tabWidth = 0.45;
    const tabHeight = 12.0;

    path.moveTo(0, radius + tabHeight);
    // Tab
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.lineTo(size.width * tabWidth - radius, 0);
    path.quadraticBezierTo(
        size.width * tabWidth, 0, size.width * tabWidth, radius);
    path.lineTo(size.width * tabWidth + 10, radius + tabHeight);
    // Top right
    path.lineTo(size.width - radius, radius + tabHeight);
    path.quadraticBezierTo(
        size.width, radius + tabHeight, size.width, radius * 2 + tabHeight);
    // Bottom right
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(
        size.width, size.height, size.width - radius, size.height);
    // Bottom left
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.close();

    if (!isDashed) {
      canvas.drawPath(path, paint);
      if (borderColor != null) {
        canvas.drawPath(
            path,
            Paint()
              ..color = borderColor!
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    } else {
      // Draw dashed path (simplified)
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
