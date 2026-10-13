import 'dart:typed_data';

import 'package:apexo/app/app.dart';
import 'package:apexo/core/persistence/save_remote.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

class RecordingFilePicker extends FilePickerPlatform {
  String? savedName;
  Uint8List? savedBytes;
  int saves = 0;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    saves++;
    // A browser download or a canceled native dialog returns no path.
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingFilePicker picker;
  late MockClient client;
  late SaveRemote remote;
  late List<Uri> downloads;
  const payload = [0, 1, 2, 127, 255];
  var statusCode = 200;

  setUp(() {
    final previousPicker = FilePickerPlatform.instance;
    final previousRemote = appointments.remote;
    picker = RecordingFilePicker();
    FilePickerPlatform.instance = picker;
    downloads = [];
    statusCode = 200;
    client = MockClient((request) async {
      if (request.url.path.endsWith('/api/health')) {
        return http.Response('{}', 200);
      }
      downloads.add(request.url);
      return http.Response.bytes(payload, statusCode);
    });
    remote = SaveRemote(
      storeName: 'appointments',
      pbInstance:
          PocketBase('https://files.example', httpClientFactory: () => client),
    );
    remote.fullNamesCache['download-row'] = [
      'download_photo_abcdef.jpg',
      'download_scan_abcdef.dcm',
      'download_scan_abcdef.dcm.png',
    ];
    appointments.remote = remote;
    addTearDown(() {
      FilePickerPlatform.instance = previousPicker;
      appointments.remote = previousRemote;
      remote.dispose();
      client.close();
    });
  });

  Future<void> mountContext(WidgetTester tester) async {
    await tester.pumpWidget(FluentApp(
      home: Builder(builder: (context) {
        bContext = context;
        return const SizedBox.shrink();
      }),
    ));
  }

  for (final extension in ['jpg', 'dcm']) {
    final name = extension == 'jpg'
        ? 'download_photo_abcdef.jpg'
        : 'download_scan_abcdef.dcm';
    testWidgets('downloads remote $extension bytes without a local file',
        (tester) async {
      await mountContext(tester);
      await tester.runAsync(() => http.runWithClient(
            () => downloadFile('download-row', name),
            () => client,
          ));

      expect(downloads.single.pathSegments.last, name);
      expect(picker.savedName, displayNameForFile(name));
      expect(picker.savedBytes, payload);
      expect(picker.saves, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('downloads a direct URL without a row ID', (tester) async {
    await mountContext(tester);
    const url = 'https://files.example/photo.jpg';
    await http.runWithClient(() => downloadFile(null, url), () => client);

    expect(downloads.single.toString(), url);
    expect(picker.savedName, 'photo.jpg');
    expect(picker.savedBytes, payload);
  });

  testWidgets('failed HTTP download does not save an error response',
      (tester) async {
    await mountContext(tester);
    statusCode = 404;
    await tester.runAsync(() => expectLater(
          http.runWithClient(
            () => downloadFile('download-row', 'download_photo_abcdef.jpg'),
            () => client,
          ),
          throwsA(isA<Exception>().having(
              (e) => e.toString(), 'message', contains('Download failed'))),
        ));
    expect(picker.saves, 0);
  });

  testWidgets('missing file reports not found without trying to save',
      (tester) async {
    await mountContext(tester);
    await tester.runAsync(() => expectLater(
          downloadFile(null, 'download_missing_abcdef.dcm'),
          throwsA(isA<Exception>().having(
              (e) => e.toString(), 'message', contains('File not found'))),
        ));
    expect(downloads, isEmpty);
    expect(picker.saves, 0);
  });
}
