// ============================================================
// KATIYA STATION RMS — IMAGE URL HELPER
// Makes externally-hosted menu images load reliably & fast in the browser.
// ============================================================

import 'package:flutter/foundation.dart' show kIsWeb;

/// Returns a display-ready URL for a menu image.
///
/// On **web** the raw URL is routed through the wsrv.nl image CDN, which:
///   • adds the `Access-Control-Allow-Origin` header the browser requires —
///     many image hosts don't send it, so the raw link loads fine in the
///     desktop/mobile app (native ignores CORS) but is silently blocked in a
///     browser, showing the placeholder instead;
///   • resizes to a card-sized width and re-encodes to WebP, so a card pulls a
///     ~20–40 KB thumbnail instead of a full-resolution photo — much faster and
///     cached on the CDN edge.
///
/// On **native** (Android / Windows / desktop) the original URL is returned
/// unchanged: CORS doesn't apply there and we avoid depending on a third-party
/// proxy for the installed app.
///
/// [width] is the target pixel width to downscale to (device-independent px ×
/// devicePixelRatio is a good input from the call site; a 2× card is plenty).
String menuImageUrl(String raw, {int width = 400}) {
  final url = raw.trim();
  if (url.isEmpty) return url;
  if (!kIsWeb) return url;

  // Data URIs and already-proxied URLs are passed through untouched.
  if (url.startsWith('data:') || url.startsWith('https://wsrv.nl/')) return url;

  final encoded = Uri.encodeComponent(url);
  // n=-1 → keep aspect ratio; q=80 → good quality/size tradeoff.
  return 'https://wsrv.nl/?url=$encoded&w=$width&output=webp&q=80';
}
