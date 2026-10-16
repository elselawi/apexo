#!/usr/bin/env dart run
// iOS Launch Image Generator
// Usage: dart run tools/generate_launch_image.dart
//
// `flutter build ipa` reports "Launch image is set to the default placeholder icon"
// for as long as ios/Runner/Assets.xcassets/LaunchImage.imageset still holds the 1x1
// transparent PNGs that `flutter create` wrote: Flutter validates that imageset
// against its own template images and warns when the bytes are unchanged.
// `flutter_launcher_icons` only ever writes AppIcon.appiconset (it has no launch-image
// support), so the imageset has to be regenerated from the app icon by this script.
//
// A developer CLI, not app code: it lives in `tools/` (not under `lib/`), it is never
// imported, and its whole output is a short console summary, so `print` is the correct
// channel here and the logging framework the lint suggests would be wrong.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:image/image.dart' as img;

/// Source artwork: the iOS app icon, i.e. the same art `flutter_launcher_icons`
/// derives `AppIcon.appiconset` from. It is the tooth on white with no app-icon frame,
/// which is what the launch screen wants (the storyboard background is white too).
const String _sourcePath = 'assets/app_icon_ios.png';

/// The storyboard draws the image at its intrinsic size, so this is the size the logo
/// renders at on screen. Kept in sync with the `LaunchImage` storyboard entry by
/// [_syncStoryboardSize], because the storyboard caches the image's size.
const int _pointSize = 168;

const String _imagesetDir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
const String _storyboardPath = 'ios/Runner/Base.lproj/LaunchScreen.storyboard';

void main() {
  final File source = File(_sourcePath);
  if (!source.existsSync()) {
    _fail('$_sourcePath not found. Run this from the repository root.');
  }

  final img.Image? decoded = img.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    _fail('Could not decode $_sourcePath as an image.');
  }

  Directory(_imagesetDir).createSync(recursive: true);

  for (final int scale in <int>[1, 2, 3]) {
    final int pixels = _pointSize * scale;
    final String suffix = scale == 1 ? '' : '@${scale}x';
    final File output = File('$_imagesetDir/LaunchImage$suffix.png');
    // `average` box-filters the pixels, the only interpolation that stays clean when
    // downscaling the 1024px source by more than 2x.
    final img.Image resized = img.copyResize(
      decoded,
      width: pixels,
      height: pixels,
      interpolation: img.Interpolation.average,
    );
    output.writeAsBytesSync(img.encodePng(resized));
    print('${output.path} (${pixels}x$pixels)');
  }

  _syncStoryboardSize();
}

/// Xcode caches the image's size in the storyboard; without this it keeps claiming
/// Flutter's placeholder size of 168x185.
void _syncStoryboardSize() {
  final File storyboard = File(_storyboardPath);
  if (!storyboard.existsSync()) {
    return;
  }
  final String contents = storyboard.readAsStringSync();
  final String updated = contents.replaceFirstMapped(
    RegExp(r'<image name="LaunchImage" width="\d+" height="\d+"'),
    (Match _) =>
        '<image name="LaunchImage" width="$_pointSize" height="$_pointSize"',
  );
  if (updated != contents) {
    storyboard.writeAsStringSync(updated);
  }
}

Never _fail(String message) {
  stderr.writeln('error: $message');
  exit(1);
}
