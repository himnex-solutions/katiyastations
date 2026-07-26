// ============================================================
// KATIYA STATION RMS — MENU IMAGE PRE-CACHE
// While online, downloads EVERY menu image into the same disk cache that
// CachedNetworkImage reads from — so when the internet drops, the waiter sees
// all menu photos, not only the ones that happened to load earlier.
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils/image_url.dart';

/// Downloads each image URL into the shared [DefaultCacheManager] store (the
/// one CachedNetworkImage uses when no custom manager is given), so it's
/// available offline. Best-effort and sequential to stay gentle on the network;
/// already-cached images are skipped by the manager, so re-runs are cheap.
Future<void> precacheMenuImages(Iterable<String?> rawUrls) async {
  // Web keeps its own browser cache and routes through a CDN proxy; the offline
  // target is the installed native app, so only pre-cache there.
  if (kIsWeb) return;

  final cache = DefaultCacheManager();
  // De-dupe so the same photo shared by several items downloads once.
  final urls = <String>{
    for (final raw in rawUrls)
      if (raw != null && raw.trim().isNotEmpty) menuImageUrl(raw, width: 400),
  };

  for (final url in urls) {
    try {
      // Checks the cache first; downloads + stores only if missing.
      await cache.getSingleFile(url);
    } catch (_) {
      // A broken/unreachable image URL must not stop the rest.
    }
  }
}
