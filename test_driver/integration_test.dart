// The host side of a web run of `integration_test`: `flutter drive` runs this
// file in the Dart VM and talks to the app in the browser through chromedriver.
//
// Only the web runs load it:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//       --target=integration_test/integration.dart -d chrome
//
// Native runs (`flutter test integration_test/integration.dart -d windows`)
// never touch it.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
