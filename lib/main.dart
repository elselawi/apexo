import 'package:apexo/app/app.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/utils/init_stores.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:apexo/sentry_dsn.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:apexo/utils/js/js_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en', null);
  await initializeDateFormatting('ar', null);
  await initializeDateFormatting('es', null);
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('>>> ${record.level.name}: ${record.time}: ${record.message}');
  });

  // initialize receiving notifications
  // on Android and iOS
  if (kIsWeb == false) await Messaging.initializeReceiving();

  // initialize stores
  initializeStores();

  if (kIsWeb) {
    JSBridge.removeItemFromSessionStorage('canvaskit_reload_count');
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  if (kDebugMode) {
    runApp(ApexoApp());
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDSN;
      },
      appRunner: () => runApp(ApexoApp()),
    );
  }
}
