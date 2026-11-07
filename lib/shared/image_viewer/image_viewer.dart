import 'dart:async';
import 'dart:math' as math;

import 'package:apexo/common_widgets/transitions/border.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Colors, IconButton, Tooltip;
import 'package:flutter/services.dart';

import 'drawing_canvas.dart';
import 'image_page.dart';
import 'viewer_tools.dart';

class ImageViewer extends StatefulWidget {
  const ImageViewer(
    this.images, {
    super.key,
    this.rowId,
    this.imageIds,
    this.initialIndex = 0,
    this.drawings,
    this.onSaveDrawing,
    this.onPressedDelete,
  });

  /// The photos, already loaded and ready to draw.
  final List<ImageProvider<Object>> images;

  /// The record whose files these are, which is what a download resolves by.
  final String? rowId;

  /// File names, page by page; a page's drawing is keyed by its name.
  final List<String>? imageIds;

  /// The page to open on.
  final int initialIndex;

  /// Drawings already stored, by file name.
  final Map<String, String>? drawings;

  /// Saves a page's drawing; null leaves every photo unannotated and offers no pen.
  final void Function(String imageId, String drawing)? onSaveDrawing;

  /// Deletes the photo at that index; null hides the delete action.
  final ValueChanged<int>? onPressedDelete;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  /// How long a slideshow rests on a photo, and how long a page takes to move.
  static const Duration _slideshowStep = Duration(seconds: 10);
  static const Duration _turn = Duration(milliseconds: 200);

  int get _pageCount => widget.images.length;

  /// True when there is more than one photo to page through.
  bool get _paged => _pageCount > 1;

  late final PageController _pages = PageController(
    initialPage: math.max(0, math.min(widget.initialIndex, _pageCount - 1)),
  );
  final FocusNode _keys = FocusNode();

  // The paged list's index: with more than one photo the list wraps, so it is
  // not the photo's index.
  late int _at = math.max(0, math.min(widget.initialIndex, _pageCount - 1));

  /// The photo on screen.
  int get _page => _at % _pageCount;

  bool _isDrawing = false;
  bool _isEraser = false;
  bool _showDrawings = true;
  Color _selectedColor = ViewerDrawingTools.colors.first;

  // False while a photo is zoomed in: the drag belongs to the photo.
  bool _pagingEnabled = true;

  Timer? _slideshow;

  /// The file name of the page on screen, empty where the viewer has no names.
  String get _fileName {
    final ids = widget.imageIds;
    if (ids == null || _page < 0 || _page >= ids.length) return '';
    return ids[_page];
  }

  /// The drawing already stored on the page on screen, if there is one.
  String? get _drawing {
    final drawings = widget.drawings;
    final name = _fileName;
    if (drawings == null || name.isEmpty) return null;
    return drawings[name];
  }

