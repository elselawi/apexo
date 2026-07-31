import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/dicom_byte_fetcher.dart';
import 'package:apexo/services/dicom/dicom_viewer_prefs.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart' show login;
import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Maps a `dicom_toolkit` English label to its localized equivalent via
/// `txt()`. Keys are lowercase-without-spaces versions of the English labels.
String _dicomLabel(String englishLabel) {
  const map = {
    'Full Range': 'fullRange',
    'DICOM Default': 'dicomDefault',
    'Mid 50%': 'mid50',
    'Narrow 25%': 'narrow25',
    'High': 'high',
    'Low': 'low',
    'Grayscale': 'grayscale',
    'Hot Iron': 'hotIron',
    'PET Heat': 'petHeat',
    'Rainbow': 'rainbow',
    'Cool': 'cool',
    'Bone': 'bone',
  };
  return txt(map[englishLabel] ?? englishLabel);
}

// ─── Public entry ─────────────────────────────────────────────────

Future<void> openDicomFromBytes(BuildContext context, Uint8List bytes) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => _DicomViewerDialog(bytes: bytes),
  );
}

Future<void> openDicomViewerPanel(
  BuildContext context,
  String rowId,
  String dcmName,
) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => _DicomViewerDialog(rowId: rowId, dcmName: dcmName),
  );
}

// ─── Measurement state ────────────────────────────────────────────

enum _MeasureMode { none, ruler, roi }

class _MeasureState {
  final _MeasureMode mode;
  final Offset? start;
  final Offset? end;
  final RoiStatistics? stats;
  final double? rulerMm;

  const _MeasureState({
    this.mode = _MeasureMode.none,
    this.start,
    this.end,
    this.stats,
    this.rulerMm,
  });

  _MeasureState copyWith({
    _MeasureMode? mode,
    Offset? start,
    Offset? end,
    RoiStatistics? stats,
    double? rulerMm,
    bool clearStart = false,
    bool clearEnd = false,
    bool clearStats = false,
    bool clearRuler = false,
  }) =>
      _MeasureState(
        mode: mode ?? this.mode,
        start: clearStart ? null : (start ?? this.start),
        end: clearEnd ? null : (end ?? this.end),
        stats: clearStats ? null : (stats ?? this.stats),
        rulerMm: clearRuler ? null : (rulerMm ?? this.rulerMm),
      );
}

// ─── Dialog ───────────────────────────────────────────────────────

class _DicomViewerDialog extends StatefulWidget {
  final String? rowId;
  final String? dcmName;
  final Uint8List? bytes;

  const _DicomViewerDialog({this.rowId, this.dcmName, this.bytes});

  @override
  State<_DicomViewerDialog> createState() => _DicomViewerDialogState();
}

