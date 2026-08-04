import 'package:apexo/app/app.dart';
import 'package:apexo/utils/init_stores.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/live_backend/test_utils.dart';
import 'base.dart';

void main() async {
  TestUtils.integrationLoggerInit();
  await TestUtils.removeLocalData();
  await TestUtils.resetServer();
  initializeStores();

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Integration test', () {
    testWidgets('integration test', (tester) async {
      try {
        // Load app widget
        await tester.pumpWidget(const ApexoApp());
        expect(find.byKey(WK.appLogo), findsOneWidget);

        // ------ being integration tests //

        // there's no PB here, so this cuts of the connectivity for faster tests
        final baseURL = login.pb!.baseURL;
        login.pb!.baseURL = "https://apexo.app";
        // run tests that don't require connectivity first, then the ones that do, s

        login.pb!.baseURL = baseURL;
        // run tests that require connectivity last

        // ------ end integration tests //

        logger('\x1B[32m---------------------------------------------\x1B[0m',
            null, 3);
        int noOfPassedTests = 0;
        for (var groupName in passedTests.keys) {
          for (var testName in passedTests[groupName]!) {
            logger('\x1B[32m✔️ Passed $groupName: $testName\x1B[0m', null, 3);
            noOfPassedTests++;
          }
        }

        logger(
            '\x1B[32m✔️✔️✔️✔️✔️ ALL ($noOfPassedTests) INTEGRATION TEST SUCCESS!✔️✔️✔️✔️✔️\x1B[0m',
            null,
            3);
        logger('\x1B[32m---------------------------------------------\x1B[0m',
            null, 3);
      } catch (e, s) {
        logger("Error: $e", s, 1);
        logger('\x1B[31m❌❌❌❌❌ INTEGRATION TEST FAILED! ❌❌❌❌❌\x1B[0m', null, 1);
      }

      await Future.delayed(const Duration(hours: 2));
    });
  });
}
