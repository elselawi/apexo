import 'dart:async';

import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'image_viewer.dart';

/// A record's photos, loaded in the window itself so the wait stays inside it.
/// [ImageViewer] only renders and knows nothing about stores, files or loading.
class PhotoViewerWindow extends StatefulWidget {
  const PhotoViewerWindow({
    super.key,
    required this.rowId,
    required this.images,
    this.initialIndex = 0,
    this.drawings,
    this.onSaveDrawing,
    this.onDelete,
    this.onClosed,
    this.load,
  });

  /// The record whose files these are.
  final String rowId;

  /// The file names to show, in order.
  final List<String> images;

  /// The photo to open on.
  final int initialIndex;

  /// Drawings already stored, by file name.
  final Map<String, String>? drawings;
  final void Function(String imageId, String drawing)? onSaveDrawing;

  /// Deletes the photo at the given index in [images]; null means view-only.
  final ValueChanged<int>? onDelete;

  /// Runs once the photo on screen is deleted, so the window can close with it.
  final VoidCallback? onClosed;

  /// Loader seam for tests only: the app always reads the record's own files, so
  /// nothing in the app should pass this.
  @visibleForTesting
  final Future<List<ImageProvider<Object>>> Function()? load;

  @override
  State<PhotoViewerWindow> createState() => _PhotoViewerWindowState();
}

class _PhotoViewerWindowState extends State<PhotoViewerWindow> {
  late Future<List<ImageProvider<Object>>> _loading = _load();

  // The loaded photos, evicted on dispose: full-size X-rays are the biggest thing
  // the app loads and outlive the gallery that opened them.
  final Set<ImageProvider<Object>> _loaded = <ImageProvider<Object>>{};

  Future<List<ImageProvider<Object>>> _load() async {
    try {
      final load = widget.load;
      if (load != null) {
        final providers = await load();
        _loaded.addAll(providers);
        return providers;
      }
      final providers = await Future.wait(
        widget.images.map((name) => getImage(widget.rowId, name, false)),
      );
      final resolved = [
        for (final provider in providers)
          provider ?? const AssetImage('assets/images/missing.png'),
      ];
      _loaded.addAll(resolved);
      return resolved;
    } catch (error, stackTrace) {
      logger("Error loading images: $error", stackTrace);
      rethrow;
    }
  }

  @override
  void dispose() {
    for (final provider in _loaded) {
      unawaited(provider.evict());
    }
    super.dispose();
  }

  void _retry() {
    setState(() {
      _loading = _load();
    });
  }

  void _delete(int index) {
    widget.onDelete!(index);
    widget.onClosed?.call();
  }

  Widget _message(String text, {bool waiting = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (waiting) ...[
            const ProgressRing(backgroundColor: Colors.white),
            const SizedBox(height: 10),
          ],
          Txt(text, style: const TextStyle(color: Colors.white)),
          if (!waiting) ...[
            const SizedBox(height: 8),
            HyperlinkButton(
              onPressed: _retry,
              child: Txt(
                txt("retry"),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: FutureBuilder<List<ImageProvider<Object>>>(
        future: _loading,
        builder: (context, snapshot) {
          final providers = snapshot.data;
          if (snapshot.hasError || (providers != null && providers.isEmpty)) {
            return _message(txt("couldNotOpenImage"));
          }
          if (providers == null) {
            return _message(txt("gettingImages"), waiting: true);
          }
          return ImageViewer(
            providers,
            rowId: widget.rowId,
            imageIds: widget.images,
            initialIndex: widget.initialIndex,
            drawings: widget.drawings,
            onSaveDrawing: widget.onSaveDrawing,
            onPressedDelete: widget.onDelete == null ? null : _delete,
          );
        },
      ),
    );
  }
}