class _DicomViewerDialogState extends State<_DicomViewerDialog> {
  DicomViewerController? _controller;
  bool _loading = true;
  String? _error;
  Timer? _persistDebounce;
  _MeasureState _measure = const _MeasureState();
  final _viewerKey = GlobalKey();
  static const _ruler = DicomRuler();
  final _windowFlyoutCtrl = FlyoutController();
  final _colorFlyoutCtrl = FlyoutController();
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Uint8List? bytes;
      if (widget.bytes != null) {
        bytes = widget.bytes;
      } else {
        bytes =
            await fetchDcmBytes(rowId: widget.rowId!, dcmName: widget.dcmName!);
      }
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = txt("dicomLoadFailed");
        });
        return;
      }
      final controller = DicomViewerController();
      await controller.loadFromBytes(bytes: bytes);
      if (controller.hasError) {
        final msg = controller.errorMessage ?? txt("dicomLoadFailed");
        controller.dispose();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = msg;
        });
        return;
      }
      final prefs = DicomViewerPrefs.fromLocalSettings(localSettings);
      await prefs.applyTo(controller);
      controller.addListener(_onControllerChanged);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e, s) {
      logger('openDicomViewerPanel load error: $e', s);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = txt("dicomLoadFailed");
      });
    }
  }

  void _onControllerChanged() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), () {
      final c = _controller;
      if (c == null || !c.hasData) return;
      localSettings.dicomViewerPrefs =
          DicomViewerPrefs.fromController(c).toJsonString();
      localSettings.notifyAndPersist();
    });
  }

  // ── Measurement helpers ────────────────────────────────────────

  Offset _toImagePixel(Offset widgetLocal, Size widgetSize, Size imageSize) {
    if (imageSize.isEmpty || widgetSize.isEmpty) return Offset.zero;
    final imgAspect = imageSize.width / imageSize.height;
    final widgetAspect = widgetSize.width / widgetSize.height;
    double displayW, displayH, offsetX, offsetY;
    if (imgAspect > widgetAspect) {
      displayW = widgetSize.width;
      displayH = widgetSize.width / imgAspect;
      offsetX = 0;
      offsetY = (widgetSize.height - displayH) / 2;
    } else {
      displayH = widgetSize.height;
      displayW = widgetSize.height * imgAspect;
      offsetX = (widgetSize.width - displayW) / 2;
      offsetY = 0;
    }
    return Offset(
      ((widgetLocal.dx - offsetX) / displayW * imageSize.width)
          .clamp(0, imageSize.width - 1),
      ((widgetLocal.dy - offsetY) / displayH * imageSize.height)
          .clamp(0, imageSize.height - 1),
    );
  }

  Size _viewerSize() {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? Size.zero;
  }

  void _onViewerTapDown(TapDownDetails details, Size imageSize) {
    if (_measure.mode == _MeasureMode.none) return;
    final local = _globalToLocal(details.globalPosition);
    final vs = _viewerSize();
    if (_measure.mode == _MeasureMode.ruler) {
      if (_measure.start == null) {
        setState(() => _measure = _measure.copyWith(
            start: _toImagePixel(local, vs, imageSize),
            clearEnd: true,
            clearRuler: true));
      } else {
        final end = _toImagePixel(local, vs, imageSize);
        final result = _controller?.result;
        double? mm;
        if (result != null) {
          mm = _ruler.measure(
              result.metadata,
              (x: _measure.start!.dx, y: _measure.start!.dy),
              (x: end.dx, y: end.dy));
        }
        setState(() => _measure = _measure.copyWith(end: end, rulerMm: mm));
      }
    }
  }

  void _onViewerPanStart(DragStartDetails details, Size imageSize) {
    if (_measure.mode != _MeasureMode.roi) return;
    final local = _globalToLocal(details.globalPosition);
    setState(() => _measure = _measure.copyWith(
        start: _toImagePixel(local, _viewerSize(), imageSize),
        clearEnd: true,
        clearStats: true));
  }

  void _onViewerPanUpdate(DragUpdateDetails details, Size imageSize) {
    if (_measure.mode != _MeasureMode.roi || _measure.start == null) return;
    final local = _globalToLocal(details.globalPosition);
    setState(() => _measure =
        _measure.copyWith(end: _toImagePixel(local, _viewerSize(), imageSize)));
  }

  void _onViewerPanEnd(DragEndDetails details, Size imageSize) {
    if (_measure.mode != _MeasureMode.roi ||
        _measure.start == null ||
        _measure.end == null) return;
    final result = _controller?.result;
    if (result == null) return;
    final s = _measure.start!;
    final e = _measure.end!;
    final roi = DicomRoi(
      x: s.dx < e.dx ? s.dx.toInt() : e.dx.toInt(),
      y: s.dy < e.dy ? s.dy.toInt() : e.dy.toInt(),
      width: (s.dx - e.dx).abs().toInt(),
      height: (s.dy - e.dy).abs().toInt(),
    );
    if (roi.width > 0 && roi.height > 0) {
      final stats = roi.compute(result);
      setState(() => _measure = _measure.copyWith(stats: stats));
    }
  }

  Offset _globalToLocal(Offset global) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? Offset.zero : box.globalToLocal(global);
  }

  void _clearMeasurement() => setState(() => _measure = const _MeasureState());

  void _setMeasureMode(_MeasureMode m) =>
      setState(() => _measure = _measure.copyWith(
          mode: m,
          clearStart: true,
          clearEnd: true,
          clearStats: true,
          clearRuler: true));

  void _resetAll() {
    final c = _controller;
    if (c == null || !c.hasData) return;
    c.resetWindowing();
    c.setColorMap(DicomColorMap.grayscale);
    if (c.invert) c.toggleInvert();
    while (c.rotationSteps != 0) {
      c.rotateCounterClockwise();
    }
    _clearMeasurement();
  }

  // ── Export ─────────────────────────────────────────────────────

  Future<void> _exportPng() async {
    if (widget.dcmName == null) return;
    final c = _controller;
    if (c == null || !c.hasData) return;
    try {
      const exporter = DicomExport();
      final bytes = await exporter.toPngBytes(
        c.result!,
        windowCenter: c.windowCenter,
        windowWidth: c.windowWidth,
        colorMap: c.colorMap,
        invert: c.invert,
        rotationSteps: c.rotationSteps,
      );
      final name =
          widget.dcmName?.replaceAll('.dcm', '').replaceAll('.dicom', '');
      await FilePicker.saveFile(
        bytes: bytes,
        dialogTitle: 'Export DICOM as PNG',
        fileName: '$name.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
      );
    } catch (e, s) {
      logger('Export PNG failed: $e', s);
    }
  }

  // ── Delete ─────────────────────────────────────────────────────

  Widget _divider() => Container(
        width: 1,
        height: 24,
        color: Colors.white.withValues(alpha: 0.54),
      );

  Future<void> _deleteDcm() async {
    if (_isDeleting || widget.rowId == null || widget.dcmName == null) return;
    setState(() => _isDeleting = true);
    try {
      await appointments.deleteDcmImg(widget.rowId!, widget.dcmName!);
      // Remove from the appointment model.
      final appt = appointments.get(widget.rowId!);
      if (appt != null) {
        appt.dcmImgs.remove(widget.dcmName);
        appointments.set(appt);
      }
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e, s) {
      showErrorMessage(e, "deletingPatientImageFromServer");
      login.askForLoginAgain(e);
      logger("Error during deleting DCM image: $e", s);
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── Presets / color map flyouts ─────────────────────────────────

  void _showWindowFlyout() {
    final c = _controller;
    if (c == null) return;
    final curCenter = c.windowCenter;
    final curWidth = c.windowWidth;
    bool isSelected(DicomWindowPreset p) =>
        curCenter == p.center && curWidth == p.width;
    _windowFlyoutCtrl.showFlyout(
      builder: (ctx) => MenuFlyout(items: _buildPresetItems(isSelected)),
    );
  }

  List<MenuFlyoutItem> _buildPresetItems(
      bool Function(DicomWindowPreset) isSelected) {
    final result = _controller?.result;
    if (result == null) return [];
    return DicomWindowPreset.forImage(result).map((preset) {
      return MenuFlyoutItem(
        leading: isSelected(preset)
            ? const Icon(FluentIcons.accept, size: 14)
            : null,
        text: Text(_dicomLabel(preset.label)),
        onPressed: () {
          _controller!.applyPreset(center: preset.center, width: preset.width);
          Navigator.pop(context);
        },
      );
    }).toList();
  }

  void _showColorFlyout() {
    final curMap = _controller?.colorMap;
    _colorFlyoutCtrl.showFlyout(
      builder: (ctx) => MenuFlyout(
          items: DicomColorMap.values.map((map) {
        return MenuFlyoutItem(
          leading:
              curMap == map ? const Icon(FluentIcons.accept, size: 14) : null,
          text: Text(_dicomLabel(map.label)),
          onPressed: () {
            _controller!.setColorMap(map);
            Navigator.pop(ctx);
          },
        );
      }).toList()),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _windowFlyoutCtrl.dispose();
    _colorFlyoutCtrl.dispose();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Container(
        color: Colors.black,
        child: _loading
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ProgressRing(activeColor: Colors.white, strokeWidth: 3),
                const SizedBox(height: 12),
                Txt(txt("loadingDicom"),
                    style: const TextStyle(color: Colors.white)),
              ]))
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(FluentIcons.error,
                        size: 48, color: Color(0xFFFF0000)),
                    const SizedBox(height: 12),
                    Txt(_error!, style: const TextStyle(color: Colors.white)),
                  ]))
                : _buildLoaded(),
      ),
    );
  }

  Widget _buildLoaded() {
    final controller = _controller!;
    final meta = controller.result!.metadata;
    final imageSize = Size(meta.width.toDouble(), meta.height.toDouble());
    final measuring = _measure.mode != _MeasureMode.none;

    return ListenableBuilder(
      listenable: controller,
      builder: (_, __) => Stack(
        key: _viewerKey,
        fit: StackFit.expand,
        children: [
          // ── Viewer ──
          GestureDetector(
            onTapDown: measuring ? (d) => _onViewerTapDown(d, imageSize) : null,
            onPanStart:
                measuring ? (d) => _onViewerPanStart(d, imageSize) : null,
            onPanUpdate:
                measuring ? (d) => _onViewerPanUpdate(d, imageSize) : null,
            onPanEnd: measuring ? (d) => _onViewerPanEnd(d, imageSize) : null,
            child: DicomViewer(
              controller: controller,
              interactive: !measuring,
              fit: BoxFit.contain,
            ),
          ),

          // ── Measurement overlay ──
          if (measuring)
            _MeasureOverlay(measure: _measure, imageSize: imageSize),

          // ── Vertical sliders ──
          Positioned(
            left: 4,
            top: 60,
            bottom: 60,
            child: _VerticalSlider(
              label: 'L',
              value: controller.windowCenter ?? meta.windowCenter,
              min: (meta.windowCenter - meta.windowWidth * 3)
                  .clamp(-40000.0, 40000.0),
              max: (meta.windowCenter + meta.windowWidth * 3)
                  .clamp(-40000.0, 40000.0),
              onChanged: (v) => controller.updateWindowing(center: v),
            ),
          ),
          Positioned(
            right: 4,
            top: 60,
            bottom: 60,
            child: _VerticalSlider(
              label: 'W',
              value: controller.windowWidth ?? meta.windowWidth,
              min: 1,
              max: (meta.windowWidth * 4).clamp(4.0, 65536.0),
              onChanged: (v) => controller.updateWindowing(width: v),
            ),
          ),

          // ── Patient info (padded left to clear the vertical slider) ──
          Positioned(
            bottom: 56,
            left: 36,
            right: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0078D4).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          meta.modality == 'Unknown' ? 'DICOM' : meta.modality,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (meta.patientName != 'Unknown')
                        Text(meta.patientName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      if (meta.bestDate != null || meta.width > 0)
                        Text(
                          [
                            if (meta.bestDate != null) meta.bestDate,
                            '${meta.width}×${meta.height}',
                          ].join('  ·  '),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Measurement result popup (below top bar) ──
          if (_measure.rulerMm != null || _measure.stats != null)
            Positioned(
              bottom: 0,
              left: 36,
              right: 44,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 56),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        if (_measure.rulerMm != null)
                          Text(
                            '${_measure.rulerMm!.toStringAsFixed(1)} ${txt("mm")}',
                            style: const TextStyle(
                                color: Color(0xFF4CC2FF),
                                fontWeight: FontWeight.w700,
                                fontSize: 14),
                          ),
                        if (_measure.stats != null) ...[
                          Container(
                            width: 1,
                            height: 20,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                // Note: μ and σ are universal symbols, not localized
                                '\u03BC=${_measure.stats!.mean.toStringAsFixed(0)}'
                                '  \u03C3=${_measure.stats!.stdDev.isNaN ? "\u2014" : _measure.stats!.stdDev.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    color: Color(0xFF4CC2FF),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12),
                              ),
                              Text(
                                '${txt("roiMin")}=${_measure.stats!.min.toStringAsFixed(0)}'
                                '  ${txt("roiMax")}=${_measure.stats!.max.toStringAsFixed(0)}'
                                '  ${txt("roiMedian")}=${_measure.stats!.median.toStringAsFixed(0)}'
                                '  ${txt("roiPixelCount")}=${_measure.stats!.pixelCount}',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                        GestureDetector(
                          onTap: _clearMeasurement,
                          child: const Icon(
                            FluentIcons.chrome_close,
                            size: 16,
                            color: Color(0xFF4CC2FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Top bar ──
          Positioned(
            top: 0,
            left: 20,
            right: 20,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 10,
                    children: [
                      // Download PNG
                      if (widget.dcmName != null)
                        IconButton(
                          icon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FluentIcons.download,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 4),
                              Txt(
                                txt("download"),
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
                          onPressed: _exportPng,
                        ),
                      // Delete
                      if (widget.dcmName != null) ...[
                        _divider(),
                        DeleteButton(
                          onConfirm: _deleteDcm,
                          preview: FileDeletePreview(
                            name: widget.dcmName!,
                          ),
                          actionText: txt("delete"),
                          actionIcon: WindowsIcons.delete,
                          restorable: false,
                          style: const ButtonStyle(
                              foregroundColor:
                                  WidgetStatePropertyAll(Colors.white)),
                          child: ButtonContent(
                            WindowsIcons.delete,
                            txt("delete"),
                            size: 18,
                          ),
                        ),
                      ],
                      // Divider before close (only when there's content before it)
                      if (widget.dcmName != null) _divider(),
                      // Close
                      IconButton(
                        icon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.clear,
                                color: Colors.white, size: 18),
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
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom bar (scrollable) ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 10,
                      children: [
                        // Window preset
                        FlyoutTarget(
                          controller: _windowFlyoutCtrl,
                          child: _VwBtn(
                            icon: FluentIcons.brightness,
                            label: txt("window"),
                            tooltip: txt("window"),
                            onTap: _showWindowFlyout,
                          ),
                        ),
                        // Color map
                        FlyoutTarget(
                          controller: _colorFlyoutCtrl,
                          child: _VwBtn(
                            icon: FluentIcons.color,
                            label: txt("colorMap"),
                            tooltip: txt("colorMap"),
                            onTap: _showColorFlyout,
                          ),
                        ),
                        _divider(),
                        // Rotate left
                        _VwBtn(
                          icon: FluentIcons.rotate90_counter_clockwise,
                          label: txt("rotateLeft"),
                          tooltip: txt("rotateLeft"),
                          onTap: controller.rotateCounterClockwise,
                        ),
                        // Rotation angle
                        Text('${controller.rotationSteps * 90}°',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.7))),
                        // Rotate right
                        _VwBtn(
                          icon: FluentIcons.rotate90_clockwise,
                          label: txt("rotateRight"),
                          tooltip: txt("rotateRight"),
                          onTap: controller.rotateClockwise,
                        ),
                        _divider(),
                        // Invert
                        _VwBtn(
                          icon: FluentIcons.contrast,
                          label: txt("invert"),
                          tooltip: txt("invert"),
                          onTap: controller.toggleInvert,
                          active: controller.invert,
                        ),
                        _divider(),
                        // Ruler
                        _VwBtn(
                          icon: FluentIcons.line,
                          label: txt("ruler"),
                          tooltip: txt("ruler"),
                          onTap: () => _setMeasureMode(
                              _measure.mode == _MeasureMode.ruler
                                  ? _MeasureMode.none
                                  : _MeasureMode.ruler),
                          active: _measure.mode == _MeasureMode.ruler,
                        ),
                        // ROI
                        _VwBtn(
                          icon: FluentIcons.rectangle_shape,
                          label: txt("roi"),
                          tooltip: txt("roi"),
                          onTap: () => _setMeasureMode(
                              _measure.mode == _MeasureMode.roi
                                  ? _MeasureMode.none
                                  : _MeasureMode.roi),
                          active: _measure.mode == _MeasureMode.roi,
                        ),
                        // Reset all
                        _VwBtn(
                          icon: FluentIcons.refresh,
                          label: txt("reset"),
                          tooltip: txt("reset"),
                          onTap: _resetAll,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Viewer button (dark pill overlay style) ──────────────────────

class _VwBtn extends StatefulWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  const _VwBtn({
    required this.icon,
    this.label,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  @override
  State<_VwBtn> createState() => _VwBtnState();
}

class _VwBtnState extends State<_VwBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fgColor = widget.active
        ? const Color(0xFF4CC2FF)
        : Colors.white.withValues(alpha: 0.85);

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18, color: fgColor),
                if (widget.label != null) ...[
                  const SizedBox(width: 6),
                  Txt(
                    widget.label!,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Vertical slider ──────────────────────────────────────────────

class _VerticalSlider extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  const _VerticalSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.4))),
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
                value: clamped, min: min, max: max, onChanged: onChanged),
          ),
        ),
        Text(clamped.toStringAsFixed(0),
            style: TextStyle(
                fontSize: 9, color: Colors.white.withValues(alpha: 0.5))),
      ],
    );
  }
}

// ─── Measurement overlay (CustomPaint) ────────────────────────────

class _MeasureOverlay extends StatelessWidget {
  const _MeasureOverlay({required this.measure, required this.imageSize});
  final _MeasureState measure;
  final Size imageSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
      final imgAspect = imageSize.width / imageSize.height;
      final widgetAspect = widgetSize.width / widgetSize.height;
      double displayW, displayH, offsetX, offsetY;
      if (imgAspect > widgetAspect) {
        displayW = widgetSize.width;
        displayH = widgetSize.width / imgAspect;
        offsetX = 0;
        offsetY = (widgetSize.height - displayH) / 2;
      } else {
        displayH = widgetSize.height;
        displayW = widgetSize.height * imgAspect;
        offsetX = (widgetSize.width - displayW) / 2;
        offsetY = 0;
      }
      return IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _MeasurePainter(
            measure: measure,
            displayW: displayW,
            displayH: displayH,
            offsetX: offsetX,
            offsetY: offsetY,
            imageW: imageSize.width,
            imageH: imageSize.height,
          ),
        ),
      );
    });
  }
}

