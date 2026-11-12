@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/app/app_context.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/server_status_dialog.dart';
import 'package:apexo/services/server_status.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/pump_app.dart';

void main() {
  late Future<http.Response> Function(Uri) originalGet;
  late Duration originalDelay;

  setUp(() {
    originalGet = serverStatus.get;
    originalDelay = serverStatus.displayDelay;
    serverStatus.displayDelay = Duration.zero;
  });

  tearDown(() {
    serverStatus.get = originalGet;
    serverStatus.displayDelay = originalDelay;
  });

  /// Pumps an app whose content is the global dialog context, then lets the
  /// service fetch [body] and show whatever it publishes.
  Future<void> pumpStatus(WidgetTester tester, String body) async {
    serverStatus.get = (_) async => http.Response(body, 200);
    await pumpApexoApp(
      tester,
      Builder(builder: (context) {
        bContext = context;
        return const SizedBox.expand();
      }),
    );
    unawaited(serverStatus.show('https://clinic.example.com'));
    await tester.pumpAndSettle();
  }

  const active =
      '{"active": true, "dismissable": true, "message": "Scheduled maintenance"}';
  const blocking =
      '{"active": true, "dismissable": false, "message": "Server migration in progress"}';

  /// A blocking message has no way out, so the test closes its route directly.
  Future<void> closeRoute(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(ServerStatusDialog)),
            rootNavigator: true)
        .pop();
    await tester.pumpAndSettle();
  }

  testWidgets('shows the server message verbatim', (tester) async {
    await pumpStatus(tester, active);

    expect(find.text('Scheduled maintenance'), findsWidgets);

    await tester.tap(find.byType(CloseButtonInDialog));
    await tester.pumpAndSettle();
  });

  testWidgets('a payload with no active message shows nothing', (tester) async {
    await pumpStatus(tester, '{}');

    expect(find.byType(ServerStatusDialog), findsNothing);
  });

  testWidgets('a dismissable message closes with Escape or its button',
      (tester) async {
    await pumpStatus(tester, active);
    expect(find.byType(ServerStatusDialog), findsOneWidget);
    expect(find.byType(CloseButtonInDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ServerStatusDialog), findsNothing);

    await pumpStatus(tester, active);
    await tester.tap(find.byType(CloseButtonInDialog));
    await tester.pumpAndSettle();
    expect(find.byType(ServerStatusDialog), findsNothing);
  });

  testWidgets('a dismissable message closes when the barrier is clicked',
      (tester) async {
    await pumpStatus(tester, active);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(ServerStatusDialog), findsNothing);
  });

  testWidgets('a blocking message has no close action and ignores Escape',
      (tester) async {
    await pumpStatus(tester, blocking);
    expect(find.byType(ServerStatusDialog), findsOneWidget);
    expect(find.byType(CloseButtonInDialog), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ServerStatusDialog), findsOneWidget);

    await closeRoute(tester);
  });

  testWidgets('a blocking message ignores clicks on the barrier',
      (tester) async {
    await pumpStatus(tester, blocking);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(ServerStatusDialog), findsOneWidget);

    await closeRoute(tester);
  });
}
