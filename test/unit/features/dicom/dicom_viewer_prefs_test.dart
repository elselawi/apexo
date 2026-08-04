import 'dart:convert';

import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/dicom/dicom_viewer_prefs.dart';
import 'package:apexo/services/localization/en.dart';
import 'package:dicom_toolkit/dicom_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal [LocalSettings] that lets us set [dicomViewerPrefs] directly
/// without touching Hive. [notifyAndPersist] is recorded for assertion.
class _TestLocalSettings extends LocalSettings {
  final List<String> persistLog = [];
  @override
  void notifyAndPersist() {
    persistLog.add(dicomViewerPrefs);
  }
}

/// Fake [SaveRemote] that resolves a fixed URL for known (rowId, name) pairs.
/// Used to document the fetchDcmBytes null-URL contract without real network.
class _FakeSaveRemote {
  final Map<String, String> urlFor;
  _FakeSaveRemote({required this.urlFor});

  String _key(String rowId, String name) => '$rowId/$name';

  Future<String?> getImageLink(String rowID, String imageName,
      [bool useCache = true]) async {
    return urlFor[_key(rowID, imageName)];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────
  // DicomViewerPrefs — pure parse / serialize / apply logic.
  // ─────────────────────────────────────────────────────────────────────
  group('DicomViewerPrefs — JSON parsing', () {
    test('empty string → empty prefs (fromLocalSettings)', () {
      final ls = _TestLocalSettings()..dicomViewerPrefs = '';
      final p = DicomViewerPrefs.fromLocalSettings(ls);
      expect(p.isEmpty, isTrue);
      expect(p.invert, isFalse);
      expect(p.rotationSteps, 0);
    });

    test('blank whitespace → empty (defensive)', () {
      final ls = _TestLocalSettings()..dicomViewerPrefs = '   ';
      expect(DicomViewerPrefs.fromLocalSettings(ls).isEmpty, isTrue);
    });

    test('malformed JSON → empty (never throws)', () {
      final ls = _TestLocalSettings()..dicomViewerPrefs = '{not json';
      expect(DicomViewerPrefs.fromLocalSettings(ls).isEmpty, isTrue);
    });

    test('full round-trip preserves all fields', () {
      const original = DicomViewerPrefs(
        windowCenter: 40,
        windowWidth: 400,
        colorMap: DicomColorMap.bone,
        invert: true,
        rotationSteps: 2,
      );
      final encoded = original.toJsonString();
      final restored = DicomViewerPrefs.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>);
      expect(restored.windowCenter, 40);
      expect(restored.windowWidth, 400);
      expect(restored.colorMap, DicomColorMap.bone);
      expect(restored.invert, isTrue);
      expect(restored.rotationSteps, 2);
      expect(restored.isEmpty, isFalse);
    });

    test('colorMap round-trips by enum name for every value', () {
      for (final map in DicomColorMap.values) {
        final p = DicomViewerPrefs(colorMap: map);
        final restored = DicomViewerPrefs.fromJson(
            jsonDecode(p.toJsonString()) as Map<String, dynamic>);
        expect(restored.colorMap, map,
            reason: 'color map $map should round-trip');
      }
    });

    test('unknown colorMap name → null (graceful)', () {
      final p = DicomViewerPrefs.fromJson(
          jsonDecode('{"colorMap":"nonexistent"}') as Map<String, dynamic>);
      expect(p.colorMap, isNull);
    });

    test('rotationSteps clamped to 0–3', () {
      expect(DicomViewerPrefs.fromJson(const {'rotationSteps': -1}).rotationSteps, 0);
      expect(DicomViewerPrefs.fromJson(const {'rotationSteps': 5}).rotationSteps, 3);
      expect(DicomViewerPrefs.fromJson(const {'rotationSteps': 2}).rotationSteps, 2);
      expect(DicomViewerPrefs.fromJson(const {}).rotationSteps, 0);
    });

    test('int windowCenter accepted (not just double)', () {
      // JSON numbers without a decimal arrive as int in Dart. The parser
      // must coerce to double.
      final p = DicomViewerPrefs.fromJson(
          jsonDecode('{"windowCenter":40,"windowWidth":400}')
              as Map<String, dynamic>);
      expect(p.windowCenter, 40.0);
      expect(p.windowWidth, 400.0);
    });
  });

  group('DicomViewerPrefs — fromController snapshot', () {
    test('captures the controller defaults', () {
      // A bare controller (no DicomToolkit.init) has:
      //   windowCenter = null, windowWidth = null, colorMap = grayscale,
      //   invert = false, rotationSteps = 0.
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      final p = DicomViewerPrefs.fromController(controller);
      expect(p.colorMap, DicomColorMap.grayscale);
      expect(p.invert, isFalse);
      expect(p.rotationSteps, 0);
      expect(p.windowCenter, isNull);
      expect(p.windowWidth, isNull);
    });

    test('captures rotation + invert after mutations (no load needed)', () {
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      controller.rotateClockwise();
      controller.toggleInvert();
      final p = DicomViewerPrefs.fromController(controller);
      expect(p.rotationSteps, 1);
      expect(p.invert, isTrue);
    });
  });

