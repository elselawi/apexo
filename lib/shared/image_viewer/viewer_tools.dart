/// The buttons that act on the photo on screen, laid on the photo itself in a
/// dark pill so they stay legible over an X-ray or a white tooth.
///
/// Pure views: the viewer owns what the pen is doing; these only draw it and
/// report taps back.
library;

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/shared/image_viewer/file_download_button.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A pill to hold a row of tools above a photo.
class _ToolPill extends StatelessWidget {
  const _ToolPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A thin line between groups of tools.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: Colors.white.withValues(alpha: 0.54),
    );
  }
}

/// The pen's tools: draw, pick a colour, erase, hide what is drawn.
///
/// A pill with the pen and its colours, and the eraser and the eye only while
/// they mean something — a drawing tool that is always there says the photo has
/// drawings when it has none.
class ViewerDrawingTools extends StatelessWidget {
  const ViewerDrawingTools({
    super.key,
    required this.isDrawing,
    required this.isEraser,
    required this.showDrawings,
    required this.selectedColor,
    required this.canHideDrawings,
    required this.onToggleDrawing,
    required this.onToggleEraser,
    required this.onSelectColor,
    required this.onToggleShowDrawings,
  });

  final bool isDrawing;
  final bool isEraser;
  final bool showDrawings;
  final Color selectedColor;

  /// Whether this photo carries drawings worth showing or hiding.
  final bool canHideDrawings;

  final VoidCallback onToggleDrawing;
  final VoidCallback onToggleEraser;
  final ValueChanged<Color> onSelectColor;
  final VoidCallback onToggleShowDrawings;

  /// The pen colours, which are the ones a dentist reaches for on an X-ray.
  static final List<Color> colors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.white,
    Colors.black,
  ];

  @override
  Widget build(BuildContext context) {
    return _ToolPill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: _ToolLabel(
              icon: isDrawing ? FluentIcons.edit_solid12 : FluentIcons.edit,
              label: txt('draw'),
              active: isDrawing,
            ),
            onPressed: onToggleDrawing,
          ),
          const SizedBox(width: 8),
          if (isDrawing) ...[
            for (final color in colors)
              _ColorDot(
                color: color,
                selected: color == selectedColor && !isEraser,
                onPressed: () => onSelectColor(color),
              ),
            const SizedBox(width: 8),
            const _Divider(),
            const SizedBox(width: 8),
            IconButton(
              icon: _ToolLabel(
                icon: FluentIcons.erase_tool,
                label: txt('erase'),
                active: isEraser,
              ),
              onPressed: onToggleEraser,
            ),
            const SizedBox(width: 8),
            const _Divider(),
            const SizedBox(width: 8),
          ],
          if (canHideDrawings || isDrawing) ...[
            if (!isDrawing) ...[
              const SizedBox(width: 8),
              const _Divider(),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: _ToolLabel(
                icon: showDrawings ? FluentIcons.red_eye : FluentIcons.hide,
                label: txt('showDrawings'),
                active: showDrawings,
                inactive: !showDrawings,
              ),
              onPressed: onToggleShowDrawings,
            ),
          ],
        ],
      ),
    );
  }
}

/// The file's tools: download it, and delete it where the caller deletes.
class ViewerFileTools extends StatelessWidget {
  const ViewerFileTools({
    super.key,
    this.rowId,
    required this.name,
    this.preview,
    this.onPressedDelete,
  });

  /// The record whose files these are — what a download resolves the file by.
  final String? rowId;

  /// The file on screen. Empty where the viewer was given no names — and then
  /// no download is offered, because there is no file to fetch. The delete is
  /// offered on its own terms: it names the photo, not the file.
  final String name;

  /// The photo on screen, for the delete prompt to show what it would remove.
  final ImageProvider? preview;

  /// Null where deleting is not this viewer's to do.
  final VoidCallback? onPressedDelete;

  @override
  Widget build(BuildContext context) {
    final canDelete = onPressedDelete != null;
    final canDownload = name.isNotEmpty;
    // Nothing to act on: the viewer was given no names and may not delete.
    if (!canDelete && !canDownload) return const SizedBox.shrink();

    return _ToolPill(
      child: Row(
        spacing: 10,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canDownload)
            FileDownloadButton(
                rowId: rowId, name: name, buttonLabel: txt('download')),
          if (canDownload && canDelete) const _Divider(),
          if (canDelete)
            DeleteButton(
              onConfirm: onPressedDelete!,
              preview: _PhotoPreview(image: preview),
              actionText: txt('delete'),
              actionIcon: WindowsIcons.delete,
              restorable: false,
              style: const ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(Colors.white),
              ),
              child:
                  ButtonContent(WindowsIcons.delete, txt('delete'), size: 18),
            ),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({this.image});

  static const double _size = 80;

  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) {
      return const Icon(WindowsIcons.photo, size: _size * 0.5);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image(
        image: image,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// An icon and its word, tinted while the tool it stands for is on. The words
/// are the point: a draw button that is only a pencil leaves the dentist
/// guessing what a tap will do.
class _ToolLabel extends StatelessWidget {
  const _ToolLabel({
    required this.icon,
    required this.label,
    required this.active,
    this.inactive = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  /// Drawn dimmed: the tool is off rather than merely idle.
  final bool inactive;

  @override
  Widget build(BuildContext context) {
    final color = inactive
        ? Colors.white.withValues(alpha: 0.54)
        : active
            ? Colors.blue
            : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Txt(
          label,
          style: FluentTheme.of(context)
              .typography
              .bodyStrong!
              .copyWith(color: color, fontSize: 16),
        ),
      ],
    );
  }
}

/// One pen colour, ringed while it is the one in the dentist's hand.
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Big enough to be aimed at with a finger: a bare 24-pixel dot is a target
    // no one hits on a tablet.
    return Semantics(
      button: true,
      selected: selected,
      label: txt('penColor'),
      child: Tooltip(
        message: txt('penColor'),
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Colors.blue
                      : Colors.white.withValues(alpha: 0.54),
                  width: selected ? 3 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
