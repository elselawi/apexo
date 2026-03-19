import 'dart:js_interop';
import 'dart:typed_data'; // Required for Uint8List
import 'package:web/web.dart' as web;

class SaveFileImpl {
  static void saveFileWeb(List<int> bytes, String fileName) {
    // 1. Convert to Uint8List, then to a JS Uint8Array
    final uint8list = Uint8List.fromList(bytes);
    final jsArray = uint8list.toJS;

    // 2. Create the Blob (the constructor expects an Iterable of JS objects)
    final blob = web.Blob([jsArray].toJS);

    // 3. Create the object URL
    final url = web.URL.createObjectURL(blob);

    // 4. Create anchor and trigger download
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    anchor.click();

    // 5. Cleanup
    web.URL.revokeObjectURL(url);
  }
}
