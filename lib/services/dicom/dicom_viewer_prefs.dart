import 'dart:convert';

import 'package:apexo/features/settings/settings_stores.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:flutter/foundation.dart';

/// Persisted per-user viewer prefs (window, color map, invert, rotation) stored
/// as JSON in [LocalSettings.dicomViewerPrefs]; applied before showing the viewer
/// and written back, debounced, on change. Missing fields fall back to defaults.
@immutable
class DicomViewerPrefs {
  const DicomViewerPrefs({
    this.windowCenter,
    this.windowWidth,
    this.colorMap,
    this.invert = false,
    this.rotationSteps = 0,
  });

  /// Parses the settings JSON; null/blank/malformed return [empty] and never throw.
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

  /// Snapshots [controller] for the debounced persist-on-change listener.
  factory DicomViewerPrefs.fromController(DicomViewerController controller) {
    return DicomViewerPrefs(
      windowCenter: controller.windowCenter,
      windowWidth: controller.windowWidth,
      colorMap: controller.colorMap,
      invert: controller.invert,
      rotationSteps: controller.rotationSteps,
    );
  }

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

  /// Empty prefs — viewer opens with DICOM header / controller defaults.
  static const DicomViewerPrefs empty = DicomViewerPrefs();

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

  /// True when every field is at its default (nothing to apply).
  bool get isEmpty =>
      windowCenter == null &&
      windowWidth == null &&
      colorMap == null &&
      invert == false &&
      rotationSteps == 0;

  /// Applies after loadFromBytes: windowing only when data is loaded, color map /
  /// invert / rotation always. Async because setColorMap builds the LUT.
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
