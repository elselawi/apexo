// js_bridge.dart
import 'js_stub.dart' if (dart.library.js_interop) 'js_web.dart';

abstract class JSBridge {
  static void setGlobalVariable(String name, String value) {
    // If the conditional import fails, it lands here.
    // We call the version in the imported file.
    return JSBridgeImpl.setGlobalVariable(name, value);
  }
}
