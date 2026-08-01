import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/lan/lan_config.dart';
import '../../../../core/lan/lan_mirror.dart';
import '../../../../core/lan/lan_sync.dart';
import '../../../../core/offline/connectivity_provider.dart';
import '../../../../core/offline/offline_cache.dart';
import '../../../../core/offline/offline_store.dart'; // OfflineKot/Item models
import '../../../../core/offline/offline_ids.dart';
import '../../../../core/offline/sync_engine.dart';
import '../../../../core/offline/menu_image_precache.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../menu/domain/entities/menu_entities.dart';
import '../../../tables/presentation/providers/tables_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../domain/entities/order_entities.dart';

List<MenuCategory> _activeCategories(List<dynamic> rows) => rows
    .map((r) => MenuCategory.fromJson(r as Map<String, dynamic>))
    .where((c) => c.isActive)
    .toList()
  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

List<MenuItem> _availableItems(List<dynamic> rows) => rows
    .map((r) => MenuItem.fromJson(r as Map<String, dynamic>))
    .where((i) => i.isAvailable)
    .toList()
  ..sort((a, b) => a.name.compareTo(b.name));

/// Offline-first fetch: when the app is offline and a cached copy exists, it is
/// returned **immediately** — no network call, so nothing waits on a timeout.
/// Otherwise it fetches, caches on success, and falls back to the cache on a
/// network failure. This is what keeps the waiter screen instant with no
/// internet instead of stalling on every load.
Future<List<T>> _offlineFirst<T>(
  Ref ref,
  String key,
  Future<List<dynamic>> Function() fetch,
  List<T> Function(List<dynamic>) map,
) async {
  if (!ref.read(connectivityProvider)) {
    final cached = await OfflineCache.instance.get(key);
    if (cached is List) return map(cached);
  }
  try {
    final rows = await fetch();
    await OfflineCache.instance.put(key, rows);
    return map(rows);
  } on NetworkException {
    final cached = await OfflineCache.instance.get(key);
    if (cached is List) return map(cached);
    rethrow;
  }
}

Future<List<dynamic>> _getRows(String path, Map<String, dynamic> query) async =>
    (await ApiClient.instance.get(path, queryParameters: query)).data as List<dynamic>;

// Menu categories for ordering (by branchId). Offline-first so the waiter can
// still build an order with no internet, instantly.
final menuCategoriesProvider =
    FutureProvider.family<List<MenuCategory>, String>((ref, branchId) {
  return _offlineFirst(
    ref,
    CacheKeys.menuCategories(branchId),
    () => _getRows(ApiConstants.menuCategories, {'branchId': branchId}),
    _activeCategories,
  );
});

// Menu items for ordering (by categoryId).
final menuItemsProvider =
    FutureProvider.family<List<MenuItem>, String>((ref, categoryId) {
  return _offlineFirst(
    ref,
    CacheKeys.menuItemsByCategory(categoryId),
    () => _getRows(ApiConstants.menuItems, {'categoryId': categoryId}),
    _availableItems,
  );
});

// All menu items across every category for a branch — used by menu search.
final allMenuItemsProvider =
    FutureProvider.family<List<MenuItem>, String>((ref, branchId) {
  return _offlineFirst(
    ref,
    CacheKeys.menuItemsByBranch(branchId),
    () => _getRows(ApiConstants.menuItems, {'branchId': branchId}),
    _availableItems,
  );
});

/// Side-effect provider: while online, downloads every menu image so the waiter
/// sees them ALL offline — not just the ones that happened to load. Re-runs
/// cheaply (already-cached images are skipped) and no-ops offline. Watch it
/// from the shell so it warms the cache as soon as a user is signed in.
final menuImagePrecacheProvider =
    FutureProvider.family<void, String>((ref, branchId) async {
  if (!ref.watch(connectivityProvider)) return;
  final items = await ref.watch(allMenuItemsProvider(branchId).future);
  await precacheMenuImages(items.map((i) => i.imageUrl));
});

KotWithItems _kotWithItemsFromJson(Map<String, dynamic> json) => KotWithItems(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      sessionId: json['session_id'] as String,
      tableId: json['table_id'] as String? ?? '',
      kotNumber: json['kot_number'] as String,
      status: json['status'] as String? ?? 'pending',
      waiterId: json['waiter_id'] as String?,
      waiterName: json['waiter_name'] as String?,
      items: List<Map<String, dynamic>>.from(json['items'] as List? ?? []),
      createdAt: DateTime.parse(json['created_at'] as String),
      notes: json['notes'] as String?,
    );

