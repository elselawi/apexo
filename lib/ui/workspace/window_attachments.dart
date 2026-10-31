import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The editors a record carries with it, drawn as **attachments** on the frame
/// they belong to.
///
/// A visit's labwork order and photos hang off its band and off the post-op card
/// inside its chart; a patient's photos and page hang off the patient's panel.
/// They are not row windows — they never take a place beside the panel — so they
/// are not switches in a dock: they are a row of chips at the foot of the thing
/// they are about, one click from the editor and one click back.
///
/// The tray is deliberately quiet: a paperclip, then a chip per attachment with
/// its own label and whether its editor is on screen. It reads as a footer, not
/// as another toolbar, so the window above it keeps the eye.
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
    this.padding = const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
  });

  final List<PanelWindow> windows;

  /// Whether the attachment's editor is on screen now.
  final bool Function(PanelWindow window) isOpen;

  /// Switches the attachment's editor on or off.
  final void Function(PanelWindow window) onToggle;

  /// Per-attachment permission to open it — false while it needs a stored
  /// record. Null means every attachment may be opened.
  final bool Function(PanelWindow window)? enabled;

  /// The colour the record is known by, so its attachments are tinted like it.
  final Color? accent;

  final Key Function(PanelWindow window)? keyForWindow;

  /// Whether the tray leads with a paperclip. A tray that is the whole point of
  /// its surface (the panel's) says what it is; one under a window that already
  /// names its record can do without.
  final bool marker;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final tint = accent ?? theme.accentColor;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (marker)
            Tooltip(
              message: txt('attachments'),
              child: Icon(
                FluentIcons.attach,
                size: 12,
                color: theme.inactiveColor,
              ),
            ),
          for (final window in windows)
            _AttachmentChip(
              key: keyForWindow?.call(window) ?? WK.attachmentToggle(window.id),
              window: window,
              open: isOpen(window),
              enabled: enabled?.call(window) ?? true,
              tint: tint,
              onToggle: () => onToggle(window),
            ),
        ],
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
    // What the attachment holds, not only what it is called: a gallery's first
    // pictures, an order's state. Null for a chip with nothing to preview.
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
                Icon(window.icon, size: 12, color: foreground),
                const SizedBox(width: 5),
                if (preview != null) ...[
                  preview,
                  const SizedBox(width: 5),
                ],
                // The name gives way before the chip does: a preview makes the
                // chip wider, and a tray is only as wide as the frame it is on.
                Flexible(
                  child: Txt(
                    txt(window.title),
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.caption?.copyWith(
                      fontSize: 11,
                      fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                if (open) ...[
                  const SizedBox(width: 5),
                  // On screen now: the chip says so, and pressing it puts it
                  // away — the same grammar as the dock it replaced.
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
