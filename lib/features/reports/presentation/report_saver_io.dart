// Native (Windows / macOS / Linux / Android) file save for report exports.
// Writes the bytes straight into the user's Downloads folder so a click on
// "PDF"/"Excel" downloads immediately to a findable location — no picker, no
// obscure temp path.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Writes [bytes] to the Downloads folder (desktop) — or the app documents
/// folder as a fallback (Android/iOS, where Downloads isn't exposed) — and
/// returns the absolute path. A numeric suffix is added if the file already
/// exists so repeated exports never overwrite each other.
Future<String?> savePlatformFile(Uint8List bytes, String name, String ext) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }
  dir ??= await getApplicationDocumentsDirectory();

  final safe = name.replaceAll(RegExp(r'[^\w\-. ]'), '_');
  final sep = Platform.pathSeparator;
  var file = File('${dir.path}$sep$safe.$ext');
  var i = 1;
  while (await file.exists()) {
    file = File('${dir.path}$sep$safe ($i).$ext');
    i++;
  }
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Opens the OS file browser with the saved file highlighted, so the user can
/// jump straight to it from the "Open folder" snackbar action.
Future<void> openContainingFolder(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', path]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [File(path).parent.path]);
    }
  } catch (_) {
    // Best-effort: if the shell call fails the file is still saved.
  }
}
