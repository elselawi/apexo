import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A record's attached editors, as chips on the frame they belong to.
class WindowAttachments extends StatelessWidget {
  const WindowAttachments({
    super.key,
    required this.windows,
    required this.isOpen,
    required this.onToggle,
    this.enabled,
    this.accent,
    this.keyForWindow,
    this.marker = true,
    this.trailing,
    this.padding = const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
  });

  final List<PanelWindow> windows;

  /// Whether the attachment's editor is on screen now.
  final bool Function(PanelWindow window) isOpen;

  /// Switches the attachment's editor on or off.
  final void Function(PanelWindow window) onToggle;

  /// Per-attachment permission to open it; null means all may open. A caller
  /// disables attachments that need the record stored first.
  final bool Function(PanelWindow window)? enabled;

  /// The colour the record is known by, so its attachments are tinted like it.
  final Color? accent;

  final Key Function(PanelWindow window)? keyForWindow;

  final bool marker;

  /// Drawn after the chips: an action that belongs to the same foot as the
  /// record's attachments rather than to its fields.
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final tint = accent ?? theme.accentColor;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: FluentMaterials.of(context).glassTint.withAlpha(6),
        border: Border(
          top: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (marker)
                    Tooltip(
                      message: txt('attachments'),
                      child: Icon(
                        WindowsIcons.attach,
                        size: 16,
                        color: theme.inactiveColor,
                      ),
                    ),
                  for (final window in windows)
                    _AttachmentChip(
                      key: keyForWindow?.call(window) ??
                          WK.attachmentToggle(window.id),
                      window: window,
                      open: isOpen(window),
                      enabled: enabled?.call(window) ?? true,
                      tint: tint,
                      onToggle: () => onToggle(window),
                    ),
                ],
              ),
            ),
            // Not an attachment: it keeps the end of the row, after the
            // record's own editors.
            if (trailing != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: trailing,
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    super.key,
    required this.window,
    required this.open,
    required this.enabled,
    required this.tint,
    required this.onToggle,
  });

  final PanelWindow window;
  final bool open;
  final bool enabled;
  final Color tint;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final idle = theme.resources.solidBackgroundFillColorBase;
    final muted = theme.inactiveColor;
    final foreground = !enabled
        ? muted.withValues(alpha: 0.55)
        : open
            ? tint
            : (theme.typography.body?.color ?? muted);
    final border = !enabled
        ? Colors.grey.withValues(alpha: 0.18)
        : open
            ? tint.withValues(alpha: 0.55)
            : Colors.grey.withValues(alpha: 0.30);
    final background = open
        ? Color.alphaBlend(tint.withValues(alpha: 0.10), idle)
        : Colors.transparent;
    final preview = window.chipPreview?.call();

    return Tooltip(
      message: txt(window.title),
      child: HoverButton(
        onPressed: enabled ? onToggle : null,
        builder: (context, states) {
          final hovered =
              states.contains(WidgetState.hovered) && enabled && !open;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsetsDirectional.fromSTEB(7, 3, 8, 3),
            decoration: BoxDecoration(
              color: hovered
                  ? Color.alphaBlend(
                      Colors.grey.withValues(alpha: 0.10), background)
                  : background,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(window.icon, size: 15, color: foreground),
                const SizedBox(width: 5),
                if (preview != null) ...[
                  preview,
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Txt(
                    txt(window.title),
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption?.copyWith(
                      fontSize: 12.5,
                      fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                if (open) ...[
                  const SizedBox(width: 5),
                  Icon(WindowsIcons.chrome_minimize,
                      size: 10, color: foreground),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
