import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apexo/common_widgets/adaptive_hover_widget.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/import_photos_dialog.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/shared/image_viewer/file_download_button.dart';
import 'package:apexo/shared/image_viewer/photo_viewer_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:image_picker/image_picker.dart';

part 'gallery_preview.dart';
part 'gallery_tiles.dart';

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

class GalleryUploadConfig {
  const GalleryUploadConfig({
    required this.store,
    required this.modelPersistence,
    required this.canUpload,
    this.acceptedSources = const {
      UploadSource.camera,
      UploadSource.gallery,
      UploadSource.link,
      UploadSource.files
    },
  });
  /// The record store the files are uploaded to. Required: an upload without a
  /// store would have to guess one, and guessing meant every feature's files
  /// went to the appointments collection.
  final Store store;
  final Future<void> Function(List<String> newNames) modelPersistence;
  final bool canUpload;
  final Set<UploadSource> acceptedSources;
}

// ─── GridGallery widget ───────────────────────────────────────────────────

class GridGallery extends StatefulWidget {
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
    this.owner,
    this.onOpenRecord,
  });
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

  /// Tap handler for DCM entries. Defaults to [openDicomViewerWindow] when
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

  /// Whose gallery this is — the patient and day of the visit, say. A photo's
  /// window says it, so several open at once can be told apart.
  final String Function()? owner;

  /// The record these photos belong to, for a photo's own window: it leads back
  /// to the panel that holds them. Null where there is no such panel.
  final Future<void> Function()? onOpenRecord;

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
      unawaited(provider.evict());
    }
    super.dispose();
  }

  // ── Upload logic ──

  void _showUploadMenu() async {
    final cfg = widget.uploadConfig;
    if (cfg == null || !cfg.canUpload) return;
    final src = cfg.acceptedSources;
    await flyoutFocusFix(context);
    unawaited(_uploadFlyoutCtrl.showFlyout(
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
    ));
  }

  Future<void> _doDelete(String img) async {
    if (_isDeleting) return;
    _isDeleting = true;
    // The photo's own window outlives this gallery: deleting from it reaches
    // here after the panel that holds the gallery may be gone — so the owner
    // is only told about it while there is one to tell.
    if (mounted) widget.onProgress?.call(true);
    if (mounted) setState(() {});
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
      _isDeleting = false;
      if (mounted) widget.onProgress?.call(false);
      if (mounted) setState(() {});
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

  Future<void> _handleFileTap(String img) async {
    // DCM X-rays open the interactive viewer (which parses the raw .dcm
    // itself — no dependency on the PNG preview being ready yet). Only entries
    // explicitly in `dcmImgs` route here — a `.dcm` file attached to a
    // note/expense falls through to the regular download path below.
    // A DCM opens in the viewer its owner passes in. Without one — a gallery
    // that is not a record's X-rays — it is a file like any other and downloads.
    if (_dcmNames.contains(img) && widget.onTapDcm != null) {
      widget.onTapDcm!(context, widget.rowId, img);
      return;
    }
    if (!isAnImageName(img)) {
      setState(() => _downloadingFiles.add(img));
      try {
        await downloadFile(widget.rowId, img);
      } catch (error) {
        if (mounted) showErrorMessage(error, "downloadingFile");
      } finally {
        if (mounted) setState(() => _downloadingFiles.remove(img));
      }
      return;
    }
    _openSingleImage(img);
  }

  void _openSingleImage(String img) {
    _showImageWindow(
      id: 'image:$img',
      title: 'photo',
      subtitle: () => _joinOwner(img),
      images: [img],
      onDelete: _deleteEnabled ? (_) => _doDelete(img) : null,
    );
  }

  void _openSlideShow([int initialIndex = 0]) {
    _showImageWindow(
      id: 'images:${viewableImgs.join(",")}',
      title: 'photoSlideshow',
      subtitle: () => _joinOwner(''),
      images: viewableImgs,
      initialIndex: initialIndex,
      onDelete:
          _deleteEnabled ? (index) => _doDelete(viewableImgs[index]) : null,
    );
  }

  /// Whose photos these are, and which file — enough for a window to say what it
  /// is when several are open.
  String _joinOwner(String fileName) => [
        if ((widget.owner?.call() ?? '').isNotEmpty) widget.owner!(),
        if (fileName.isNotEmpty) fileName,
      ].join(' · ');

  /// Shows photos in a window of their own — beside the app, not over it.
  ///
  /// A photo is something you glance at while you keep working, so it takes a
  /// window the way a scan or a chart does: drawn, downloaded, deleted and
  /// closed from the window's own tools, and closed by its frame like any other.
  ///
  /// The photos load *inside* that window: opening one never puts a blocking
  /// dialog over the app behind it.
  void _showImageWindow({
    required String id,
    required String title,
    required List<String> images,
    String Function()? subtitle,
    int initialIndex = 0,
    ValueChanged<int>? onDelete,
  }) {
    late final FloatingWindow floating;
    floating = WindowsManager.showStandalone(
      PanelWindow(
        id: id,
        title: title,
        icon: FluentIcons.photo,
        subtitle: subtitle,
        padding: 0,
        scrollable: false,
        // A photo is its own viewer, not a column of a panel.
        matchesPanelWidth: false,
        preferredWidth: 760,
        body: PhotoViewerWindow(
          rowId: widget.rowId,
          images: images,
          initialIndex: initialIndex,
          drawings: widget.drawings,
          onSaveDrawing: widget.onSaveDrawing,
          onDelete: onDelete,
          onClosed: () => WindowsManager.close(floating),
        ),
      ),
      scope: 'row:${widget.rowId}',
      onOpenRecord: widget.onOpenRecord,
    );
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
            // The gallery is as wide as its `rowWidth`, or narrower where it is
            // given less: the note wraps rather than pushing past the edge.
            Flexible(
              child: Txt(
                txt("noFiles"),
                style: FluentTheme.of(context).typography.caption,
              ),
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

