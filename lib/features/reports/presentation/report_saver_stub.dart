// Web fallback for report file saving. On the web the browser performs the
// download itself (via file_saver), so there's no local filesystem path to
// return and nothing to "open".

import 'dart:typed_data';

/// Web has no direct filesystem access — signal "use the browser download"
/// by returning null so the caller falls back to file_saver.
Future<String?> savePlatformFile(Uint8List bytes, String name, String ext) async => null;

Future<void> openContainingFolder(String path) async {}
