import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/common_widgets/dialogs/loading_blocking.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/common_widgets/slideshow/slideshow.dart';
import 'package:fluent_ui/fluent_ui.dart';

class GridGallery extends StatefulWidget {
  final String rowId;
  final List<String> imgs;
  final void Function(String img) onPressDelete;
  final int countPerLine;
  final double rowWidth;
  final double? size;
  final int clipCount;
  final bool progress;
  final bool showPlayIcon;
  final bool showDeleteMiniButton;
  final bool canDelete;
  final Map<String, String>? drawings;
  final void Function(String, String)? onSaveDrawing;

  const GridGallery({
    super.key,
    required this.rowId,
    required this.imgs,
    required this.progress,
    required this.onPressDelete,
    required this.showDeleteMiniButton,
    required this.canDelete,
    this.countPerLine = 3,
    this.rowWidth = 350,
    this.size,
    this.clipCount = 0,
    this.showPlayIcon = true,
    this.drawings,
    this.onSaveDrawing,
  });

  @override
  State<GridGallery> createState() => _GridGalleryState();
}

class _GridGalleryState extends State<GridGallery> {
  final Set<ImageProvider> _imageProviders = {};

  @override
  void dispose() {
    super.dispose();
    for (final imageProvider in _imageProviders) {
      imageProvider.evict();
    }
  }

  @override
  Widget build(BuildContext context) {
    const double spacing = 4;
    final double calculatedSized =
        ((widget.rowWidth - (spacing * (widget.countPerLine * 4))) /
            widget.countPerLine);
    return SizedBox(
      width: widget.rowWidth,
      child: Padding(
        padding: const EdgeInsets.all(spacing),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.start,
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          spacing: spacing,
          runSpacing: spacing,
          children: [
            ...List<Widget>.from(List.generate(widget.imgs.length, (index) {
              if (widget.clipCount > 0 && index >= widget.clipCount) {
                return null;
              }
              return SizedBox(
                width: widget.size ??
                    calculatedSized, // Adjust for desired column count
                height: widget.size ?? calculatedSized,
                child: _buildSingleImage(context, index),
              );
            }).where((e) => e != null)),
            if (widget.imgs.length > 1 && widget.showPlayIcon)
              SizedBox(
                width: widget.size ??
                    calculatedSized, // Adjust for desired column count
                height: widget.size ?? calculatedSized,
                child: FilledButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                        Colors.grey.withValues(alpha: 0.8)),
                    foregroundColor: const WidgetStatePropertyAll(Colors.white),
                    elevation: const WidgetStatePropertyAll(5),
                  ),
                  onPressed: () => openSlideShow(context, 0),
                  child:
                      Icon(FluentIcons.play_resume, size: calculatedSized / 2),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildSingleImage(BuildContext context, int index) {
    final img = widget.imgs[index];
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<ImageProvider<Object>?>(
          future: getImage(widget.rowId, img),
          builder: (context, snapshot) {
            if (snapshot.data != null) {
              _imageProviders.add(snapshot.data!);
            }
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData) {
              return GestureDetector(
                onTap: () => openSingleImage(context, img),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image(
                    image: snapshot.data!,
                    fit: BoxFit.cover, // Crops the image to fit the space
                  ),
                ),
              );
            } else {
              return const Center(
                child: ProgressRing(), // Placeholder while loading
              );
            }
          },
        ),
        if (widget.showDeleteMiniButton &&
            login.permissions[PInt.photos] == 1 &&
            widget.progress == false)
          Positioned(
            top: 4,
            right: 4,
            child: ImageDeleteButton(widget: widget, img: img),
          ),
        if ((index == widget.clipCount - 1 &&
            widget.imgs.length > widget.clipCount))
          SizedBox.expand(
            child: GestureDetector(
              onTap: () => widget.showPlayIcon
                  ? openSingleImage(context, widget.imgs[index])
                  : openSlideShow(context, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8.0),
                  boxShadow: kElevationToShadow[1],
                  border: Border.all(color: Colors.white, width: 0.4),
                ),
                child: Center(
                  child: Text(
                      "+${(widget.imgs.length - widget.clipCount).toString()}",
                      style:
                          const TextStyle(color: Colors.white, fontSize: 18)),
                ),
              ),
            ),
          )
      ],
    );
  }

  void openSingleImage(BuildContext context, String img) async {
    final closeDialog =
        showLoadingBlockingDialog(context, txt("gettingImages"));
    ImageProvider? provider;
    try {
      provider = await getImage(widget.rowId, img, false) ??
          const AssetImage("assets/images/missing.png");
    } catch (e) {
      closeDialog();
      showErrorMessage(e, "openingImageFromGrid");
    } finally {
      closeDialog();
    }
    if (context.mounted && provider != null) {
      _imageProviders.add(provider);
      showImageViewer(
        context,
        provider,
        canDelete: widget.canDelete,
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        doubleTapZoomable: true,
        immersive: false,
        swipeDismissible: true,
        drawings: widget.drawings,
        imageIds: [img],
        onSaveDrawing: widget.onSaveDrawing,
        onPressDelete: (_) {
          widget.onPressDelete(img);
        },
      );
    }
  }

  void openSlideShow(BuildContext context, int initialIndex) async {
    final closeDialog =
        showLoadingBlockingDialog(context, txt("gettingImages"));
    MultiImageProvider? multiImageProvider;
    try {
      final List<ImageProvider<Object>> list = (await Future.wait(widget.imgs
              .map((img) => getImage(widget.rowId, img, false))
              .toList()))
          .map((el) => el ?? const AssetImage("assets/images/missing.png"))
          .toList();
      multiImageProvider = MultiImageProvider(list, initialIndex: initialIndex);
    } catch (e) {
      closeDialog();
      showErrorMessage(e, "openingMultipleImagesFromGrid");
    } finally {
      closeDialog();
    }

    if (multiImageProvider != null &&
        context.mounted &&
        multiImageProvider.imageCount > 0) {
      _imageProviders.addAll(multiImageProvider.imageProviders);
      showImageViewerPager(
        context,
        multiImageProvider,
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        doubleTapZoomable: true,
        immersive: false,
        swipeDismissible: true,
        infinitelyScrollable: true,
        canDelete: widget.canDelete,
        drawings: widget.drawings,
        imageIds: widget.imgs,
        onSaveDrawing: widget.onSaveDrawing,
        onPressDelete: (int index) {
          widget.onPressDelete(widget.imgs[index]);
        },
      );
    }
  }
}

class ImageDeleteButton extends StatefulWidget {
  const ImageDeleteButton({
    super.key,
    required this.widget,
    required this.img,
  });

  final GridGallery widget;
  final String img;

  @override
  State<ImageDeleteButton> createState() => _ImageDeleteButtonState();
}

class _ImageDeleteButtonState extends State<ImageDeleteButton> {
  final FlyoutController deleteConfirmationFlyout = FlyoutController();

  @override
  void dispose() {
    deleteConfirmationFlyout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: deleteConfirmationFlyout,
      child: IconButton(
        style: ButtonStyle(
            backgroundColor:
                WidgetStatePropertyAll(FluentTheme.of(context).menuColor)),
        icon: const Icon(WindowsIcons.delete),
        onPressed: () async {
          await flyoutFocusFix(context);
          deleteConfirmationFlyout.showFlyout(builder: (context) {
            return FlyoutContent(
              child: ConfirmDeleteFlyout(
                controller: deleteConfirmationFlyout,
                onConfirm: () => widget.widget.onPressDelete.call(widget.img),
              ),
            );
          });
        },
      ),
    );
  }
}
