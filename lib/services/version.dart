import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:apexo/core/observable.dart';
import 'package:apexo/utils/logger.dart';

class GithubFile implements Comparable<GithubFile> {
  final String name;
  final String? downloadUrl;
  final String version;
  final int major, minor, patch;

  GithubFile({
    required this.name,
    required this.downloadUrl,
    required this.version,
    required this.major,
    required this.minor,
    required this.patch,
  });

  factory GithubFile.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final versionMatch = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(name);
    
    final maj = int.tryParse(versionMatch?.group(1) ?? '0') ?? 0;
    final min = int.tryParse(versionMatch?.group(2) ?? '0') ?? 0;
    final pat = int.tryParse(versionMatch?.group(3) ?? '0') ?? 0;

    return GithubFile(
      name: name,
      downloadUrl: json['download_url'],
      version: '$maj.$min.$pat',
      major: maj,
      minor: min,
      patch: pat,
    );
  }

  /// Returns true if this file's version is strictly greater than the provided string
  bool isNewerThan(String currentVersion) {
    final parts = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.length < 3) return true;

    if (major != parts[0]) return major > parts[0];
    if (minor != parts[1]) return minor > parts[1];
    return patch > parts[2];
  }

  @override
  int compareTo(GithubFile other) {
    if (major != other.major) return other.major.compareTo(major);
    if (minor != other.minor) return other.minor.compareTo(minor);
    return other.patch.compareTo(patch);
  }
}


class _GithubReleaseClient {
  final String owner;
  final String repo;

  _GithubReleaseClient({required this.owner, required this.repo});

  Future<List<GithubFile>> fetchFiles(String path) async {
    final url = Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$path');
    final response = await http.get(url, headers: {'Accept': 'application/vnd.github.v3+json'});

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch repo: ${response.statusCode}');
    }

    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => GithubFile.fromJson(json)).toList();
  }
}

class _VersionService {
  // Observables
  final current = ObservableState("0.0.0");
  final isOutdated = ObservableState(false);
  String latestAPKLink = "";
  String latestZipLink = "";

  final _client = _GithubReleaseClient(owner: 'elselawi', repo: 'apexo');

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
      final allFiles = await _client.fetchFiles('dist');
      if (allFiles.isEmpty) return;

      // Sort newest first
      allFiles.sort();

      final latestApk = allFiles.where((f) => f.name.endsWith('.apk')).firstOrNull;
      final latestZip = allFiles.where((f) => f.name.endsWith('.zip')).firstOrNull;

      if (latestApk != null) {
        latestAPKLink = latestApk.downloadUrl ?? "";
        isOutdated(latestApk.isNewerThan(current()));
      }
      
      latestZipLink = latestZip?.downloadUrl ?? "";
      
    } catch (e, s) {
      logger("Update check failed: $e", s);
    }
  }
}

final version = _VersionService();