import 'dart:convert';

import 'package:apexo/features/settings/settings_stores.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:flutter/foundation.dart';

/// Per-user DICOM viewer preferences, persisted as JSON in
/// [LocalSettings.dicomViewerPrefs].
///
/// Next image opens with the same windowing / color map / invert / rotation
/// the dentist last used. Applied to a [DicomViewerController] before the
/// viewer is shown; written back (debounced) on any control change.
///
/// JSON shape (all fields optional; missing fields fall back to DICOM header
/// defaults or the controller's own defaults):
/// ```json
/// {"windowCenter": 40, "windowWidth": 400, "colorMap": "bone",
///  "invert": true, "rotationSteps": 1}
/// ```
@immutable
class DicomViewerPrefs {
  /// Window center (level). `null` → use the DICOM header value on load.
  final double? windowCenter;

  /// Window width. `null` → use the DICOM header value on load.
  final double? windowWidth;

  /// Color map name (matches [DicomColorMap.name]). `null` → grayscale.
  final DicomColorMap? colorMap;

  /// Whether grayscale inversion is active.
  final bool invert;

  /// Number of 90° clockwise rotation steps (0–3).
  final int rotationSteps;

  const DicomViewerPrefs({
    this.windowCenter,
    this.windowWidth,
    this.colorMap,
    this.invert = false,
    this.rotationSteps = 0,
  });

  /// Empty prefs — viewer opens with DICOM header / controller defaults.
  static const DicomViewerPrefs empty = DicomViewerPrefs();

  /// Parses [LocalSettings.dicomViewerPrefs] (a JSON string). Returns
  /// [empty] on a null/blank/malformed string — never throws.
  factory DicomViewerPrefs.fromLocalSettings(LocalSettings localSettings) {
    final raw = localSettings.dicomViewerPrefs;
    if (raw.isEmpty) return empty;
    try {
      return DicomViewerPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return empty;
    }
  }

  /// Parses a JSON map. Tolerant of missing/invalid fields.
  factory DicomViewerPrefs.fromJson(Map<String, dynamic> json) {
    DicomColorMap? colorMap;
    final colorMapName = json['colorMap'] as String?;
    if (colorMapName != null) {
      for (final e in DicomColorMap.values) {
        if (e.name == colorMapName) {
          colorMap = e;
          break;
        }
      }
    }
    return DicomViewerPrefs(
      windowCenter: _asDouble(json['windowCenter']),
      windowWidth: _asDouble(json['windowWidth']),
      colorMap: colorMap,
      invert: json['invert'] as bool? ?? false,
      rotationSteps: _clampRotation(json['rotationSteps'] as int?),
    );
  }

  /// Serializes to the JSON shape persisted in [LocalSettings.dicomViewerPrefs].
  Map<String, dynamic> toJson() => {
        if (windowCenter != null) 'windowCenter': windowCenter,
        if (windowWidth != null) 'windowWidth': windowWidth,
        if (colorMap != null) 'colorMap': colorMap!.name,
        'invert': invert,
        'rotationSteps': rotationSteps,
      };

  /// Serializes to the JSON string form stored in [LocalSettings.dicomViewerPrefs].
  String toJsonString() => jsonEncode(toJson());

  /// Reads the current state of [controller] into a new prefs instance.
  /// Used by the debounced persist-on-change listener.
  factory DicomViewerPrefs.fromController(DicomViewerController controller) {
    return DicomViewerPrefs(
      windowCenter: controller.windowCenter,
      windowWidth: controller.windowWidth,
      colorMap: controller.colorMap,
      invert: controller.invert,
      rotationSteps: controller.rotationSteps,
    );
  }

  /// True when every field is at its default (nothing to apply).
  bool get isEmpty =>
      windowCenter == null &&
      windowWidth == null &&
      colorMap == null &&
      invert == false &&
      rotationSteps == 0;

  /// Applies these prefs to [controller] after [DicomViewerController.loadFromBytes]
  /// has completed. Windowing is applied only when the controller has data
  /// (loaded); color map / invert / rotation are set unconditionally.
  ///
  /// [DicomViewerController.setColorMap] is async (builds a color LUT texture),
  /// so this method is async. Returns when all prefs have been applied.
  Future<void> applyTo(DicomViewerController controller) async {
    if (isEmpty) return;

    // Windowing — only meaningful once pixel data is loaded.
    if (controller.hasData && (windowCenter != null || windowWidth != null)) {
      controller.updateWindowing(
        center: windowCenter,
        width: windowWidth,
      );
    }

    // Color map.
    if (colorMap != null && colorMap != controller.colorMap) {
      await controller.setColorMap(colorMap!);
    }

    // Invert.
    if (invert && !controller.invert) {
      controller.toggleInvert();
    }

    // Rotation (0–3 steps clockwise). Advance until matched.
    var steps = controller.rotationSteps;
    while (steps != rotationSteps) {
      controller.rotateClockwise();
      steps = (steps + 1) % 4;
    }
  }
}

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return null;
}

int _clampRotation(int? v) {
  if (v == null) return 0;
  if (v < 0) return 0;
  if (v > 3) return 3;
  return v;
}
