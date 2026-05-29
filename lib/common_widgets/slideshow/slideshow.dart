import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'src/easy_image_provider.dart';
import 'src/easy_image_viewer_dismissible_dialog.dart';
import 'src/single_image_provider.dart';

export 'src/easy_image_provider.dart' show EasyImageProvider;
export 'src/single_image_provider.dart' show SingleImageProvider;
export 'src/multi_image_provider.dart' show MultiImageProvider;

export 'src/easy_image_view.dart' show EasyImageView;
export 'src/easy_image_view_pager.dart' show EasyImageViewPager;

// Defined here so we don't repeat ourselves
const _defaultBackgroundColor = Colors.black;
const _defaultCloseButtonColor = Colors.white;
const _defaultCloseButtonTooltip = 'Close';

/// Shows the given [imageProvider] in a full-screen [Dialog].
/// Setting [immersive] to false will prevent the top and bottom bars from being hidden.
/// The optional [onViewerDismissed] callback function is called when the dialog is closed.
/// The optional [useSafeArea] boolean defaults to false and is passed to [showDialog].
/// The optional [swipeDismissible] boolean defaults to false and allows swipe-down-to-dismiss.
/// The optional [doubleTapZoomable] boolean defaults to false and allows double tap to zoom.
/// The [backgroundColor] defaults to black, but can be set to any other color.
/// The optional [barrierColor] (in connection with [useSafeArea]) defaults to the [backgroundColor], but can be set to any other color.
/// The [closeButtonTooltip] text is displayed when the user long-presses on the
/// close button and is used for accessibility.
/// The [closeButtonColor] defaults to white, but can be set to any other color.
showImageViewer(
  BuildContext context,
  ImageProvider imageProvider, {
  bool immersive = true,
  void Function()? onViewerDismissed,
  required void Function(int) onPressDelete,
  required bool canDelete,
  bool useSafeArea = false,
  bool swipeDismissible = false,
  bool doubleTapZoomable = false,
  Color backgroundColor = _defaultBackgroundColor,
  Color? barrierColor,
  String closeButtonTooltip = _defaultCloseButtonTooltip,
  Color closeButtonColor = _defaultCloseButtonColor,
  Map<String, String>? drawings,
  List<String>? imageIds,
  void Function(String, String)? onSaveDrawing,
}) {
  return showImageViewerPager(
    context,
    SingleImageProvider(imageProvider),
    immersive: immersive,
    onViewerDismissed:
        onViewerDismissed != null ? (_) => onViewerDismissed() : null,
    useSafeArea: useSafeArea,
    swipeDismissible: swipeDismissible,
    doubleTapZoomable: doubleTapZoomable,
    onPressDelete: onPressDelete,
    canDelete: canDelete,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    closeButtonTooltip: closeButtonTooltip,
    closeButtonColor: closeButtonColor,
    drawings: drawings,
    imageIds: imageIds,
    onSaveDrawing: onSaveDrawing,
  );
}

/// Shows the images provided by the [imageProvider] in a full-screen PageView [Dialog].
/// Setting [immersive] to false will prevent the top and bottom bars from being hidden.
/// The optional [onPageChanged] callback function is called with the index of
/// the image when the user has swiped to another image.
/// The optional [onViewerDismissed] callback function is called with the index of
/// the image that is displayed when the dialog is closed.
/// The optional [useSafeArea] boolean defaults to false and is passed to [showDialog].
/// The optional [swipeDismissible] boolean defaults to false and allows swipe-down-to-dismiss.
/// The optional [doubleTapZoomable] boolean defaults to false and allows double tap to zoom.
/// The optional [infinitelyScrollable] boolean defaults to false and allows infinite scrolling.
/// The [backgroundColor] defaults to black, but can be set to any other color.
/// The optional [barrierColor] (in connection with [useSafeArea]) defaults to the [backgroundColor], but can be set to any other color.
/// The [closeButtonTooltip] text is displayed when the user long-presses on the
/// close button and is used for accessibility.
/// The [closeButtonColor] defaults to white, but can be set to any other color.
showImageViewerPager(BuildContext context, EasyImageProvider imageProvider,
    {bool immersive = true,
    void Function(int)? onPageChanged,
    void Function(int)? onViewerDismissed,
    required void Function(int) onPressDelete,
    required bool canDelete,
    bool useSafeArea = false,
    bool swipeDismissible = false,
    bool doubleTapZoomable = false,
    bool infinitelyScrollable = false,
    Color backgroundColor = _defaultBackgroundColor,
    Color? barrierColor,
    String closeButtonTooltip = _defaultCloseButtonTooltip,
    Color closeButtonColor = _defaultCloseButtonColor,
    Map<String, String>? drawings,
    List<String>? imageIds,
    void Function(String, String)? onSaveDrawing}) {
  if (immersive) {
    // Hide top and bottom bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  return showDialog(
      context: context,
      barrierDismissible: true,
      dismissWithEsc: true,
      barrierColor: barrierColor ?? backgroundColor,
      builder: (context) {
        return EasyImageViewerDismissibleDialog(
          imageProvider,
          immersive: immersive,
          onPageChanged: onPageChanged,
          onViewerDismissed: onViewerDismissed,
          onPressDelete: onPressDelete,
          canDelete: canDelete,
          swipeDismissible: swipeDismissible,
          doubleTapZoomable: doubleTapZoomable,
          infinitelyScrollable: infinitelyScrollable,
          backgroundColor: backgroundColor,
          closeButtonTooltip: closeButtonTooltip,
          drawings: drawings,
          imageIds: imageIds,
          onSaveDrawing: onSaveDrawing,
        );
      });
}
