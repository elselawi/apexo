import 'package:apexo/ui/workspace/window_defaults.dart';

/// Gives each test a fresh in-memory [windowDefaults]; production binds a
/// settings-backed store at the root, so nothing here touches Hive.
Future<void> resetWindowDefaults() async {
  String stored = '';
  windowDefaults = WindowDefaults(
    read: () => stored,
    write: (value) => stored = value,
  );
}
