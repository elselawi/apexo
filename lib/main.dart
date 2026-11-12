import 'dart:async';

import 'package:apexo/app/routing/routes.dart';
import 'package:apexo/core/reactive/observable_base.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/file_links.dart';
import 'package:apexo/services/backdrop.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/session_events.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/services/localization/intl_data.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/error_reporting.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/app/app.dart';
import 'package:apexo/services/notifications/core_notifications_initializer.dart';
import 'package:apexo/utils/dicom_init.dart';
import 'package:apexo/app/data/initialize_booking.dart';
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

  await initDicomToolkit();

  if (kIsWeb == false) await Messaging.initializeReceiving();

  // initialize stores
  initializeStores();

  // The window is Mica on Windows; Dart paints the stand-in anywhere else, so
  // this has to settle before the first frame.
  await Backdrop.initialize(
    dark: localSettings.selectedTheme == ThemeMode.dark,
  );
  unawaited(localSettings.ready.then((_) => Backdrop.setDark(
        localSettings.selectedTheme == ThemeMode.dark,
      )));

  initializeBooking();

  SessionEvents.onEnded(() {
    routes.reset();
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    // A visit's draft belongs to the account that opened it; on logout there is
    // nobody left to prompt.
    appointmentSessions.clear();
  });
  SessionEvents.onStarted(
    () => unawaited(ApexoApp.showDialogsIfNeeded()),
  );

  // Uploads live in the appointments collection; image utils call this instead
  // of importing the feature.
  fileLinkResolver =
      (rowID, name) => appointments.remote!.getImageLink(rowID, name);

  // Must run before any login: `dicomCtrl` is a lazily-initialized top-level
  // final, so without this the auto-scan timer never starts.
  initializeDicomScan();

  if (kIsWeb) {
    JSBridge.removeItemFromSessionStorage('canvaskit_reload_count');
    // Web: the browser's context menu would cover the app's own, and on drag
    // rows it was the only one that opened.
    await SystemChannels.contextMenu.invokeMethod('disableContextMenu');
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
        // Sized so a widget failing every frame doesn't flood the buffer before
        // the error worth reading is recorded.
        options.maxBreadcrumbs = 300;
        options.beforeBreadcrumb = breadcrumbLimiter.limit;
      },
      appRunner: () {
        // Enrich the scope before Sentry's framework handler captures the event.
        installFlutterErrorReporting();
        runApp(const ApexoApp());
      },
    );
  }
}
