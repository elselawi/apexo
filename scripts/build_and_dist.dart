// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import "package:archive/archive.dart";
import 'package:yaml/yaml.dart';

// --- Configuration ---
const String bucketName = "apexo-releases";
const String appName = "apexo";
const String bucketDomain = "download.apexo.app";

void main() {
  print("🚀 Starting Production Build & Deploy...");

  final version = _updateVersion();

  // 1. Build Windows (Zip and Upload to R2)
  _buildPlatform(
    platform: "windows",
    flutterArg: "windows",
    sourcePath: p.join(
        Directory.current.path, "build", "windows", "x64", "runner", "Release"),
    version: version,
    isArchive: true,
  );

  // 2. Build Android (APK and Upload to R2)
  _buildPlatform(
    platform: "android",
    flutterArg: "apk",
    sourcePath: p.join(Directory.current.path, "build", "app", "outputs",
        "flutter-apk", "app-release.apk"),
    version: version,
  );

  // 3. Build Web (Keep in /dist/web for Git/Cloudflare Pages)
  _buildWeb(version);

  // 4. Update Metadata & Changelog
  _finalizeRelease(version);
}

// --- Core Logic ---

void _buildPlatform({
  required String platform,
  required String flutterArg,
  required String sourcePath,
  required String version,
  bool isArchive = false,
}) {
  print("\n📦 Building $platform...");
  _runCommand(Platform.isWindows ? "flutter.bat" : "flutter",
      ["build", flutterArg, "--release"]);

  String finalFilePath;

  if (isArchive) {
    finalFilePath = p.join(Directory.current.path, "temp_${platform}.zip");
    _createZip(sourcePath, finalFilePath);
  } else {
    finalFilePath = sourcePath;
  }

  // Upload to R2
  final extension = p.extension(finalFilePath);
  final r2Path = "releases/$version/${appName}_${platform}_$version$extension";
  _uploadToR2(finalFilePath, r2Path);

  // Cleanup temp zip if created
  if (isArchive) File(finalFilePath).deleteSync();
}

void _buildWeb(String version) {
  print("\n🌐 Building Web (Local Dist for Pages - needs commit and push)...");
  _runCommand(Platform.isWindows ? "flutter.bat" : "flutter",
      ["build", "web", "--release"]);

  final source = Directory(p.join(Directory.current.path, "build", "web"));
  final destination = Directory(p.join(Directory.current.path, "dist", "web"));

  if (destination.existsSync()) destination.deleteSync(recursive: true);
  _copyDirectorySync(source, destination);
  print(" ✅ Web build moved to /dist/web for Git tracking.");
}

void _finalizeRelease(String version) {
  final changesInput =
      _prompt("What are the changes? (separate by /// or leave empty)");
  final changes = changesInput
      .split("///")
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  if (changes.isNotEmpty) {
    _prependChangelog(version, changes);
  }

  // Create and Upload metadata.json
  final metadata = {
    "latest_version": version,
    "updated_at": DateTime.now().toIso8601String(),
    "changelog": changes,
    "downloads": {
      "windows":
          "https://$bucketDomain/releases/$version/${appName}_windows_$version.zip",
      "android":
          "https://$bucketDomain/releases/$version/${appName}_android_$version.apk",
    }
  };

  final metaFile = File("metadata.json");
  metaFile.writeAsStringSync(jsonEncode(metadata));
  _uploadToR2(metaFile.path, "metadata.json");
  print("\n🎉 Release $version fully deployed to R2!");
}

// --- Helper Methods ---

void _uploadToR2(String localPath, String remotePath) {
  final wranglerCmd = Platform.isWindows ? "wrangler.cmd" : "wrangler";
  print(" ☁️  Uploading to R2: $remotePath");
  Platform.isWindows ? "wrangler.cmd" : "wrangler";
  final result = Process.runSync(wranglerCmd, [
    "r2",
    "object",
    "put",
    "$bucketName/$remotePath",
    "--file=$localPath",
    "--remote"
  ]);
  if (result.exitCode != 0) {
    print(" ❌ Upload failed: ${result.stderr}");
    exit(1);
  }
}

void _runCommand(String cmd, List<String> args) {
  final res = Process.runSync(cmd, args, environment: Platform.environment);
  if (res.exitCode != 0) {
    print("Error running $cmd: ${res.stderr}");
    exit(1);
  }
}

String _updateVersion() {
  final current = _readPubspecVersion();
  print("Current version: $current");
  final next = _prompt("New version (leave empty to keep):").trim();
  final finalVer = next.isEmpty ? current : next;

  if (next.isNotEmpty) {
    final file = File("pubspec.yaml");
    final content = file
        .readAsStringSync()
        .replaceAll("version: $current", "version: $next");
    file.writeAsStringSync(content);
  }
  return finalVer;
}

void _createZip(String dirPath, String zipPath) {
  final archive = Archive();
  final dir = Directory(dirPath);
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final content = entity.readAsBytesSync();
      final relPath = p.relative(entity.path, from: dirPath);
      archive.addFile(ArchiveFile(relPath, content.length, content));
    }
  }
  File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive)!);
}

// Standard helper for deep-copying directories
void _copyDirectorySync(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (var entity in source.listSync()) {
    final newPath = p.join(destination.path, p.basename(entity.path));
    if (entity is File)
      entity.copySync(newPath);
    else if (entity is Directory)
      _copyDirectorySync(entity, Directory(newPath));
  }
}

String _readPubspecVersion() {
  final yaml = loadYaml(File("pubspec.yaml").readAsStringSync());
  return yaml["version"];
}

String _prompt(String m) {
  stdout.write("$m\n> ");
  return stdin.readLineSync() ?? "";
}

void _prependChangelog(String version, List<String> changes) {
  final file = File("CHANGELOG.md");
  final current = file.existsSync() ? file.readAsStringSync() : "";
  final newEntry = "### [$version]\n- ${changes.join("\n- ")}\n\n";
  file.writeAsStringSync(newEntry + current);
}