/// KOTs taken offline for [sessionId] (not yet uploaded), rebuilt from the
/// local Isar copy so they render on the order screen like server ones.
Future<List<KotWithItems>> _offlineKotsFor(String sessionId) async {
  final kots = await OfflineStore.instance.kotsForSession(sessionId);
  final result = <KotWithItems>[];
  for (final k in kots) {
    final items = await OfflineStore.instance.itemsForKot(k.id);
    result.add(KotWithItems(
      id: k.id,
      branchId: k.branchId,
      sessionId: k.sessionId,
      tableId: k.tableId,
      kotNumber: k.kotNumber,
      status: k.status,
      waiterId: k.waiterId,
      waiterName: k.waiterName,
      items: items
          .map((i) => <String, dynamic>{
                'id': i.id,
                'kot_id': k.id,
                'menu_item_id': i.menuItemId,
                'name': i.menuItemName,
                'quantity': i.quantity,
                'unit_price': i.unitPrice,
                'note': i.notes,
                'status': 'pending',
              })
          .toList(),
      createdAt: k.createdAt,
    ));
  }
  return result;
}

/// Re-applies locally-recorded cancels on top of what the server just sent.
///
/// The server is authoritative for everything EXCEPT a cancel this device has
/// recorded but not yet managed to deliver. For that window the local fact
/// wins: a whole tombstoned order is dropped, and tombstoned lines are removed
/// from the orders that survive (an order left with no live lines is dropped
/// too, exactly as cancelling its last line would).
///
/// Public so the tests exercise this exact function rather than a restatement
/// of it — a copy in the test would keep passing after this one changed.
Future<List<KotWithItems>> applyCancelTombstones(List<KotWithItems> kots) async {
  if (kots.isEmpty) return kots;
  final cancelledKots = await OfflineCache.instance.cancelledKotIds();
  final cancelledItems = await OfflineCache.instance.cancelledItemIds();
  if (cancelledKots.isEmpty && cancelledItems.isEmpty) return kots;

  final result = <KotWithItems>[];
  for (final k in kots) {
    if (cancelledKots.contains(k.id)) continue;
    if (cancelledItems.isEmpty) {
      result.add(k);
      continue;
    }
    final liveItems = k.items
        .where((i) => !cancelledItems.contains(i['id'] as String?))
        .toList();
    if (liveItems.isEmpty) continue;
    result.add(KotWithItems(
      id: k.id,
      branchId: k.branchId,
      sessionId: k.sessionId,
      tableId: k.tableId,
      kotNumber: k.kotNumber,
      status: k.status,
      waiterId: k.waiterId,
      waiterName: k.waiterName,
      items: liveItems,
      createdAt: k.createdAt,
      notes: k.notes,
    ));
  }
  return result;
}

// KOTs for a session — server data merged with any offline (pending-sync)
// orders. Offline, the server call fails and only local orders are shown.
final sessionKotsProvider =
    FutureProvider.family<List<KotWithItems>, String>((ref, sessionId) async {
  if (sessionId.isEmpty) return [];
  var serverKots = <KotWithItems>[];
  // Did the server actually answer? Only then is its list authoritative enough
  // to prune local copies against.
  var serverAnswered = false;
  // Offline: skip the server call entirely (no 5s stall) and show the orders
  // stored locally on this device.
  if (ref.read(connectivityProvider)) {
    try {
      final response =
          await ApiClient.instance.get(ApiConstants.kotsBySession(sessionId));
      final rows = response.data as List<dynamic>;
      serverKots = rows
          .map((r) => _kotWithItemsFromJson(r as Map<String, dynamic>))
          .toList();
      serverAnswered = true;
    } on NetworkException {
      // Dropped mid-request — fall through to locally-stored orders only.
    }
  }
  // Orders/lines cancelled here but whose cancel hasn't reached the server yet.
  // This is the half that used to be missing: the device recorded what was
  // ADDED offline but never what was DELETED, so a refetch that beat the
  // outbox drain brought a cancelled order straight back onto the bill — and
  // if the queued cancel ever failed, it came back permanently. A tombstone
  // outranks the server until SyncEngine confirms the cancel landed.
  serverKots = await applyCancelTombstones(serverKots);

  final offline = await _offlineKotsFor(sessionId);
  if (offline.isEmpty) return serverKots;
  final serverIds = serverKots.map((k) => k.id).toSet();

  // The server now has this order, so the local copy has done its job — drop
  // it. Covers our own synced orders AND ones mirrored in over the LAN from
  // another device, which would otherwise sit in Isar for good (they carry no
  // outbox op of their own, so the sync engine never cleans them up).
  if (serverAnswered) {
    for (final k in offline) {
      if (serverIds.contains(k.id)) {
        unawaited(OfflineStore.instance.deleteOfflineKot(k.id));
      }
    }
  }

  return [...serverKots, ...offline.where((k) => !serverIds.contains(k.id))];
});

