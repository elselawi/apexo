// js_stub.dart
class JSBridgeImpl {
  static void setGlobalVariable(String name, String value) {
    // No-op for Android/Windows
    print("JS interop ignored on this platform.");
  }
}
