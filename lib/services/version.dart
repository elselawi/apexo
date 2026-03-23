import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/utils/logger.dart';

// --- Models ---

class ReleaseMetadata {
  final String latestVersion;
  final List<String> changelog;
  final String androidUrl;
  final String windowsUrl;

  ReleaseMetadata({
    required this.latestVersion,
    required this.changelog,
    required this.androidUrl,
    required this.windowsUrl,
  });

  factory ReleaseMetadata.fromJson(Map<String, dynamic> json) {
    final downloads = json['downloads'] as Map<String, dynamic>;
    return ReleaseMetadata(
      latestVersion: json['latest_version'] ?? "0.0.0",
      changelog: List<String>.from(json['changelog'] ?? []),
      androidUrl: downloads['android'] ?? "",
      windowsUrl: downloads['windows'] ?? "",
    );
  }
}

// --- Service ---

class _VersionService {
  // Observables
  final current = ObservableState("0.0.0");
  final isOutdated = ObservableState(false);
  final latestVersion = ObservableState("0.0.0");

  String latestAPKLink = "";
  String latestZipLink = "";
  List<String> changelog = [];

  // Your new Cloudflare R2 URL
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
      latestAPKLink = data.androidUrl;
      latestZipLink = data.windowsUrl;
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
