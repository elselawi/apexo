import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'easy_image_provider.dart';
import 'easy_image_view_pager.dart';

/// An internal widget that is used to hold a state to activate/deactivate the ability to
/// swipe-to-dismiss. This needs to be tied to the zoom scale of the current image, since
/// the user needs to be able to pan around on a zoomed-in image without triggering the
/// swipe-to-dismiss gesture.
class EasyImageViewerDismissibleDialog extends StatefulWidget {
  final EasyImageProvider imageProvider;
  final bool immersive;
  final void Function(int) onPressDelete;
  final bool canDelete;
  final void Function(int)? onPageChanged;
  final void Function(int)? onViewerDismissed;
  final bool swipeDismissible;
  final bool doubleTapZoomable;
  final Color backgroundColor;
  final String closeButtonTooltip;
  final bool infinitelyScrollable;

  final Map<String, String>? drawings;
  final List<String>? imageIds;
  final void Function(String, String)? onSaveDrawing;

  /// Refer to [showImageViewerPager] for the arguments
  EasyImageViewerDismissibleDialog(this.imageProvider,
      {super.key,
      this.immersive = true,
      this.onPageChanged,
      this.onViewerDismissed,
      this.swipeDismissible = false,
      this.doubleTapZoomable = false,
      this.infinitelyScrollable = false,
      required this.canDelete,
      required this.onPressDelete,
      required this.backgroundColor,
      required this.closeButtonTooltip,
      this.drawings,
      this.imageIds,
      this.onSaveDrawing});

  @override
  State<EasyImageViewerDismissibleDialog> createState() =>
      _EasyImageViewerDismissibleDialogState();
}