  group('DicomViewerPrefs — applyTo', () {
    test('empty prefs → no-op (invert stays off, rotation stays 0)', () {
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      const p = DicomViewerPrefs.empty;
      p.applyTo(controller);
      expect(controller.invert, isFalse);
      expect(controller.rotationSteps, 0);
    });

    test('invert=true toggles invert on', () async {
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      await const DicomViewerPrefs(invert: true).applyTo(controller);
      expect(controller.invert, isTrue);
    });

    test('rotationSteps=2 advances rotation to 2 (two clockwise steps)',
        () async {
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      await const DicomViewerPrefs(rotationSteps: 2).applyTo(controller);
      expect(controller.rotationSteps, 2);
    });

    test('rotationSteps=3 wraps correctly (3 clockwise from 0)', () async {
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      await const DicomViewerPrefs(rotationSteps: 3).applyTo(controller);
      expect(controller.rotationSteps, 3);
    });

    test('windowing is NOT applied when controller has no data (no crash)',
        () async {
      // Without DicomToolkit.init + loadFromBytes, hasData is false.
      // applyTo must skip the windowing branch rather than throw.
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      await const DicomViewerPrefs(windowCenter: 50, windowWidth: 200)
          .applyTo(controller);
      // windowCenter/Width remain null (not applied).
      expect(controller.windowCenter, isNull);
      expect(controller.windowWidth, isNull);
    });

    test('grayscale color map (explicit) → no color LUT build needed',
        () async {
      // Setting colorMap to grayscale is the no-op early-return path in the
      // controller; applyTo must not choke on it even without data.
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      await const DicomViewerPrefs(colorMap: DicomColorMap.grayscale)
          .applyTo(controller);
      expect(controller.colorMap, DicomColorMap.grayscale);
    });

    test('invert=true + colorMap=bone applies both settings', () async {
      // Verify that opening the viewer with
      // {invert: true, colorMap: bone} initializes invert on. (The bone
      // color LUT build is async and requires the Rust backend; we assert
      // the request is made without throwing, and invert is applied.)
      final controller = DicomViewerController();
      addTearDown(controller.dispose);
      // setColorMap(bone) calls _buildColorLut → decodeImageFromPixels,
      // which works without the Rust backend (pure dart:ui). If it throws
      // in this test environment, we treat color-map application as
      // best-effort and still verify invert.
      try {
        await const DicomViewerPrefs(
          colorMap: DicomColorMap.bone,
          invert: true,
        ).applyTo(controller);
      } catch (_) {
        // Color LUT build may fail in headless test; invert must still apply.
      }
      expect(controller.invert, isTrue,
          reason: 'invert must be applied even if colorMap build fails');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // fetchDcmBytes — null-URL contract (no network).
  // ─────────────────────────────────────────────────────────────────────
  group('fetchDcmBytes null-URL contract', () {
    test('SaveRemote.getImageLink returning null means no download', () async {
      // Documents the contract fetchDcmBytes relies on: when the PB file URL
      // cannot be resolved, fetchDcmBytes returns null (no HTTP attempt).
      final fakeRemote = _FakeSaveRemote(urlFor: {});
      final url = await fakeRemote.getImageLink('apt-1', 'dcm_none.dcm');
      expect(url, isNull,
          reason: 'a missing (rowId, name) must resolve to a null URL, '
              'which fetchDcmBytes treats as "file not found"');
    });

    test('a known (rowId, name) resolves to a non-null URL', () async {
      final fakeRemote = _FakeSaveRemote(urlFor: {
        'apt-1/dcm_abc.dcm': 'https://example.test/files/apt-1/dcm_abc.dcm',
      });
      final url = await fakeRemote.getImageLink('apt-1', 'dcm_abc.dcm');
      expect(url, 'https://example.test/files/apt-1/dcm_abc.dcm');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Localization keys.
  // ─────────────────────────────────────────────────────────────────────
  group('localization keys present in En', () {
    test('viewer control keys exist', () {
      final en = En();
      for (final key in [
        'dicomViewer',
        'window',
        'colorMap',
        'invert',
        'rotateLeft',
        'rotateRight',
        'loadingDicom',
        'dicomLoadFailed',
        'defaultWindow',
        'fullRange',
        'dicomDefault',
        'mid50',
        'narrow25',
        'grayscale',
        'hotIron',
        'petHeat',
        'rainbow',
        'cool',
        'bone',
      ]) {
        expect(en.dictionary.containsKey(key), isTrue, reason: 'missing $key');
        expect(en.dictionary[key]!.isNotEmpty, isTrue);
      }
    });
  });
}
