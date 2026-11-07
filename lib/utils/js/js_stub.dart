// js_stub.dart
class JSBridgeImpl {
  static void setGlobalVariable(String name, String value) {
    // No-op off web; called on every settings change, so it stays silent.
  }

  static void removeItemFromSessionStorage(String key) {
    // No-op for Android/Windows
  }
}
