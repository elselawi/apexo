import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apexo/common_widgets/adaptive_hover_widget.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/import_photos_dialog.dart';
import 'package:apexo/common_widgets/dialogs/loading_blocking.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/dicom/open_dicom_viewer_panel.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/common_widgets/slideshow/slideshow.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:image_picker/image_picker.dart';

// ─── Constants ────────────────────────────────────────────────────────────

const double _kGallerySpacing = 5.0;
const int _kGridColumns = 3;

// ─── Upload source enum ───────────────────────────────────────────────────

enum UploadSource { camera, gallery, link, files }

// ─── Shared helpers ───────────────────────────────────────────────────────

ButtonStyle get _deleteButtonStyle => const ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
    );

// ─── Gallery delete button ───────────────────────────────────────────────

class _GalleryDeleteButton extends StatelessWidget {
  final VoidCallback onConfirm;
  final String rowId;
  final String name;

  const _GalleryDeleteButton({
    required this.onConfirm,
    required this.rowId,
    required this.name,
  });

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

class GalleryDownloadButton extends StatefulWidget {
  final String? rowId;
  final String name;
  final String? buttonLabel;

  const GalleryDownloadButton({
    super.key,
    this.rowId,
    this.buttonLabel,
    required this.name,
  });

  @override
  State<GalleryDownloadButton> createState() => GalleryDownloadButtonState();
}

class GalleryDownloadButtonState extends State<GalleryDownloadButton> {
  bool _isDownloading = false;

  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      await downloadFile(widget.rowId, widget.name);
    } catch (e) {
      if (mounted) {
        showErrorMessage(e, "downloadingFile");
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _isDownloading
          ? const SizedBox(
              width: 18, height: 18, child: ProgressRing(strokeWidth: 2))
          : ButtonContent(WindowsIcons.download, widget.buttonLabel ?? "",
              size: 18),
      onPressed: _isDownloading ? null : _download,
      style: const ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(Colors.white),
      ),
    );
  }
}

// ─── File preview widget ─────────────────────────────────────────────────

/// A unified preview widget that auto-detects whether [name] is an image
/// (by extension) and shows either a loaded thumbnail or a file placeholder.
///
/// When [imageProvider] is supplied (e.g. from an already-open viewer), it is
/// used directly. Otherwise [rowId] + [name] are used to load a thumbnail.
class FileDeletePreview extends StatelessWidget {
  final String? rowId;
  final String name;
  final double size;
  final ImageProvider? imageProvider;

  const FileDeletePreview({
    super.key,
    this.rowId,
    required this.name,
    this.size = 80,
    this.imageProvider,
  });

