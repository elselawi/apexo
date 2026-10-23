import 'windows_notification_id_allocator.dart';

const int maxWindowsNotificationId = WindowsNotificationIdAllocator.maxId;

final WindowsNotificationIdAllocator _windowsNotificationIds =
    WindowsNotificationIdAllocator();

Future<int> nextWindowsNotificationId() => _windowsNotificationIds.nextId();
