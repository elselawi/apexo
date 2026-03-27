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
const String pagesProjectName = "apexo-web";

final List<String> changes = [];
String version = _readPubspecVersion();

void main() {
  print("🚀 Starting Production Build & Deploy...");

  final isPatch = _getIsPatch();

  if (!isPatch) {
    changes.addAll(_getChanges());
    version = _updateVersion();
  }

  // 1. Build for windows and android
  _buildNative(
    isPatch: isPatch,
    version: version,
  );

  // 2. Build Web (Keep in /dist/web for Git/Cloudflare Pages)
  _buildWeb(version);

  if (!isPatch) {
    // 3. Update Metadata & Changelog
    _finalizeRelease(version);
  }
}

// --- Core Logic ---

void _buildNative({
  required bool isPatch,
  required String version,
}) {
  print("\n📦 Building for windows and android");

  final executable = Platform.isWindows ? "shorebird.bat" : "shorebird";
  final shoreBirdCommand = isPatch ? "patch" : "release";

  _runCommand(
    executable,
    [
      shoreBirdCommand,
      "--platform",
      "android",
      if (!isPatch) ...["--artifact", "apk"],
    ],
  );
  _runCommand(
    executable,
    [shoreBirdCommand, "--platform", "windows"],
  );

  if (isPatch) return;

  final windowsInstallerPath =
      p.join(Directory.current.path, "temp_windows.zip");
  _createZip(
      p.join(Directory.current.path, "build", "windows", "x64", "runner",
          "Release"),
      windowsInstallerPath);

  final androidInstallerPath = p.join(
    Directory.current.path,
    "build",
    "app",
    "outputs",
    "flutter-apk",
    "app-release.apk",
  );

  // Upload to R2
  final r2PathWindows =
      "releases/$version/${appName}_windows_$version${p.extension(windowsInstallerPath)}";
  final r2PathAndroid =
      "releases/$version/${appName}_android_$version${p.extension(androidInstallerPath)}";
  _uploadToR2(windowsInstallerPath, r2PathWindows);
  _uploadToR2(androidInstallerPath, r2PathAndroid);

  // Cleanup temp zip if created
  File(windowsInstallerPath).deleteSync();
}

void _buildWeb(String version) {
  print("\n🌐 Building Web (Web app & demo app)...");
  _runCommand(Platform.isWindows ? "flutter.bat" : "flutter",
      ["build", "web", "--release"]);

  final webBuildPath = p.join(Directory.current.path, "build", "web");

  print(" 🚀 Deploying directly to Cloudflare Pages...");

  final wranglerCmd = Platform.isWindows ? "wrangler.cmd" : "wrangler";
  final deployRes = Process.runSync(wranglerCmd, [
    "pages",
    "deploy",
    webBuildPath,
    "--project-name=$pagesProjectName",
  ]);

  if (deployRes.exitCode == 0) {
    print(" ✅ Web version $version is now LIVE on Cloudflare Pages.");
  } else {
    print(" ❌ Web deployment failed: ${deployRes.stderr}");
    // We don't exit here because R2 builds might have succeeded,
    // but you should check why the upload failed.
  }
}

List<String> _getChanges() {
  final changesInput =
      _prompt("What are the changes? (separate by /// or leave empty)");
  return changesInput
      .split("///")
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

void _finalizeRelease(String version) {
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

// Determine content type based on extension
  String contentType = "application/octet-stream";
  if (remotePath.endsWith(".apk")) {
    contentType = "application/vnd.android.package-archive";
  } else if (remotePath.endsWith(".zip")) {
    contentType = "application/zip";
  } else if (remotePath.endsWith(".json")) {
    contentType = "application/json";
  }

  final result = Process.runSync(wranglerCmd, [
    "r2",
    "object",
    "put",
    "$bucketName/$remotePath",
    "--file=$localPath",
    "--content-type=$contentType",
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

bool _getIsPatch() {
  print("Is this a patch? (y/n, default: n)");
  final input = stdin.readLineSync() ?? "n";
  return input.toLowerCase() == "y";
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
