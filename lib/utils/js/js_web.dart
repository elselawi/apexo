// js_web.dart
import 'dart:js_interop';
import 'dart:js_interop_unsafe'; // Required for dynamic property setting
import 'package:web/web.dart' as web;

class JSBridgeImpl {
  static void setGlobalVariable(String name, String value) {
    // 1. Get the window object
    // 2. Use the 'setProperty' extension from js_interop_unsafe
    web.window.setProperty(name.toJS, value.toJS);
  }
}
