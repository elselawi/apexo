import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:apexo/core/reactive/observable.dart';
import 'package:apexo/utils/logger.dart';

// --- Models ---

class ReleaseMetadata {
  ReleaseMetadata({
    required this.latestVersion,
    required this.changelog,
    required this.msStoreUrl,
    required this.macosUrl,
    required this.iosUrl,
    required this.androidUrl,
    required this.webUrl,
  });

  factory ReleaseMetadata.fromJson(Map<String, dynamic> json) {
    final downloads = json['downloads'] as Map<String, dynamic>;
    return ReleaseMetadata(
      latestVersion: json['latest_version'] as String? ?? "0.0.0",
      changelog:
          List<String>.from(json['changelog'] as List<dynamic>? ?? const []),
      msStoreUrl: downloads['ms_store'] as String? ?? "",
      macosUrl: downloads['macos'] as String? ?? "",
      iosUrl: downloads['ios'] as String? ?? "",
      androidUrl: downloads['android'] as String? ?? "",
      webUrl: downloads['web'] as String? ?? "",
    );
  }
  final String latestVersion;
  final List<String> changelog;
  final String msStoreUrl;
  final String macosUrl;
  final String iosUrl;
  final String androidUrl;
  final String webUrl;
}

// --- Service ---

class _VersionService {
  _VersionService() {
    unawaited(init());
  }
  // Observables
  final current = ObservableState("0.0.0");
  final isOutdated = ObservableState(false);
  final latestVersion = ObservableState("0.0.0");

  /// The macos DMG download link (only platform that needs manual updates).
  String _macosDownloadLink = "";
  List<String> changelog = [];

  /// Only macOS needs manual update notifications — all other platforms
  /// (Windows MS Store, Play Store, App Store) auto-update via their stores.
  bool get needsUpdateNotification => !kIsWeb && Platform.isMacOS;

  /// The download link for the current platform (only valid for macOS).
  String get downloadLink => _macosDownloadLink;

  final String metadataUrl = "https://download.apexo.app/metadata.json";

  Future<void>? _currentVersionReady;

  Future<void> loadCurrentVersion() =>
      _currentVersionReady ??= _setCurrentVersion();

  Future<void> init() async {
    await loadCurrentVersion();
    await checkForUpdates();
  }

  Future<void> _setCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      current(info.version);
    } catch (e) {
      current("0.0.0");
    }
  }

  Future<void> checkForUpdates() async {
    try {
      final response = await http
          .get(Uri.parse(metadataUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch metadata: ${response.statusCode}');
      }

      final data = ReleaseMetadata.fromJson(
          json.decode(response.body) as Map<String, dynamic>);

      // Store data
      latestVersion(data.latestVersion);
      _macosDownloadLink = data.macosUrl;
      changelog = data.changelog;

      // Compare versions
      isOutdated(_isVersionNewer(data.latestVersion, current()));
    } catch (e, s) {
      logger("Version update check failed: $e", s);
    }
  }

  /// Simple semantic version comparison
  bool _isVersionNewer(String latest, String current) {
    final List<int> latestParts =
        latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final List<int> currentParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Ensure we have at least 3 parts (major.minor.patch)
    while (latestParts.length < 3) {
      latestParts.add(0);
    }
    while (currentParts.length < 3) {
      currentParts.add(0);
    }

    for (var i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }
}

final version = _VersionService();
