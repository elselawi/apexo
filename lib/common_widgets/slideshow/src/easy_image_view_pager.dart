import 'dart:async';
import 'package:apexo/common_widgets/transitions/border.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide IconButton, Colors;
import 'package:flutter/services.dart';

import 'easy_image_provider.dart';
import 'easy_image_view.dart';

/// Custom ScrollBehavior that allows dragging with all pointers
/// including the normally excluded mouse
class MouseEnabledScrollBehavior extends MaterialScrollBehavior {
  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

/// PageView for swiping through a list of images
class EasyImageViewPager extends StatefulWidget {
  final EasyImageProvider easyImageProvider;
  final PageController pageController;
  final bool doubleTapZoomable;
  final bool infinitelyScrollable;

  /// Callback for when the scale has changed, only invoked at the end of
  /// an interaction.
  final void Function(double)? onScaleChanged;

  final Map<String, String>? drawings;
  final List<String>? imageIds;
  final void Function(String, String)? onSaveDrawing;
  final bool isDrawingMode;
  final bool showDrawings;
  final Color selectedColor;
  final bool isEraserMode;

  /// Create new instance, using the [easyImageProvider] to populate the [PageView],
  /// and the [pageController] to control the initial image index to display.
  /// The optional [doubleTapZoomable] boolean defaults to false and allows double tap to zoom.
  EasyImageViewPager({
    super.key,
    required this.easyImageProvider,
    required this.pageController,
    this.doubleTapZoomable = false,
    this.onScaleChanged,
    this.infinitelyScrollable = false,
    this.drawings,
    this.imageIds,
    this.onSaveDrawing,
    this.isDrawingMode = false,
    this.showDrawings = true,
    this.selectedColor = const Color(0xFF000000),
    this.isEraserMode = false,
  });

  @override
  State<EasyImageViewPager> createState() => _EasyImageViewPagerState();
}

class _EasyImageViewPagerState extends State<EasyImageViewPager> {
  bool _pagingEnabled = true;
  bool slideshowEnabled = false;

  late Timer _timer;

  @override
  void initState() {
    super.initState();

    widget.pageController.addListener(() {
      setState(() {});
    });

    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (slideshowEnabled) {
        widget.pageController.nextPage(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _timer.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (ev) {
        if (widget.pageController.page == null) {
          return;
        }
        if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.pageController.previousPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        } else if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
          widget.pageController.nextPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      },
      child: Stack(
        children: [
          PageView.builder(
            physics: _pagingEnabled
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            key: GlobalObjectKey(widget.easyImageProvider),
            itemCount: widget.infinitelyScrollable
                ? null
                : widget.easyImageProvider.imageCount,
            controller: widget.pageController,
            scrollBehavior: MouseEnabledScrollBehavior(),
            itemBuilder: (context, index) {
              final pageIndex = _getPageIndex(index);
              final imgId = (widget.imageIds != null &&
                      pageIndex < widget.imageIds!.length)
                  ? widget.imageIds![pageIndex]
                  : null;
              final drawingStr = imgId != null && widget.drawings != null
                  ? widget.drawings![imgId]
                  : null;

              return EasyImageView.imageWidget(
                GestureDetector(
                  onTap: () {
                    // leave empty
                  },
                  child: widget.easyImageProvider
                      .imageWidgetBuilder(context, pageIndex),
                ),
                key: Key('easy_image_view_$pageIndex'),
                doubleTapZoomable: widget.doubleTapZoomable,
                initialDrawing: drawingStr,
                onSaveDrawing: (widget.onSaveDrawing != null && imgId != null)
                    ? (newDrawing) {
                        widget.onSaveDrawing!(imgId, newDrawing);
                      }
                    : null,
                isDrawingMode: widget.isDrawingMode,
                showDrawings: widget.showDrawings,
                selectedColor: widget.selectedColor,
                isEraserMode: widget.isEraserMode,
                onScaleChanged: (scale) {
                  if (widget.onScaleChanged != null) {
                    widget.onScaleChanged!(scale);
                  }

                  setState(() {
                    _pagingEnabled = scale <= 1.0;
                  });
                },
              );
            },
          ),
          if (widget.easyImageProvider.imageCount > 1)
            Positioned(
              top: 0,
              left: 5,
              child: LayoutBuilder(builder: (context, constraints) {
                return Text(
                  "${((widget.pageController.page! % widget.easyImageProvider.imageCount) + 1).round()}/${widget.easyImageProvider.imageCount}",
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                );
              }),
            ),
          if (widget.easyImageProvider.imageCount > 1)
            Positioned(
              bottom: 0,
              left: 0,
              child: Row(
                  mainAxisSize: MainAxisSize.max,
                  textDirection: TextDirection.ltr,
                  children: [
                    IconButton(
                      icon: const Icon(FluentIcons.chevron_left,
                          color: Colors.white, size: 30),
                      onPressed: () {
                        widget.pageController.animateToPage(
                          widget.pageController.page!.toInt() - 1,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                    BorderColorTransition(
                      animate: slideshowEnabled,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: IconButton(
                          icon: const Icon(FluentIcons.play_resume,
                              color: Colors.white, size: 30),
                          onPressed: () {
                            setState(() {
                              slideshowEnabled = !slideshowEnabled;
                            });
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.chevron_right,
                          color: Colors.white, size: 30),
                      onPressed: () {
                        widget.pageController.animateToPage(
                          widget.pageController.page!.toInt() + 1,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ]),
            ),
        ],
      ),
    );
  }

  // If the infinitelyScrollable true, the page number is calculated modulo the
  // total number of images, effectively creating a looping carousel effect.
  // Otherwise, the index is returned as is.
  int _getPageIndex(int index) {
    if (widget.infinitelyScrollable) {
      return index % widget.easyImageProvider.imageCount;
    }
    return index;
  }
}
