import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/dicom_byte_fetcher.dart';
import 'package:apexo/services/dicom/dicom_viewer_prefs.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart' show login;
import 'package:apexo/utils/logger.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';

part 'dicom_measure_overlay.dart';
part 'dicom_viewport_controls.dart';

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

/// Shows raw DICOM bytes the user picked, in a window of their own.
void openDicomFromBytes(Uint8List bytes, {String? name}) {
  late final FloatingWindow floating;
  // Each imported file is a window of its own: two files must not replace one
  // another, and the user has to be able to tell which is which.
  final id = 'dicom:bytes:${_importedScans++}';
  floating = WindowsManager.showStandalone(
    PanelWindow(
      id: id,
      title: "xRayViewer",
      icon: FluentIcons.medical_care,
      // Which file this is: several imported scans can be open at once, and
      // they all carry the same title.
      subtitle: () => name ?? '',
      padding: 0,
      scrollable: false,
      // A scan is its own viewer, not a column of a panel: it asks for the room
      // an X-ray needs.
      matchesPanelWidth: false,
      preferredWidth: 1100,
      body: DicomScanViewer(
        bytes: bytes,
        onClose: () => WindowsManager.close(floating),
      ),
    ),
  );
}

/// How many scans have been imported and opened in this session — what tells
/// one imported file's window from another's.
int _importedScans = 0;

/// Shows one of a record's scans in a window of its own — beside the app, not
/// over it: a scan is something you look at while you keep working.
void openDicomViewerWindow(String rowId, String dcmName) {
  late final FloatingWindow floating;
  floating = WindowsManager.showStandalone(
    PanelWindow(
      id: 'dicom:$dcmName',
      title: "xRayViewer",
      icon: FluentIcons.medical_care,
      // Whose scan it is, and which file: several can be open at once.
      subtitle: () {
        final owner = appointments.get(rowId)?.patient?.title ?? '';
        return [if (owner.isNotEmpty) owner, dcmName].join(' · ');
      },
      padding: 0,
      scrollable: false,
      // A scan is its own viewer, not a column of a panel: it asks for the room
      // an X-ray needs.
      matchesPanelWidth: false,
      preferredWidth: 1100,
      body: DicomScanViewer(
        rowId: rowId,
        dcmName: dcmName,
        onClose: () => WindowsManager.close(floating),
      ),
    ),
    // The scan belongs to a visit, and it is named the way the visit's own
    // windows are: the panel of that visit takes the scan's place when it
    // opens, and the scan wears the visit's colour.
    scope: 'appointment:$rowId',
    // A scan belongs to a visit: its window leads back to that record. A scan
    // whose record is gone — an imported file — has nowhere to go.
    onOpenRecord: appointments.get(rowId) == null
        ? null
        : () async {
            final appointment = appointments.get(rowId);
            if (appointment != null) openAppointment(appointment);
          },
  );
}

// ─── Measurement state ────────────────────────────────────────────

class DicomScanViewer extends StatefulWidget {
  const DicomScanViewer({
    super.key,
    this.rowId,
    this.dcmName,
    this.bytes,
    required this.onClose,
  });

  final String? rowId;
  final String? dcmName;
  final Uint8List? bytes;

  /// Closes the viewer: the window it lives in is the one that goes away.
  final VoidCallback onClose;

  @override
  State<DicomScanViewer> createState() => _DicomViewerState();
}

class _DicomViewerState extends State<DicomScanViewer> {
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
    unawaited(_load());
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
      logger('openDicomViewerWindow load error: $e', s);
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
        _measure.end == null) {
      return;
    }
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
    unawaited(c.setColorMap(DicomColorMap.grayscale));
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
      widget.onClose();
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
    unawaited(_windowFlyoutCtrl.showFlyout<void>(
      builder: (ctx) => MenuFlyout(items: _buildPresetItems(isSelected, ctx)),
    ));
  }

  List<MenuFlyoutItem> _buildPresetItems(
      bool Function(DicomWindowPreset) isSelected, BuildContext flyoutContext) {
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
          Navigator.pop(flyoutContext);
        },
      );
    }).toList();
  }

  void _showColorFlyout() {
    final curMap = _controller?.colorMap;
    unawaited(_colorFlyoutCtrl.showFlyout<void>(
      builder: (ctx) => MenuFlyout(
          items: DicomColorMap.values.map((map) {
        return MenuFlyoutItem(
          leading:
              curMap == map ? const Icon(FluentIcons.accept, size: 14) : null,
          text: Text(_dicomLabel(map.label)),
          onPressed: () {
            unawaited(_controller!.setColorMap(map));
            Navigator.pop(ctx);
          },
        );
      }).toList()),
    ));
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
                        onPressed: widget.onClose,
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

