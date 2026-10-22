import 'dart:async';
import 'dart:convert';

import 'package:apexo/features/settings/services_settings/auth_settings.dart';
import 'package:apexo/features/settings/services_settings/backups_settings.dart';
import 'package:apexo/features/settings/services_settings/file_upload_settings.dart';
import 'package:apexo/features/settings/services_settings/meta_settings.dart';
import 'package:apexo/features/settings/services_settings/s3_settings.dart';
import 'package:apexo/features/settings/services_settings/smtp_settings.dart';
import 'package:apexo/services/login.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  late PocketBase? originalPocketBase;
  setUp(() => originalPocketBase = login.pb);
  tearDown(() => login.pb = originalPocketBase);

  const widgets = <Widget>[
    AuthSettings(),
    BackupsSettings(),
    FileUploadSettings(),
    MetaSettings(),
    S3Settings(),
    SmtpSettings(),
  ];

  for (final widget in widgets) {
    testWidgets('${widget.runtimeType} ignores a response after disposal',
        (tester) async {
      final response = Completer<http.Response>();
      var requests = 0;
      final client = MockClient((_) {
        requests++;
        return response.future;
      });
      addTearDown(client.close);
      login.pb =
          PocketBase('https://example.test', httpClientFactory: () => client);
      await tester.pumpWidget(FluentApp(home: widget));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      response.complete(http.Response(
          jsonEncode({
            'id': 'collection',
            'name': 'data',
            'type': 'base',
            'fields': [
              {'id': 'imgs', 'name': 'imgs', 'type': 'file', 'maxSize': 1048576}
            ],
            'meta': {'appName': 'Example', 'appURL': 'https://example.test'},
          }),
          200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(requests, widget is AuthSettings ? 2 : 1);
    });
  }

  testWidgets('failed metadata reads do not overwrite server settings',
      (tester) async {
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      return http.Response('{"message":"Unavailable"}', 503);
    });
    addTearDown(client.close);
    login.pb =
        PocketBase('https://example.test', httpClientFactory: () => client);
    await tester.pumpWidget(const FluentApp(home: MetaSettings()));
    await tester.pumpAndSettle();
    expect(methods, ['GET']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