/// What a session's kitchen orders allow the waiter to do next.
///
/// The kitchen walks each KOT `pending -> preparing -> ready -> served`, and
/// only `served` means the guest actually has the food. Cancelled KOTs are
/// ignored: they were voided, so nobody is waiting on them and a table left
/// with nothing but cancellations is empty again.
///
/// While the KOTs are still loading, both gates stay shut. Withholding a
/// button for a moment costs nothing; offering "Close & Free Table" on a table
/// with food on the way loses the bill.
class SessionOrderState {
  final bool isLoading;

  /// KOTs that haven't been cancelled.
  final int liveCount;

  /// Of those, how many the kitchen hasn't marked served yet.
  final int unservedCount;

  const SessionOrderState({
    required this.isLoading,
    required this.liveCount,
    required this.unservedCount,
  });

  bool get hasOrders => liveCount > 0;

  /// The waiter may request the bill any time once at least one order has been
  /// sent — no need to wait for the kitchen to serve everything first.
  bool get canRequestBill => !isLoading && liveCount > 0;

  /// Nothing was ever ordered — the table can be released without a bill.
  bool get canFreeTable => !isLoading && liveCount == 0;

  /// Why the bill can't be requested, or null when it can. Lives here so the
  /// tables screen and the order screen say the same thing to the waiter.
  String? get billBlockedReason {
    if (canRequestBill) return null;
    if (isLoading) return 'Checking orders…';
    return 'Nothing ordered yet — use Close & Free Table';
  }

  /// Why the table can't be freed, or null when it can.
  String? get freeBlockedReason {
    if (canFreeTable) return null;
    if (isLoading) return 'Checking orders…';
    return 'Table has orders — use Request Bill to free it';
  }
}

/// Live view of [sessionKotsProvider]. The realtime layer invalidates that
/// provider on every `kot:new` and `kot:status_changed`, so a waiter watching
/// this sees "Request Bill" unlock the instant the first order is sent — the
/// bill no longer waits on the kitchen serving everything.
final sessionOrderStateProvider =
    Provider.family<SessionOrderState, String>((ref, sessionId) {
  final kots = ref.watch(sessionKotsProvider(sessionId)).valueOrNull;
  if (kots == null) {
    return const SessionOrderState(isLoading: true, liveCount: 0, unservedCount: 0);
  }
  final live = kots.where((k) => k.status != 'cancelled');
  return SessionOrderState(
    isLoading: false,
    liveCount: live.length,
    unservedCount: live.where((k) => k.status != 'served').length,
  );
});

// Cart state for current order
class CartItem {
  final MenuItem item;
  int quantity;
  String? notes;

  CartItem({required this.item, this.quantity = 1, this.notes});

  double get total => item.price * quantity;
}

class OrderNotifier extends StateNotifier<List<CartItem>> {
  final Ref _ref;
  OrderNotifier(this._ref) : super([]);

  void addItem(MenuItem item) {
    final existing = state.where((c) => c.item.id == item.id).toList();
    if (existing.isNotEmpty) {
      state = state.map((c) => c.item.id == item.id
          ? (CartItem(item: c.item, quantity: c.quantity + 1, notes: c.notes))
          : c).toList();
    } else {
      state = [...state, CartItem(item: item)];
    }
  }

  void removeItem(String itemId) {
    state = state.where((c) => c.item.id != itemId).toList();
  }

  void increaseQty(String itemId) {
    state = state.map((c) => c.item.id == itemId
        ? CartItem(item: c.item, quantity: c.quantity + 1, notes: c.notes)
        : c).toList();
  }

