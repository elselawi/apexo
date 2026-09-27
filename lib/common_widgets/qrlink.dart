import 'package:qr_flutter/qr_flutter.dart';
import 'package:fluent_ui/fluent_ui.dart';

class QRLink extends StatelessWidget {
  const QRLink({
    super.key,
    required this.link,
    this.size = 200.0,
  });
  final String link;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: QrImageView(
          data: link,
          version: QrVersions.auto,
          size: size,
          backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
          embeddedImageStyle:
              null, // Optional: You can add a logo in the center
          semanticsLabel: 'QR Code for $link',
        ),
      ),
    );
  }
}
