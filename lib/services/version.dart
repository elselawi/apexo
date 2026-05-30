import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:apexo/core/observable.dart';
import 'package:apexo/utils/logger.dart';

// --- Models ---

class ReleaseMetadata {
  final String latestVersion;
  final List<String> changelog;
  final String msStoreUrl;
  final String macosUrl;
  final String iosUrl;
  final String androidUrl;
  final String webUrl;

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
      latestVersion: json['latest_version'] ?? "0.0.0",
      changelog: List<String>.from(json['changelog'] ?? []),
      msStoreUrl: downloads['ms_store'] ?? "",
      macosUrl: downloads['macos'] ?? "",
      iosUrl: downloads['ios'] ?? "",
      androidUrl: downloads['android'] ?? "",
      webUrl: downloads['web'] ?? "",
    );
  }
}

// --- Service ---

class _VersionService {
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

  _VersionService() {
    init();
  }

  Future<void> init() async {
    await _setCurrentVersion();
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
      final response = await http.get(Uri.parse(metadataUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch metadata: ${response.statusCode}');
      }

      final data = ReleaseMetadata.fromJson(json.decode(response.body));

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
    List<int> latestParts =
        latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> currentParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Ensure we have at least 3 parts (major.minor.patch)
    while (latestParts.length < 3) latestParts.add(0);
    while (currentParts.length < 3) currentParts.add(0);

    for (var i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }
}

final version = _VersionService();
