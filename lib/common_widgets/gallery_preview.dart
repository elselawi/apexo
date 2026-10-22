part of 'grid_gallery.dart';

class _GalleryDeleteButton extends StatelessWidget {
  const _GalleryDeleteButton({
    required this.onConfirm,
    required this.rowId,
    required this.name,
  });
  final VoidCallback onConfirm;
  final String rowId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return DeleteButton(
      onConfirm: onConfirm,
      preview: FileDeletePreview(rowId: rowId, name: name),
      actionText: txt("delete"),
      actionIcon: WindowsIcons.delete,
      restorable: false,
      style: _deleteButtonStyle.copyWith(
        iconSize: const WidgetStatePropertyAll(18),
      ),
      child: const Icon(
        WindowsIcons.delete,
        size: 18,
        color: Colors.white,
      ),
    );
  }
}

// ─── File preview widget ─────────────────────────────────────────────────

/// A unified preview widget that auto-detects whether [name] is an image
/// (by extension) and shows either a loaded thumbnail or a file placeholder.
class FileDeletePreview extends StatelessWidget {
  const FileDeletePreview({
    super.key,
    this.rowId,
    required this.name,
    this.size = 80,
  });
  final String? rowId;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fileThumb = _FileThumbnail(
      name: name,
      iconSize: size * 0.5,
      showLabel: false,
    );
    if (!isAnImageName(name)) {
      return fileThumb;
    }
    return FutureBuilder<ImageProvider?>(
      future: getImage(rowId!, name, true),
      builder: (_, snap) {
        if (!snap.hasData) {
          return fileThumb;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image(
            image: snap.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

// ─── Upload configuration ────────────────────────────────────────────────
