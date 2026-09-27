// js_stub.dart
class JSBridgeImpl {
  static void setGlobalVariable(String name, String value) {
    // No-op for Android/Windows. Deliberately silent: this is called on every
    // local-settings change, and the platform is not a surprise worth logging.
  }

  static void removeItemFromSessionStorage(String key) {
    // No-op for Android/Windows
  }
}