class _MeasurePainter extends CustomPainter {
  _MeasurePainter({
    required this.measure,
    required this.displayW,
    required this.displayH,
    required this.offsetX,
    required this.offsetY,
    required this.imageW,
    required this.imageH,
  });
  final _MeasureState measure;
  final double displayW, displayH, offsetX, offsetY;
  final double imageW, imageH;
  static const _accent = Color(0xFF4CC2FF);

  Offset _toCanvas(Offset pixel) => Offset(
        pixel.dx / imageW * displayW + offsetX,
        pixel.dy / imageH * displayH + offsetY,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _accent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final start = measure.start;
    if (start == null) return;
    final s = _toCanvas(start);

    if (measure.mode == _MeasureMode.ruler) {
      _crosshair(canvas, s, paint);
      if (measure.end != null) {
        final e = _toCanvas(measure.end!);
        _crosshair(canvas, e, paint);
        canvas.drawLine(s, e, paint..strokeWidth = 1.5);
        if (measure.rulerMm != null) {
          _label(canvas, e, '${measure.rulerMm!.toStringAsFixed(1)} mm');
        }
      }
    }

    if (measure.mode == _MeasureMode.roi && measure.end != null) {
      final e = _toCanvas(measure.end!);
      final rect = Rect.fromPoints(s, e);
      canvas.drawRect(
          rect,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      canvas.drawRect(
          rect,
          paint
            ..color = _accent.withValues(alpha: 0.12)
            ..style = PaintingStyle.fill);
    }
  }

  void _crosshair(Canvas canvas, Offset c, Paint paint) {
    const r = 5.0;
    canvas.drawCircle(c, r, paint);
    canvas.drawLine(Offset(c.dx - r - 2, c.dy), Offset(c.dx + r + 2, c.dy),
        paint..strokeWidth = 1);
    canvas.drawLine(
        Offset(c.dx, c.dy - r - 2), Offset(c.dx, c.dy + r + 2), paint);
  }

  void _label(Canvas canvas, Offset pos, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 3, color: Colors.black)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 4.0, padY = 2.0;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(pos.dx - padX, pos.dy - tp.height - padY,
                tp.width + padX * 2, tp.height + padY * 2),
            const Radius.circular(3)),
        Paint()..color = _accent.withValues(alpha: 0.8));
    tp.paint(canvas, Offset(pos.dx, pos.dy - tp.height - padY + 1));
  }

  @override
  bool shouldRepaint(covariant _MeasurePainter o) => measure != o.measure;
}
