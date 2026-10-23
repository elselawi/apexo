import 'dart:io';

import 'windows_push_service.dart';

bool get isWindowsPlatform => Platform.isWindows;

Future<void> startWindowsPushReceiving() async {
  if (!isWindowsPlatform) return;
  await WindowsPushService.instance.startReceiving();
}

void requestWindowsPushRegistration({required bool isPatient}) {
  if (!isWindowsPlatform) return;
  WindowsPushService.instance.requestRegistration(isPatient: isPatient);
}

Future<void> promoteWindowsPushInstance() async {
  if (!isWindowsPlatform) return;
  await WindowsPushService.instance.promoteToInteractive();
}