class _EasyImageViewerDismissibleDialogState
    extends State<EasyImageViewerDismissibleDialog> {
  /// This is used to either activate or deactivate the ability to swipe-to-dismissed, based on
  /// whether the current image is zoomed in (scale > 0) or not.
  DismissDirection _dismissDirection = DismissDirection.down;
  void Function()? _internalPageChangeListener;
  late final PageController _pageController;
  final FlyoutController confirmDeleteFlyoutCtrl = FlyoutController();
  bool _isDrawingMode = false;
  bool _showDrawings = true;
  Color _selectedColor = Colors.red;
  bool _isEraserMode = false;

  /// This is needed because of https://github.com/thesmythgroup/easy_image_viewer/issues/27
  /// When no global key was used, the state was re-created on the initial zoom, which
  /// caused the new state to have _pagingEnabled set to true, which in turn broke
  /// panning on the zoomed-in image.
  final _popScopeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pageController =
        PageController(initialPage: widget.imageProvider.initialIndex);
    if (widget.onPageChanged != null) {
      _internalPageChangeListener = () {
        widget.onPageChanged!(_getCurrentPage());
      };
      _pageController.addListener(_internalPageChangeListener!);
    }
  }

  @override
  void dispose() {
    if (_internalPageChangeListener != null) {
      _pageController.removeListener(_internalPageChangeListener!);
    }
    _pageController.dispose();
    confirmDeleteFlyoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Remove this once we release v2.0.0 and can bump the minimum Flutter version to 3.13.0
    final popScopeAwareDialog = PopScope(
        onPopInvokedWithResult: (_, __) {
          _handleDismissal();
        },
        key: _popScopeKey,
        child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              GestureDetector(
                onTap: () {
                  if (!_isDrawingMode) {
                    Navigator.pop(context);
                  }
                },
                child: EasyImageViewPager(
                    easyImageProvider: widget.imageProvider,
                    pageController: _pageController,
                    doubleTapZoomable: widget.doubleTapZoomable,
                    infinitelyScrollable: widget.infinitelyScrollable,
                    drawings: widget.drawings,
                    imageIds: widget.imageIds,
                    onSaveDrawing: widget.onSaveDrawing,
                    isDrawingMode: _isDrawingMode,
                    showDrawings: _showDrawings,
                    selectedColor: _selectedColor,
                    isEraserMode: _isEraserMode,
                    onScaleChanged: (scale) {
                      setState(() {
                        _dismissDirection = scale <= 1.0
                            ? DismissDirection.down
                            : DismissDirection.none;
                      });
                    }),
              ),
              if (widget.onSaveDrawing != null)
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Row(
                              children: [
                                Icon(
                                  _isDrawingMode
                                      ? FluentIcons.edit_solid12
                                      : FluentIcons.edit,
                                  color: _isDrawingMode
                                      ? Colors.blue
                                      : Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Txt(
                                  txt("draw"),
                                  style: FluentTheme.of(context)
                                      .typography
                                      .bodyStrong!
                                      .copyWith(
                                        color: _isDrawingMode
                                            ? Colors.blue
                                            : Colors.white,
                                        fontSize: 16,
                                      ),
                                ),
                              ],
                            ),
                            onPressed: () {
                              setState(() {
                                _isDrawingMode = !_isDrawingMode;
                                if (_isDrawingMode) {
                                  _showDrawings = true;
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          if (_isDrawingMode) ...[
                            _buildColorButton(Colors.red),
                            _buildColorButton(Colors.blue),
                            _buildColorButton(Colors.green),
                            _buildColorButton(Colors.yellow),
                            _buildColorButton(Colors.white),
                            _buildColorButton(Colors.black),
                            const SizedBox(width: 8),
                            Container(
                                width: 1,
                                height: 24,
                                color: Colors.white.withOpacity(0.54)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Row(
                                children: [
                                  Icon(
                                    FluentIcons.erase_tool,
                                    color: _isEraserMode
                                        ? Colors.blue
                                        : Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Txt(
                                    txt("erase"),
                                    style: FluentTheme.of(context)
                                        .typography
                                        .bodyStrong!
                                        .copyWith(
                                          color: _isEraserMode
                                              ? Colors.blue
                                              : Colors.white,
                                          fontSize: 16,
                                        ),
                                  ),
                                ],
                              ),
                              onPressed: () {
                                setState(() {
                                  _isEraserMode = !_isEraserMode;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            Container(
                                width: 1,
                                height: 24,
                                color: Colors.white.withOpacity(0.54)),
                            const SizedBox(width: 8),
                          ],
                          if (_hasDrawings() || _isDrawingMode) ...[
                            if (!_isDrawingMode) ...[
                              const SizedBox(width: 8),
                              Container(
                                  width: 1,
                                  height: 24,
                                  color: Colors.white.withOpacity(0.54)),
                              const SizedBox(width: 8),
                            ],
                            IconButton(
                              icon: Row(
                                children: [
                                  Icon(
                                    _showDrawings
                                        ? FluentIcons.red_eye
                                        : FluentIcons.hide,
                                    color: _showDrawings
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.54),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Txt(
                                    txt("showDrawings"),
                                    style: FluentTheme.of(context)
                                        .typography
                                        .bodyStrong!
                                        .copyWith(
                                          color: _showDrawings
                                              ? Colors.white
                                              : Colors.white.withOpacity(0.54),
                                          fontSize: 16,
                                        ),
                                  ),
                                ],
                              ),
                              onPressed: () {
                                setState(() {
                                  _showDrawings = !_showDrawings;
                                  if (!_showDrawings) {
                                    _isDrawingMode = false;
                                  }
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.canDelete) ...[
                          FlyoutTarget(
                            controller: confirmDeleteFlyoutCtrl,
                            child: IconButton(
                              icon: Row(
                                children: [
                                  const Icon(WindowsIcons.delete,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 4),
                                  Txt(
                                    txt("delete"),
                                    style: FluentTheme.of(context)
                                        .typography
                                        .bodyStrong!
                                        .copyWith(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                  ),
                                ],
                              ),
                              onPressed: () {
                                confirmDeleteFlyoutCtrl.showFlyout(
                                  builder: (context) => ConfirmDeleteFlyout(
                                    onConfirm: () {
                                      if (_pageController.page != null) {
                                        final currentIndex =
                                            _pageController.page!.toInt();
                                        widget.onPressDelete(currentIndex %
                                            widget.imageProvider.imageCount);
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          Navigator.of(context).pop();
                                          _handleDismissal();
                                        });
                                      }
                                    },
                                    controller: confirmDeleteFlyoutCtrl,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 24,
                            color: Colors.white.withOpacity(0.54),
                          ),
                          const SizedBox(width: 8),
                        ],
                        IconButton(
                          icon: Row(
                            children: [
                              const Icon(
                                FluentIcons.clear,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Txt(
                                txt("close"),
                                style: FluentTheme.of(context)
                                    .typography
                                    .bodyStrong!
                                    .copyWith(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                              ),
                            ],
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            _handleDismissal();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ]));

    if (widget.swipeDismissible) {
      return Dismissible(
          direction: _isDrawingMode ? DismissDirection.none : _dismissDirection,
          resizeDuration: null,
          confirmDismiss: (dir) async {
            return true;
          },
          onDismissed: (_) {
            Navigator.of(context).pop();

            _handleDismissal();
          },
          key: const Key('dismissible_easy_image_viewer_dialog'),
          child: popScopeAwareDialog);
    } else {
      return popScopeAwareDialog;
    }
  }

  // Internal function to be called whenever the dialog
  // is dismissed, whether through the Android back button,
  // through the "x" close button, or through swipe-to-dismiss.
  void _handleDismissal() {
    if (widget.onViewerDismissed != null) {
      widget.onViewerDismissed!(_getCurrentPage());
    }

    if (widget.immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (_internalPageChangeListener != null) {
      _pageController.removeListener(_internalPageChangeListener!);
    }
  }

  // Returns the current page number.
  // If the infinitelyScrollable true, the page number is calculated modulo the
  // total number of images, effectively creating a looping carousel effect.
  int _getCurrentPage() {
    var currentPage = _pageController.page?.round() ?? 0;
    if (widget.infinitelyScrollable) {
      currentPage = currentPage % widget.imageProvider.imageCount;
    }
    return currentPage;
  }

  Widget _buildColorButton(Color color) {
    bool isSelected = _selectedColor == color && !_isEraserMode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedColor = color;
          _isEraserMode = false;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.white.withOpacity(0.54),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.5),
                    blurRadius: 6,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
      ),
    );
  }

  bool _hasDrawings() {
    if (widget.drawings == null || widget.imageIds == null) {
      return false;
    }
    int currentIndex = widget.imageProvider.initialIndex;
    if (_pageController.hasClients && _pageController.page != null) {
      currentIndex = _pageController.page!.round();
    }
    currentIndex = currentIndex % widget.imageProvider.imageCount;
    if (currentIndex >= widget.imageIds!.length) return false;
    final imgId = widget.imageIds![currentIndex];
    final drawingStr = widget.drawings![imgId];
    return drawingStr != null && drawingStr.isNotEmpty && drawingStr != "[]";
  }
}