  void decreaseQty(String itemId) {
    state = state.map((c) {
      if (c.item.id == itemId) {
        if (c.quantity <= 1) return null;
        return CartItem(item: c.item, quantity: c.quantity - 1, notes: c.notes);
      }
      return c;
    }).whereType<CartItem>().toList();
  }

  void clearCart() => state = [];

  double get subtotal => state.fold(0, (sum, c) => sum + c.total);

  Future<Kot?> sendKot({
    required String sessionId,
    required String tableId,
    required String branchId,
    String? notes,
  }) async {
    if (state.isEmpty) return null;
    final profile = _ref.read(authNotifierProvider).value;
    final waiterId = profile?.id;
    final waiterName = profile?.fullName;

    // One client-generated id, used for both the online call and (if it fails)
    // the offline copy — so a send that times out mid-flight and later replays
    // from the queue is idempotent on the server (never a duplicate ticket).
    final kotId = newOfflineId();
    final cart = List<CartItem>.from(state);
    final itemsPayload = cart
        .map((c) => <String, dynamic>{
              'menuItemId': c.item.id,
              'name': c.item.name,
              'quantity': c.quantity,
              if (c.notes != null) 'note': c.notes,
            })
        .toList();

    // If this table's session was opened offline and hasn't reached the server
    // yet, the backend doesn't know it — sending online would 404 ("session not
    // found"). Keep the KOT local so it uploads *after* the session (in order),
    // even though we're back online. Once the session syncs it's removed from
    // this cache, so later KOTs go straight to the server as normal.
    final offlineSession = await OfflineCache.instance.getOfflineSession(tableId);
    final sessionPendingOffline =
        offlineSession != null && offlineSession['id'] == sessionId;

    if (_ref.read(connectivityProvider) && !sessionPendingOffline) {
      try {
        final response = await ApiClient.instance.post(
          ApiConstants.kots,
          data: {
            'id': kotId,
            'sessionId': sessionId,
            if (waiterId != null) 'waiterId': waiterId,
            if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
            'items': itemsPayload,
          },
        );

        final json = response.data as Map<String, dynamic>;
        final rawItems = json['items'] as List? ?? [];
        final kot = Kot(
          id: json['id'] as String,
          branchId: json['branch_id'] as String,
          sessionId: json['session_id'] as String,
          tableId: json['table_id'] as String? ?? tableId,
          kotNumber: json['kot_number'] as String,
          status: json['status'] as String? ?? 'pending',
          waiterId: json['waiter_id'] as String? ?? waiterId,
          waiterName: json['waiter_name'] as String? ?? waiterName,
          items: rawItems
              .map((i) => KotItem.fromJson(i as Map<String, dynamic>))
              .toList(),
          createdAt: DateTime.parse(json['created_at'] as String),
          notes: notes,
        );

        _ref.invalidate(sessionKotsProvider(sessionId));
        _ref.invalidate(tableSessionProvider(tableId));
        _ref.invalidate(dashboardKotsProvider);
        _ref.invalidate(dashboardSessionsProvider);

        // Also mirror over the LAN. The cloud socket already tells every
        // ONLINE device about this order — this covers the lopsided case where
        // the sender has internet (a tablet on mobile data, say) but the till
        // does not. The till dedupes on the KOT id, so it costs nothing when
        // both routes deliver.
        _publishKot(
          kotId: kot.id,
          kotNumber: kot.kotNumber,
          sessionId: sessionId,
          tableId: tableId,
          branchId: kot.branchId,
          waiterId: waiterId,
          waiterName: waiterName,
          cart: cart,
          createdAt: kot.createdAt,
        );

        clearCart();
        return kot;
      } on NetworkException {
        // Lost the connection mid-send — fall through and capture it offline.
      }
    }

    return _sendKotOffline(
      kotId: kotId,
      sessionId: sessionId,
      tableId: tableId,
      branchId: branchId,
      notes: notes,
      waiterId: waiterId,
      waiterName: waiterName,
      cart: cart,
      itemsPayload: itemsPayload,
    );
  }