  @override
  void dispose() {
    _slideshow?.cancel();
    _pages.dispose();
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The loader above reports why there is no photo, so draw nothing here.
    if (widget.images.isEmpty) return const SizedBox.shrink();
    return KeyboardListener(
      focusNode: _keys,
      // Autofocus: the arrow keys page as soon as the window opens, with no click.
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _pages,
            scrollBehavior: const _DragAnywhereScrollBehavior(),
            physics: _pagingEnabled
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            // One photo is a photo; more than one is a carousel that wraps.
            itemCount: _paged ? null : 1,
            onPageChanged: (index) => setState(() {
              _at = index;
              // A newly paged-in photo is at rest and reports no scale, so reset
              // the flag; otherwise paging stays locked once a zoomed page is left.
              _pagingEnabled = true;
            }),
            itemBuilder: (context, index) => _buildPage(index % _pageCount),
          ),
          if (_paged) ...[
            Positioned(top: 0, left: 5, child: _buildPageCounter()),
            Positioned(bottom: 0, left: 0, child: _buildPagingControls()),
          ],
          if (widget.onSaveDrawing != null)
            Positioned(
              // Above the paging controls: the wide pen pill would otherwise
              // cover the "previous photo" chevron and eat its clicks.
              bottom: 60,
              left: 20,
              right: 20,
              child: Center(child: _buildDrawingTools()),
            ),
          if (widget.imageIds != null || widget.onPressedDelete != null)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Center(child: _buildFileTools()),
            ),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    final imageId = widget.imageIds?.elementAtOrNull(index);
    // No pen means no drawing layer: a canvas that cannot save would still paint
    // the stored strokes, which a view-only photo must not show.
    final canDraw = widget.onSaveDrawing != null;
    return ImageViewerPage(
      key: ValueKey(imageId ?? index),
      image: widget.images[index],
      drawing: imageId == null ? null : widget.drawings?[imageId],
      onSaveDrawing: (imageId == null || !canDraw)
          ? null
          : (drawing) => widget.onSaveDrawing!(imageId, drawing),
      isDrawingMode: _isDrawing,
      showDrawings: _showDrawings,
      selectedColor: _selectedColor,
      isEraserMode: _isEraser,
      onScaleChanged: (scale) {
        final next = scale <= 1.0;
        if (next == _pagingEnabled) return;
        setState(() => _pagingEnabled = next);
      },
    );
  }

  /// "3/12", where this photo sits among them.
  Widget _buildPageCounter() {
    return Text(
      '${_page + 1}/$_pageCount',
      style: const TextStyle(color: Colors.white, fontSize: 20),
    );
  }

  Widget _buildPagingControls() {
    final playing = _slideshow != null;
    return Row(
      mainAxisSize: MainAxisSize.max,
      textDirection: TextDirection.ltr,
      children: [
        Tooltip(
          message: txt('previousPhoto'),
          child: IconButton(
            icon: const Icon(WindowsIcons.chevron_left,
                color: Colors.white, size: 30),
            onPressed: _previous,
          ),
        ),
        BorderColorTransition(
          animate: playing,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Tooltip(
              message: txt(playing ? 'pause' : 'play'),
              child: IconButton(
                icon: Icon(
                  playing
                      ? FluentIcons.pause
                      : FluentIcons.play_resume,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: _toggleSlideshow,
              ),
            ),
          ),
        ),
        Tooltip(
          message: txt('nextPhoto'),
          child: IconButton(
            icon: const Icon(WindowsIcons.chevron_right,
                color: Colors.white, size: 30),
            onPressed: _next,
          ),
        ),
      ],
    );
  }

  Widget _buildDrawingTools() {
    return ViewerDrawingTools(
      isDrawing: _isDrawing,
      isEraser: _isEraser,
      showDrawings: _showDrawings,
      selectedColor: _selectedColor,
      canHideDrawings: hasStrokes(_drawing),
      onToggleDrawing: () => setState(() {
        _isDrawing = !_isDrawing;
        if (_isDrawing) _showDrawings = true;
      }),
      onToggleEraser: () => setState(() => _isEraser = !_isEraser),
      onSelectColor: (color) => setState(() {
        _selectedColor = color;
        _isEraser = false;
      }),
      onToggleShowDrawings: () => setState(() {
        _showDrawings = !_showDrawings;
        if (!_showDrawings) _isDrawing = false;
      }),
    );
  }

  Widget _buildFileTools() {
    final delete = widget.onPressedDelete;
    return ViewerFileTools(
      rowId: widget.rowId,
      name: _fileName,
      preview: widget.images[_page],
      onPressedDelete: delete == null ? null : () => delete(_page),
    );
  }

  void _previous() {
    // The list only wraps forwards: there is no photo before the first one.
    if (_at == 0 || !_pages.hasClients) return;
    _pages.previousPage(duration: _turn, curve: Curves.easeInOut);
  }

  void _next() {
    if (!_pages.hasClients) return;
    _pages.nextPage(duration: _turn, curve: Curves.easeInOut);
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _previous();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _next();
    }
  }

  /// A slideshow moves on by itself, at a pace that lets a photo be read.
  void _toggleSlideshow() {
    setState(() {
      if (_slideshow == null) {
        _slideshow = Timer.periodic(_slideshowStep, (_) => _next());
      } else {
        _slideshow!.cancel();
        _slideshow = null;
      }
    });
  }
}

// Lets a mouse drag the pages as a finger does on touch; this photo browser is
// mouse-driven on desktop.
class _DragAnywhereScrollBehavior extends MaterialScrollBehavior {
  const _DragAnywhereScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}
