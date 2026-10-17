import 'package:apexo/core/reactive/observable_base.dart';
import 'package:apexo/services/localization/intl_data.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/app/app.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/utils/dicom_init.dart';
import 'package:apexo/app/data/initialize_stores.dart';
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
  reactiveErrorReporter = (error, stack) => logger(error, stack);
  reactiveSilentErrorReporter = (error, stack) {
    login.askForLoginAgain(error);
    logger(error, stack);
  };
  await initializeDateFormatting();
  ensureCustomIntlLocalesInitialized();
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('>>> ${record.level.name}: ${record.time}: ${record.message}');
  });

  // initialize the dicom_toolkit native (Rust/WASM) engine
  // non-fatal: app continues if the engine fails to load
  await initDicomToolkit();

  // initialize receiving notifications
  // on Android and iOS
  if (kIsWeb == false) await Messaging.initializeReceiving();

  // initialize stores
  initializeStores();

  // Register the DICOM scan lifecycle (the login activator) *before* any
  // login can run. `dicomCtrl` is a lazily-initialized top-level final, so
  // nothing else touches it early enough: without this the periodic
  // auto-scan timer is never started and X-rays are only picked up when the
  // dentist opens the DICOM page.
  initializeDicomScan();

  if (kIsWeb) {
    JSBridge.removeItemFromSessionStorage('canvaskit_reload_count');
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  if (kDebugMode) {
    // ignore: prefer_const_constructors
    runApp(ApexoApp());
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDSN;
      },
      appRunner: () => runApp(const ApexoApp()),
    );
  }
}