  /// Mirrors a KOT to the other devices over the LAN, rebuilding it in the
  /// same shape the offline path stores so the receiving side has one code
  /// path for both. Items carry their name and unit price, so a till can price
  /// the bill without its own menu cache being in step.
  void _publishKot({
    required String kotId,
    required String kotNumber,
    required String sessionId,
    required String tableId,
    required String branchId,
    required String? waiterId,
    required String? waiterName,
    required List<CartItem> cart,
    required DateTime createdAt,
  }) {
    final kot = OfflineKot()
      ..id = kotId
      ..branchId = branchId
      ..sessionId = sessionId
      ..tableId = tableId
      ..kotNumber = kotNumber
      ..status = 'pending'
      ..waiterId = waiterId
      ..waiterName = waiterName
      ..createdAt = createdAt
      ..isPendingSync = false
      ..syncedAt = createdAt;

    final items = cart
        .map((c) => OfflineKotItem()
          ..id = newOfflineId()
          ..kotId = kotId
          ..menuItemId = c.item.id
          ..menuItemName = c.item.name
          ..quantity = c.quantity
          ..unitPrice = c.item.price
          ..notes = c.notes
          ..createdAt = createdAt)
        .toList();

    LanSync.instance.publish(LanMirror.kotEnvelope(
      deviceId: _ref.read(lanConfigProvider).deviceId,
      kot: kot,
      items: items,
    ));
  }

  /// Persists a KOT locally and queues it for upload — used when the device is
  /// offline (or drops mid-send). The returned [Kot] carries a provisional
  /// number so the ticket prints and the UI updates immediately.
  Future<Kot> _sendKotOffline({
    required String kotId,
    required String sessionId,
    required String tableId,
    required String branchId,
    required String? notes,
    required String? waiterId,
    required String? waiterName,
    required List<CartItem> cart,
    required List<Map<String, dynamic>> itemsPayload,
  }) async {
    final now = DateTime.now();
    final kotNumber = provisionalNumber(kotId);

    final offlineKot = OfflineKot()
      ..id = kotId
      ..branchId = branchId
      ..sessionId = sessionId
      ..tableId = tableId
      ..kotNumber = kotNumber
      ..status = 'pending'
      ..waiterId = waiterId
      ..waiterName = waiterName
      ..createdAt = now
      ..isPendingSync = true
      ..syncedAt = now;

    final offlineItems = cart
        .map((c) => OfflineKotItem()
          ..id = newOfflineId()
          ..kotId = kotId
          ..menuItemId = c.item.id
          ..menuItemName = c.item.name
          ..quantity = c.quantity
          ..unitPrice = c.item.price
          ..notes = c.notes
          ..createdAt = now)
        .toList();

    await OfflineStore.instance.saveOfflineKot(offlineKot, offlineItems);

    // Replicate to the cashier's till over the LAN. Without this the order is
    // invisible at the counter until the internet returns — the KOT prints and
    // the food is cooked, but nobody can bill it. Fire-and-forget: a hub that
    // is down must never stop the waiter sending the order.
    LanSync.instance.publish(LanMirror.kotEnvelope(
      deviceId: _ref.read(lanConfigProvider).deviceId,
      kot: offlineKot,
      items: offlineItems,
    ));

    await OfflineStore.instance.enqueue(
      entityType: 'kot',
      operation: 'create',
      endpoint: ApiConstants.kots,
      method: 'POST',
      payload: {
        'id': kotId,
        'sessionId': sessionId,
        if (waiterId != null) 'waiterId': waiterId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'items': itemsPayload,
      },
    );
    await _ref.read(pendingSyncProvider.notifier).refresh();

    _ref.invalidate(sessionKotsProvider(sessionId));
    _ref.invalidate(tableSessionProvider(tableId));

    clearCart();

    return Kot(
      id: kotId,
      branchId: branchId,
      sessionId: sessionId,
      tableId: tableId,
      kotNumber: kotNumber,
      status: 'pending',
      waiterId: waiterId,
      waiterName: waiterName,
      // offlineItems is built from `cart` in order, so index-pair them to carry
      // each item's station type (kitchen vs bar) onto the returned KOT — the
      // waiter device needs it to print food-only to the kitchen while offline.
      items: List.generate(offlineItems.length, (i) {
        final oi = offlineItems[i];
        return KotItem(
          id: oi.id,
          kotId: kotId,
          menuItemId: oi.menuItemId,
          menuItemName: oi.menuItemName,
          quantity: oi.quantity,
          unitPrice: oi.unitPrice,
          notes: oi.notes,
          type: cart[i].item.type,
        );
      }),
      createdAt: now,
      notes: notes,
    );
  }
}

final orderNotifierProvider = StateNotifierProvider<OrderNotifier, List<CartItem>>(
  (ref) => OrderNotifier(ref),
);