  @override
  Widget build(BuildContext context) {
    // Pre-loaded image takes priority
    if (imageProvider != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image(
          image: imageProvider!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
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

class GalleryUploadConfig {
  final Store? store;
  final Future<void> Function(List<String> newNames) modelPersistence;
  final bool canUpload;
  final Set<UploadSource> acceptedSources;

  const GalleryUploadConfig({
    this.store,
    required this.modelPersistence,
    required this.canUpload,
    this.acceptedSources = const {
      UploadSource.camera,
      UploadSource.gallery,
      UploadSource.link,
      UploadSource.files
    },
  });
}

// ─── GridGallery widget ───────────────────────────────────────────────────

class GridGallery extends StatefulWidget {
  final String rowId;
  final List<String> imgs;

  /// DICOM X-ray filenames (`*.dcm`/`*.dicom`) rendered alongside
  /// [imgs] as PNG previews. Each cell shows a "DCM" badge; tapping opens
  /// the interactive viewer instead of the photo slideshow.
  final List<String> dcmImgs;
  final Future<void> Function(String img) onPressDelete;

  /// Delete handler for DCM entries. If `null`, [onPressDelete] is reused —
  /// callers that pass [dcmImgs] should supply this so both `.dcm` + `.png`
  /// are removed (see `Store.deleteDcmImg`).
  final Future<void> Function(String dcmName)? onPressDeleteDcm;

  /// Tap handler for DCM entries. Defaults to [openDicomViewerPanel] when
  /// `null`; supplied explicitly so callers (e.g. read-only previews) can
  /// override or suppress it.
  final void Function(BuildContext context, String rowId, String dcmName)?
      onTapDcm;
  final int countPerLine;
  final double rowWidth;
  final double? size;
  final int clipCount;
  final bool slideshowEnabled;
  final bool canDelete;
  final Map<String, String>? drawings;
  final void Function(String, String)? onSaveDrawing;
  final VoidCallback? onTapClip;
  final void Function(bool)? onProgress;
  final GalleryUploadConfig? uploadConfig;

  const GridGallery({
    super.key,
    required this.rowId,
    required this.imgs,
    this.dcmImgs = const [],
    required this.onPressDelete,
    this.onPressDeleteDcm,
    this.onTapDcm,
    required this.canDelete,
    this.countPerLine = 3,
    this.rowWidth = 350,
    this.size,
    this.clipCount = 0,
    this.slideshowEnabled = false,
    this.drawings,
    this.onSaveDrawing,
    this.onTapClip,
    this.onProgress,
    this.uploadConfig,
  });

  @override
  State<GridGallery> createState() => _GridGalleryState();
}

class _GridGalleryState extends State<GridGallery>
    with TickerProviderStateMixin {
  final Set<ImageProvider> _imageProviders = {};
  late AnimationController _entranceController;
  late List<Animation<double>> _entranceAnimations;
  final FlyoutController _uploadFlyoutCtrl = FlyoutController();
  bool _isUploading = false;
  bool _isDeleting = false;
  final Set<String> _downloadingFiles = {};

  int get _visibleCount => _displayImgs.isNotEmpty
      ? math.min(
          widget.clipCount > 0 ? widget.clipCount : _displayImgs.length,
          _displayImgs.length,
        )
      : 0;

  /// Photos + DCM X-rays, DCMs appended after photos. Layout, clipping, and
  /// tap/delete routing all operate on this combined view; per-cell DCM
  /// behaviour is decided by membership in [_dcmNames] (NOT by name pattern —
  /// a `.dcm` file attached to a note/expense stays a regular file).
  List<String> get _displayImgs => [...widget.imgs, ...widget.dcmImgs];

  /// The set of names that are DCM X-rays (sourced from [GridGallery.dcmImgs]).
  /// Only these get the badge / spinner placeholder / viewer routing /
  /// dedicated delete. A `.dcm`-named entry in `imgs` (e.g. a note attachment)
  /// is NOT in this set and keeps regular-file behaviour.
  Set<String> get _dcmNames => widget.dcmImgs.toSet();

  /// Photos only — the slideshow is for images; DCMs open the viewer.
  List<String> get viewableImgs {
    return widget.imgs.where((name) => isAnImageName(name)).toList();
  }

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _setupEntranceAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceController.forward();
    });
  }

  void _setupEntranceAnimations() {
    final total = _visibleCount;
    _entranceAnimations = List.generate(total, (index) {
      final start = (index / math.max(total, 1)) * 0.35;
      return CurvedAnimation(
        parent: _entranceController,
        curve: Interval(
          start,
          math.min(start + 0.55, 1.0),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  void didUpdateWidget(GridGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imgs != widget.imgs ||
        oldWidget.dcmImgs != widget.dcmImgs ||
        oldWidget.clipCount != widget.clipCount) {
      _setupEntranceAnimations();
      _entranceController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _uploadFlyoutCtrl.dispose();
    for (final provider in _imageProviders) {
      provider.evict();
    }
    super.dispose();
  }

  // ── Upload logic ──

  void _showUploadMenu() async {
    final cfg = widget.uploadConfig;
    if (cfg == null || !cfg.canUpload) return;
    final src = cfg.acceptedSources;
    await flyoutFocusFix(context);
    _uploadFlyoutCtrl.showFlyout(
      builder: (ctx) => MenuFlyout(
        items: [
          if (src.contains(UploadSource.camera) &&
              ImagePicker().supportsImageSource(ImageSource.camera))
            MenuFlyoutItem(
              text: Txt(txt("camera")),
              leading: const Icon(WindowsIcons.camera),
              onPressed: _uploadFromCamera,
            ),
          if (src.contains(UploadSource.gallery) &&
              ImagePicker().supportsImageSource(ImageSource.gallery))
            MenuFlyoutItem(
              text: Txt(txt("pickPhotos")),
              leading: const Icon(WindowsIcons.photo2),
              onPressed: _uploadFromGallery,
            ),
          if (src.contains(UploadSource.files))
            MenuFlyoutItem(
              text: Txt(txt("pickFiles")),
              leading: const Icon(WindowsIcons.document),
              onPressed: _uploadFiles,
            ),
          if (src.contains(UploadSource.link))
            MenuFlyoutItem(
              text: Txt(txt("link")),
              leading: const Icon(WindowsIcons.link),
              onPressed: _importFromLink,
            ),
        ],
      ),
    );
  }

  Future<void> _doDelete(String img) async {
    if (_isDeleting) return;
    setState(() {
      _isDeleting = true;
      widget.onProgress?.call(true);
    });
    try {
      // DCM X-rays need a dedicated delete (removes both .dcm + .png preview).
      // Only entries explicitly in `dcmImgs` get this path — a `.dcm` file
      // attached to a note/expense deletes via the regular `onPressDelete`.
      if (_dcmNames.contains(img)) {
        final dcmDelete = widget.onPressDeleteDcm ?? widget.onPressDelete;
        await dcmDelete(img);
      } else {
        await widget.onPressDelete(img);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          widget.onProgress?.call(false);
        });
      }
    }
  }

  bool get _deleteEnabled => widget.canDelete && !_isDeleting;

  Future<void> _uploadFromGallery() async {
    final cfg = widget.uploadConfig;
    if (cfg == null) return;
    final res = await ImagePicker().pickMultiImage(limit: 10);
    if (res.isEmpty || !mounted) return;

    await _runUpload(cfg, () async {
      final names = <String>[];
      for (final img in res) {
        final name = await handleNewImage(
          rowID: widget.rowId,
          sourcePath: img.path,
          sourceFile: img,
          targetStore: cfg.store,
        );
        names.add(name);
        await cfg.modelPersistence([name]);
      }
      await cfg.modelPersistence(names);
      return names;
    }, errorTag: "uploadingImageToGallery");
  }

  Future<void> _uploadFromCamera() async {
    final cfg = widget.uploadConfig;
    if (cfg == null) return;
    final res = await ImagePicker().pickImage(source: ImageSource.camera);
    if (res == null || !mounted) return;

    await _runUpload(cfg, () async {
      final name = await handleNewImage(
        rowID: widget.rowId,
        sourcePath: res.path,
        sourceFile: res,
        targetStore: cfg.store,
      );
      await cfg.modelPersistence([name]);
      return [name];
    }, errorTag: "uploadingImageToCamera");
  }

  Future<void> _uploadFiles() async {
    final cfg = widget.uploadConfig;
    if (cfg == null) return;
    final res = await FilePicker.pickFiles(allowMultiple: true);
    if (res == null || res.files.isEmpty || !mounted) return;

    await _runUpload(cfg, () async {
      final names = <String>[];
      for (final file in res.files) {
        if (file.path == null) continue;
        final name = await handleNewImage(
          rowID: widget.rowId,
          sourcePath: file.path!,
          targetStore: cfg.store,
          sourceFile: file.xFile,
        );
        names.add(name);
        await cfg.modelPersistence([name]);
      }
      await cfg.modelPersistence(names);
      return names;
    }, errorTag: "uploadingFiles");
  }

  /// Runs [work], manages the uploading spinner, handles errors.
  /// [work] is responsible for calling [GalleryUploadConfig.onPhotosAdded]
  /// incrementally as each item completes. Returns `true` on success.
  Future<bool> _runUpload(
    GalleryUploadConfig cfg,
    Future<List<String>> Function() work, {
    required String errorTag,
  }) async {
    setState(() => _isUploading = true);
    widget.onProgress?.call?.call(true);
    try {
      await work();
      return true;
    } catch (e, s) {
      showErrorMessage(e, errorTag);
      login.askForLoginAgain(e);
      logger("Error during $errorTag: $e", s);
      return false;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
        widget.onProgress?.call(false);
      }
    }
  }

  Future<void> _importFromLink() async {
    _uploadFlyoutCtrl.forceClose();
    final cfg = widget.uploadConfig;
    if (cfg == null) return;
    final urls = await showDialog<List<String>>(
      context: context,
      builder: (_) => const ImportDialog(),
    );
    if (urls == null || urls.isEmpty || !mounted) return;
    await _runUpload(cfg, () async {
      final names = <String>[];
      for (final link in urls) {
        final name = await handleNewImage(
          rowID: widget.rowId,
          sourcePath: link,
          targetStore: cfg.store,
        );
        names.add(name);
        await cfg.modelPersistence([name]);
      }
      await cfg.modelPersistence(names);
      return names;
    }, errorTag: "uploadingImageToGallery");
  }

  // ── Slideshow / viewer ──

  void _handleFileTap(String img) {
    // DCM X-rays open the interactive viewer (which parses the raw .dcm
    // itself — no dependency on the PNG preview being ready yet). Only entries
    // explicitly in `dcmImgs` route here — a `.dcm` file attached to a
    // note/expense falls through to the regular download path below.
    if (_dcmNames.contains(img)) {
      final onTapDcm = widget.onTapDcm;
      if (onTapDcm != null) {
        onTapDcm(context, widget.rowId, img);
      } else {
        openDicomViewerPanel(context, widget.rowId, img);
      }
      return;
    }
    if (!isAnImageName(img)) {
      setState(() => _downloadingFiles.add(img));
      downloadFile(widget.rowId, img).whenComplete(() {
        if (mounted) setState(() => _downloadingFiles.remove(img));
      });
      return;
    }
    _openSingleImage(img);
  }

  Future<void> _openSingleImage(String img) async {
    final provider = await _loadImages([img]);
    if (provider == null || !context.mounted) return;
    showImageViewer(
      context,
      provider.first,
      canDelete: _deleteEnabled,
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      doubleTapZoomable: true,
      immersive: false,
      swipeDismissible: true,
      drawings: widget.drawings,
      imageIds: [img],
      onSaveDrawing: widget.onSaveDrawing,
      onPressDelete: (_) => _doDelete(img),
    );
  }

  Future<void> _openSlideShow([int initialIndex = 0]) async {
    final providers = await _loadImages(viewableImgs);
    if (providers == null || !context.mounted) return;
    final multi = MultiImageProvider(providers, initialIndex: initialIndex);
    showImageViewerPager(
      context,
      multi,
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      doubleTapZoomable: true,
      immersive: false,
      swipeDismissible: true,
      infinitelyScrollable: true,
      canDelete: _deleteEnabled,
      drawings: widget.drawings,
      imageIds: viewableImgs,
      onSaveDrawing: widget.onSaveDrawing,
      onPressDelete: (int index) => _doDelete(viewableImgs[index]),
    );
  }

  /// Loads [imgs] with a blocking dialog, caches providers, and returns them.
  /// Returns `null` if loading fails or the widget is no longer mounted.
  Future<List<ImageProvider<Object>>?> _loadImages(List<String> imgs) async {
    final closeDialog =
        showLoadingBlockingDialog(context, txt("gettingImages"));
    try {
      final providers = (await Future.wait(
        imgs.map((img) => getImage(widget.rowId, img, false)),
      ))
          .map((p) =>
              p ??
              const AssetImage("assets/images/missing.png")
                  as ImageProvider<Object>)
          .toList();
      _imageProviders.addAll(providers);
      return providers;
    } catch (e, s) {
      showErrorMessage(e, "openingImagesFromGrid");
      logger("Error loading images: $e", s);
      return null;
    } finally {
      closeDialog();
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final double calculatedSize =
        ((widget.rowWidth - (_kGallerySpacing * (widget.countPerLine * 2))) /
                widget.countPerLine)
            .clamp(40.0, 100.0);
    final double primarySize =
        widget.size != null ? math.min(widget.size!, 100.0) : calculatedSize;

    final Widget content;
    if (_displayImgs.isEmpty) {
      if (widget.uploadConfig == null) return const SizedBox.shrink();
      content = _buildEmptyState();
    } else if (primarySize < 90) {
      content = _buildSimpleLayout(context, primarySize);
    } else {
      content = _FeaturedMasonry(
        rowId: widget.rowId,
        imgs: _displayImgs,
        width: widget.rowWidth - _kGallerySpacing * 2,
        canDelete: _deleteEnabled,
        clipCount: widget.clipCount,
        imageProviders: _imageProviders,
        downloadingFiles: _downloadingFiles,
        onTapImage: (i) => _handleFileTap(_displayImgs[i]),
        onDeleteImage: (i) => _doDelete(_displayImgs[i]),
        dcmNames: _dcmNames,
        onTapClip: widget.onTapClip,
      );
    }

    return SizedBox(
      width: widget.rowWidth,
      child: Padding(
        padding: const EdgeInsets.all(_kGallerySpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            Row(
              spacing: 5,
              children: [
                if (widget.uploadConfig != null)
                  FlyoutTarget(
                    controller: _uploadFlyoutCtrl,
                    child: Button(
                      onPressed: _isUploading ? null : _showUploadMenu,
                      child: ButtonContent(
                        WindowsIcons.add,
                        txt("add"),
                        inProgress: _isUploading,
                      ),
                    ),
                  ),
                if (widget.slideshowEnabled && viewableImgs.length > 1)
                  Button(
                    onPressed: _openSlideShow,
                    child: ButtonContent(
                      WindowsIcons.slideshow,
                      txt("photoSlideshow"),
                    ),
                  )
              ],
            ),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: widget.rowWidth,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.solidBackgroundFillColorBase,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: FluentTheme.of(context).resources.cardStrokeColorDefault,
          width: 1,
        ),
      ),
      child: Center(
        child: Row(
          spacing: 5,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(WindowsIcons.warning),
            Txt(
              txt("noFiles"),
              style: FluentTheme.of(context).typography.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleLayout(BuildContext context, double tileSize) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: _kGallerySpacing,
      runSpacing: _kGallerySpacing,
      children: [
        for (int i = 0; i < _visibleCount; i++)
          _EntranceWrapper(
            animation:
                i < _entranceAnimations.length ? _entranceAnimations[i] : null,
            child: SizedBox(
              width: tileSize,
              height: tileSize,
              child: _ImageTile(
                img: _displayImgs[i],
                rowId: widget.rowId,
                isDcm: _dcmNames.contains(_displayImgs[i]),
                canDelete: _deleteEnabled,
                showClipOverlay: widget.clipCount > 0 &&
                    i == widget.clipCount - 1 &&
                    _displayImgs.length > widget.clipCount,
                remainingCount: _displayImgs.length - widget.clipCount + 1,
                onTap: () => _handleFileTap(_displayImgs[i]),
                onDelete: () => _doDelete(_displayImgs[i]),
                imageProviders: _imageProviders,
                downloadingFiles: _downloadingFiles,
                tileSize: tileSize,
                onTapClip: widget.onTapClip,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Entrance animation wrapper ───────────────────────────────────────────

class _EntranceWrapper extends StatelessWidget {
  final Widget child;
  final Animation<double>? animation;

  const _EntranceWrapper({required this.child, this.animation});

  @override
  Widget build(BuildContext context) {
    if (animation == null) return child;
    return AnimatedBuilder(
      animation: animation!,
      builder: (_, child) => Opacity(
        opacity: animation!.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - animation!.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ─── Individual image tile ────────────────────────────────────────────────

class _ImageTile extends StatefulWidget {
  final String img;
  final String rowId;

  /// When `true`, [img] is a `.dcm`/`.dicom` X-ray. The tile renders the PNG
  /// preview (via `getImage`, which auto-redirects `.dcm` → `.dcm.png`), shows
  /// a "DCM" badge, displays a spinner placeholder while the PNG is still
  /// generating, and rebuilds when `dicomPngReady` bumps.
  final bool isDcm;
  final bool canDelete;
  final bool showClipOverlay;
  final int remainingCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Set<ImageProvider> imageProviders;
  final Set<String> downloadingFiles;
  final double tileSize;
  final bool useOriginal;
  final VoidCallback? onTapClip;

  const _ImageTile({
    required this.img,
    required this.rowId,
    this.isDcm = false,
    required this.canDelete,
    required this.showClipOverlay,
    required this.remainingCount,
    required this.onTap,
    required this.onDelete,
    required this.imageProviders,
    required this.downloadingFiles,
    required this.tileSize,
    this.useOriginal = false,
    this.onTapClip,
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  bool _isHovered = false;
  bool _hasLoaded = false;
  late Future<ImageProvider<Object>?> _imageFuture;
  StreamSubscription<int>? _pngReadySub;

  bool get _showHoverEffects => _isHovered;
  bool get _showLargeHoverEffects => _showHoverEffects && widget.tileSize >= 56;

  @override
  void initState() {
    super.initState();
    _imageFuture = getImage(widget.rowId, widget.img, !widget.useOriginal);
    // DCM previews are generated lazily; rebuild the cell each time a new
    // PNG lands so a placeholder flips to the real preview.
    if (widget.isDcm) {
      _pngReadySub = dicomPngReady.stream.listen((_) {
        if (!mounted) return;
        setState(() {
          _hasLoaded = false;
          _imageFuture =
              getImage(widget.rowId, widget.img, !widget.useOriginal);
        });
      });
    }
  }

  @override
  void didUpdateWidget(_ImageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.img != widget.img ||
        oldWidget.useOriginal != widget.useOriginal) {
      setState(() {
        _hasLoaded = false;
        _imageFuture = getImage(widget.rowId, widget.img, !widget.useOriginal);
      });
    }
  }

  @override
  void dispose() {
    _pngReadySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AdaptiveHoverWidget(
      onEnter: () => setState(() => _isHovered = true),
      onExit: () => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: _showHoverEffects ? 0.3 : 0.10),
                blurRadius: _isHovered ? 12 : 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: theme.resources.cardStrokeColorDefault,
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_hasLoaded)
                  widget.isDcm
                      ? _buildDcmPlaceholder()
                      : const _ShimmerPlaceholder(),
                _buildImageContent(theme),
                if (widget.isDcm) const _DcmBadge(),
                if (widget.downloadingFiles.contains(widget.img))
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            gradient: RadialGradient(colors: [
                          Colors.black.withValues(alpha: 0.5),
                          Colors.transparent
                        ])),
                        child: const SizedBox(
                          width: 25,
                          height: 25,
                          child: ProgressRing(backgroundColor: Colors.white),
                        ),
                      ),
                    ),
                  ),
                if (_showLargeHoverEffects) _buildHoverGradient(),
                if (widget.showClipOverlay)
                  GestureDetector(
                    onTap: widget.onTapClip,
                    child: _ClipCountOverlay(count: widget.remainingCount),
                  ),
                // Download / delete buttons on hover
                if (_showLargeHoverEffects)
                  Positioned(
                    right: 8,
                    bottom: 0,
                    child: Row(
                      spacing: 10,
                      children: [
                        if (widget.canDelete)
                          _GalleryDeleteButton(
                            onConfirm: widget.onDelete,
                            rowId: widget.rowId,
                            name: widget.img,
                          ),
                        GalleryDownloadButton(
                          rowId: widget.rowId,
                          name: widget.img,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHoverGradient() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: widget.tileSize * 0.45,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.7),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent(FluentThemeData theme) {
    return FutureBuilder<ImageProvider<Object>?>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (!_hasLoaded) {
            _hasLoaded = true;
            if (snapshot.data != null) {
              widget.imageProviders.add(snapshot.data!);
            }
          }
          if (snapshot.hasData) {
            return Image(
              image: snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => widget.isDcm
                  ? _buildDcmPlaceholder()
                  : _buildFilePlaceholder(theme),
            );
          }
          // No preview yet: DCM shows the generating spinner; other files
          // show the file-type icon placeholder.
          return widget.isDcm
              ? _buildDcmPlaceholder()
              : _buildFilePlaceholder(theme);
        }
        // Loading: DCM shows the spinner; photos leave the shimmer visible.
        return widget.isDcm ? _buildDcmPlaceholder() : const SizedBox.expand();
      },
    );
  }

  /// Placeholder shown while a DCM's PNG preview is still being generated
  /// (or has failed to generate). A spinner conveys "in progress"; the
  /// tooltip explains what's happening.
  Widget _buildDcmPlaceholder() {
    return Tooltip(
      message: txt("generatingPreview"),
      child: Container(
        color:
            FluentTheme.of(context).resources.cardBackgroundFillColorSecondary,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: ProgressRing(strokeWidth: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildFilePlaceholder(FluentThemeData theme) {
    return _FileThumbnail(
      name: widget.img,
      iconSize: widget.tileSize * 0.5,
      showLabel: widget.tileSize >= 45,
      labelWidth: widget.tileSize,
    );
  }
}

// ─── DCM badge overlay ────────────────────────────────────────────────────

/// Small "DCM" badge rendered in the top-left corner of a gallery cell to
/// distinguish X-ray previews from regular photos.
class _DcmBadge extends StatelessWidget {
  const _DcmBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF0078D4),
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          txt("dcm"),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ─── File thumbnail ───────────────────────────────────────────────────────

class _FileThumbnail extends StatelessWidget {
  final String name;
  final double iconSize;
  final bool showLabel;
  final double? labelWidth;

  const _FileThumbnail({
    required this.name,
    required this.iconSize,
    this.showLabel = true,
    this.labelWidth,
  });

  String get _ext => name.contains('.') ? name.split('.').last : '';
  String get _baseName => displayNameForFile(name).replaceAll('.$_ext', '');

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      color: theme.resources.cardBackgroundFillColorSecondary,
      width: labelWidth ?? iconSize + 10,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(WindowsIcons.document,
                      size: iconSize, color: theme.inactiveColor),
                  if (_ext.isNotEmpty && _ext.length <= 5)
                    Positioned(
                      right: iconSize * 0.5 - 15,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.inactiveColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _ext.toUpperCase(),
                          style: theme.typography.caption?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: theme.inactiveBackgroundColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (showLabel) ...[
                const SizedBox(height: 2),
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    _baseName,
                    style: theme.typography.bodyStrong?.copyWith(
                      color: theme.inactiveColor,
                      fontSize: ((iconSize.clamp(55, 120) - 55) / 13) + 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shimmer loading placeholder ──────────────────────────────────────────

class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => IgnorePointer(
        child: CustomPaint(
          painter: _ShimmerPainter(
            progress: _controller.value,
            isDark: isDark,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _ShimmerPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE6E6E6);
    final highlightColor =
        isDark ? const Color(0xFF454545) : const Color(0xFFF2F2F2);

    // Base fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = baseColor,
    );

    // Moving highlight band
    final bandWidth = size.width * 0.6;
    final bandLeft = (progress * (size.width + bandWidth)) - bandWidth;

    canvas.drawRect(
      Rect.fromLTWH(
        bandLeft.clamp(0.0, size.width),
        0,
        math.min(bandWidth, size.width),
        size.height,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bandLeft, 0),
          Offset(bandLeft + bandWidth, 0),
          [baseColor, highlightColor, baseColor],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter old) => old.progress != progress;
}

// ─── "+N" frosted overlay ─────────────────────────────────────────────────

class _ClipCountOverlay extends StatelessWidget {
  final int count;

  const _ClipCountOverlay({required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: FluentTheme.of(context).resources.cardStrokeColorDefault,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.white)
                      .withValues(alpha: 0.5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                "+$count",
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Featured masonry ─────────────────────────────────────────────────────

class _FeaturedMasonry extends StatefulWidget {
  final String rowId;
  final List<String> imgs;
  final double width;
  final bool canDelete;
  final int clipCount;
  final Set<ImageProvider> imageProviders;
  final Set<String> downloadingFiles;
  final void Function(int index) onTapImage;
  final void Function(int index) onDeleteImage;
  final VoidCallback? onTapClip;

  /// Names in [imgs] that are DCM X-rays (sourced from `GridGallery.dcmImgs`).
  /// Only these get the DCM badge / spinner placeholder / viewer routing.
  final Set<String> dcmNames;

  const _FeaturedMasonry({
    required this.rowId,
    required this.imgs,
    required this.width,
    required this.canDelete,
    required this.clipCount,
    required this.imageProviders,
    required this.downloadingFiles,
    required this.onTapImage,
    required this.onDeleteImage,
    required this.dcmNames,
    this.onTapClip,
  });

  @override
  State<_FeaturedMasonry> createState() => _FeaturedMasonryState();
}

class _FeaturedMasonryState extends State<_FeaturedMasonry> {
  int get _totalCount => math.min(
        widget.clipCount > 0 ? widget.clipCount : widget.imgs.length,
        widget.imgs.length,
      );

  @override
  Widget build(BuildContext context) {
    final total = _totalCount;
    if (total == 0) return const SizedBox.shrink();

    final featuredH = widget.width * 0.62;
    final gridTile =
        (widget.width - (_kGridColumns - 1) * _kGallerySpacing) / _kGridColumns;

    return SizedBox(
      width: widget.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFeaturedTile(featuredH),
          if (total > 1)
            Padding(
              padding: const EdgeInsets.only(top: _kGallerySpacing),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _kGridColumns,
                  crossAxisSpacing: _kGallerySpacing,
                  mainAxisSpacing: _kGallerySpacing,
                  childAspectRatio: 1,
                ),
                itemCount: total - 1,
                itemBuilder: (_, i) => _buildTile(i + 1, gridTile),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeaturedTile(double featuredH) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: widget.width,
        height: featuredH,
        child: _buildTile(0, featuredH, original: true),
      ),
    );
  }

  Widget _buildTile(int index, double tileSize, {bool original = false}) {
    final isLast = widget.clipCount > 0 &&
        index == widget.clipCount - 1 &&
        widget.imgs.length > widget.clipCount;

    return _ImageTile(
      img: widget.imgs[index],
      rowId: widget.rowId,
      isDcm: widget.dcmNames.contains(widget.imgs[index]),
      canDelete: widget.canDelete && widget.clipCount == 0,
      showClipOverlay: isLast,
      remainingCount: isLast ? widget.imgs.length - widget.clipCount : 0,
      useOriginal: original,
      onTap: () => widget.onTapImage(index),
      onDelete: () => widget.onDeleteImage(index),
      imageProviders: widget.imageProviders,
      downloadingFiles: widget.downloadingFiles,
      tileSize: tileSize,
      onTapClip: widget.onTapClip,
    );
  }
}
