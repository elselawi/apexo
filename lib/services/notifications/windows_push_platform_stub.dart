/// Web — and any build without `dart:io` — has no Windows push service.
bool get isWindowsPlatform => false;

Future<void> startWindowsPushReceiving() async {}

void requestWindowsPushRegistration({required bool isPatient}) {}

Future<void> promoteWindowsPushInstance() async {}
