import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.leading,
    required this.header,
    this.description,
    this.trailing,
    this.control,
    this.content,
    this.contentPadding = const EdgeInsets.only(top: 20),
  });

  final Widget leading;
  final Widget header;
  final Widget? description;
  final Widget? trailing;
  final Widget? control;
  final Widget? content;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FluentMaterials.of(context).card,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: FluentMaterials.surfaceRadius,
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final inline = constraints.maxWidth >= 640;
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: IconTheme(
                data: IconThemeData(size: 18, color: theme.accentColor),
                child: Center(child: leading),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    child: header,
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.resources.textFillColorSecondary,
                      ),
                      child: description!,
                    ),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(height: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (inline && control != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 28),
                  SizedBox(width: 260, child: control),
                ],
              )
            else ...[
              heading,
              if (control != null) ...[
                const SizedBox(height: 16),
                control!,
              ],
            ],
            if (content != null)
              Padding(padding: contentPadding, child: content),
          ],
        );
      }),
    );
  }
}
