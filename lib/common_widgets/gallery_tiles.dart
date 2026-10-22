part of 'grid_gallery.dart';

class _EntranceWrapper extends StatelessWidget {
  const _EntranceWrapper({required this.child, this.animation});
  final Widget child;
  final Animation<double>? animation;

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
    unawaited(_pngReadySub?.cancel());
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
                if (!_hasLoaded && !widget.isDcm) const _ShimmerPlaceholder(),
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
                        FileDownloadButton(
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
              errorBuilder: (_, __, ___) => _buildFilePlaceholder(theme),
            );
          }
          // A completed lookup without an image is not an active load.
          // DCM tiles remain tappable and retry when dicomPngReady emits.
          return _buildFilePlaceholder(theme);
        }
        // Loading: DCM shows the spinner; photos leave the shimmer visible.
        return widget.isDcm ? _buildDcmPlaceholder() : const SizedBox.expand();
      },
    );
  }

  /// Loading placeholder while the DCM preview lookup is pending.
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
  const _FileThumbnail({
    required this.name,
    required this.iconSize,
    this.showLabel = true,
    this.labelWidth,
  });
  final String name;
  final double iconSize;
  final bool showLabel;
  final double? labelWidth;

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
  _ShimmerPainter({required this.progress, required this.isDark});
  final double progress;
  final bool isDark;

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
  const _ClipCountOverlay({required this.count});
  final int count;

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
