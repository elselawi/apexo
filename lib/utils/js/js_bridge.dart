// js_bridge.dart
import 'js_stub.dart' if (dart.library.js_interop) 'js_web.dart';

abstract class JSBridge {
  static void setGlobalVariable(String name, String value) {
    return JSBridgeImpl.setGlobalVariable(name, value);
  }

  static void removeItemFromSessionStorage(String key) {
    return JSBridgeImpl.removeItemFromSessionStorage(key);
  }
}
