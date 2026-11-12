@Tags(['serial'])
library;

import 'package:apexo/services/server_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late Future<http.Response> Function(Uri) originalGet;
  late Duration originalTimeout;
  late Duration originalDelay;

  setUp(() {
    originalGet = serverStatus.get;
    originalTimeout = serverStatus.requestTimeout;
    originalDelay = serverStatus.displayDelay;
    serverStatus.displayDelay = Duration.zero;
  });

  tearDown(() {
    serverStatus.get = originalGet;
    serverStatus.requestTimeout = originalTimeout;
    serverStatus.displayDelay = originalDelay;
  });

  group('ServerStatusMessage', () {
    test('a body with nothing to say carries no message', () {
      for (final body in [
        '',
        'not json',
        '[]',
        '{}',
        '{"active": false, "message": "off"}',
        '{"active": true}',
        '{"active": true, "message": ""}',
        '{"active": true, "message": "   "}',
        '{"active": true, "message": 42}',
        '{"message": "no active flag"}',
      ]) {
        expect(ServerStatusMessage.fromBody(body), isNull, reason: body);
      }
    });

    test('an active message is read with its dismissable flag', () {
      final status = ServerStatusMessage.fromBody(
          '{"active": true, "dismissable": true, "message": "Maintenance"}');
      expect(status, isNotNull);
      expect(status!.message, 'Maintenance');
      expect(status.dismissable, isTrue);
    });

    test('a missing or non-boolean dismissable is treated as blocking', () {
      for (final body in [
        '{"active": true, "message": "Maintenance"}',
        '{"active": true, "dismissable": "yes", "message": "Maintenance"}',
      ]) {
        expect(ServerStatusMessage.fromBody(body)!.dismissable, isFalse,
            reason: body);
      }
    });
  });

  group('ServerStatusService', () {
    test('reads the host out of the server URL', () {
      expect(serverStatus.hostOf('https://clinic.example.com/pocketbase'),
          'clinic.example.com');
      expect(serverStatus.hostOf('https://Clinic.Example.COM'),
          'clinic.example.com');
      expect(serverStatus.hostOf('clinic.example.com'), 'clinic.example.com');
      expect(
          serverStatus.hostOf('clinic.example.com:8090'), 'clinic.example.com');
      expect(serverStatus.hostOf(''), isEmpty);
    });

    test('asks the status endpoint for the host that logged in', () async {
      final requested = <Uri>[];
      serverStatus.get = (uri) async {
        requested.add(uri);
        return http.Response('{}', 200);
      };

      await serverStatus.show('https://clinic.example.com/pocketbase');

      expect(requested.map((uri) => uri.toString()),
          ['https://servers.apexo.app/hosted/clinic.example.com']);
    });

    test('a login without a host asks nothing', () async {
      var called = false;
      serverStatus.get = (_) async {
        called = true;
        return http.Response('', 200);
      };

      await serverStatus.show('');

      expect(called, isFalse);
    });

    test('an unreachable status endpoint is ignored', () async {
      serverStatus.get = (_) async => throw http.ClientException('offline');

      await expectLater(
          serverStatus.show('https://clinic.example.com'), completes);
    });

    test('an active message does not outlive the session that asked for it',
        () async {
      serverStatus.get = (_) async => http.Response(
          '{"active": true, "dismissable": true, "message": "Maintenance"}',
          200);

      await expectLater(
        serverStatus.show('https://clinic.example.com', isCurrent: () => false),
        completes,
      );
    });
  });
}
