import 'dart:async';

import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'image_viewer.dart';

/// A record's photos, loaded where they are shown.
///
/// The wait lives here rather than in a dialog over the app: a photo can take a
/// moment to arrive, and that moment belongs inside the window that asked for
/// it, not on top of everything else the dentist is doing. Once the photos are
/// here, [ImageViewer] does the rest — it knows nothing about stores, files or
/// loading.
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

  /// Deletes the photo it is given, by its index in [images]. Null where the
  /// dentist may look but not delete.
  final ValueChanged<int>? onDelete;

  /// Runs once the photo on screen is deleted, so the window can close with it.
  final VoidCallback? onClosed;

  /// How the photos are fetched. The app reads them from the record's files;
  /// a test supplies its own.
  ///
  /// The seam exists for the tests alone — the app always reads the record's
  /// own files — so nothing in the app should reach for it.
  @visibleForTesting
  final Future<List<ImageProvider<Object>>> Function()? load;

  @override
  State<PhotoViewerWindow> createState() => _PhotoViewerWindowState();
}

class _PhotoViewerWindowState extends State<PhotoViewerWindow> {
  late Future<List<ImageProvider<Object>>> _loading = _load();

  /// The photos that were loaded, so they can be taken out of the image cache
  /// when this viewer goes away.
  ///
  /// The full-size photos of an X-ray are the biggest thing the app loads, and
  /// the window that shows them outlives the gallery that opened it — so
  /// nothing else would ever take them out again.
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

  /// The one place the window talks to the dentist while it has no photo yet:
  /// what it is doing, or what went wrong and the way to try again.
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
