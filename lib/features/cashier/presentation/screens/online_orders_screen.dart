// ============================================================
// KATIYA STATION RMS — ONLINE / CALL-IN ORDERS
// The cashier takes a phone order: captures the customer, builds the order
// from the menu, saves it as a draft, then sends it to the kitchen/bar
// (printed "ONLINE ORDER") and settles it now or later. Online sales flow
// through the same session → KOT → bill → payment as dine-in.
// ============================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/offline/connectivity_provider.dart';
import '../../../../core/offline/offline_ids.dart';
import '../../../../core/printing/print_actions.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../branches/presentation/providers/branch_provider.dart';
import '../../../menu/domain/entities/menu_entities.dart';
import '../../../orders/domain/entities/order_entities.dart';
import '../../../orders/presentation/providers/order_provider.dart';

final _money = NumberFormat('#,##0.00');

// ── A locally-saved online order draft (before it's sent) ────
class OnlineDraft {
  final String id;
  final String customerName;
  final String? customerPhone;
  final String? customerAddress;
  final List<Map<String, dynamic>> items; // {menuItemId, name, quantity, price}

  OnlineDraft({
    required this.id,
    required this.customerName,
    this.customerPhone,
    this.customerAddress,
    required this.items,
  });

  double get total =>
      items.fold(0.0, (s, i) => s + ((i['price'] as num?)?.toDouble() ?? 0) * (i['quantity'] as int));

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerAddress': customerAddress,
        'items': items,
      };

  factory OnlineDraft.fromJson(Map<String, dynamic> j) => OnlineDraft(
        id: j['id'] as String,
        customerName: j['customerName'] as String,
        customerPhone: j['customerPhone'] as String?,
        customerAddress: j['customerAddress'] as String?,
        items: List<Map<String, dynamic>>.from(
            (j['items'] as List).map((e) => Map<String, dynamic>.from(e as Map))),
      );
}

// ── Drafts persisted on this device (SharedPreferences) ─────
class OnlineDraftsNotifier extends StateNotifier<List<OnlineDraft>> {
  OnlineDraftsNotifier() : super([]) {
    _load();
  }
  static const _key = 'online_order_drafts';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => OnlineDraft.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      state = list;
    } catch (_) {/* ignore corrupt cache */}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.map((d) => d.toJson()).toList()));
  }

  Future<void> upsert(OnlineDraft draft) async {
    state = [draft, ...state.where((d) => d.id != draft.id)];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((d) => d.id != id).toList();
    await _persist();
  }
}

final onlineDraftsProvider =
    StateNotifierProvider<OnlineDraftsNotifier, List<OnlineDraft>>((ref) => OnlineDraftsNotifier());

/// Sent, not-yet-settled online orders (from the server).
final onlineOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  if (!ref.read(connectivityProvider)) return const [];
  final res = await ApiClient.instance.get(
    ApiConstants.onlineOrders,
    queryParameters: {'branchId': profile!.branchId!},
  );
  return List<Map<String, dynamic>>.from(res.data as List? ?? []);
});

/// Settled online orders — the cashier's history, server-backed so it's shared
/// across every till. Each entry carries its KOT items (with station `type`) so
/// the cashier can see what went to the kitchen vs the bar.
final onlineOrderHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return const [];
  if (!ref.read(connectivityProvider)) return const [];
  final res = await ApiClient.instance.get(
    ApiConstants.onlineOrderHistory,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '40'},
  );
  return List<Map<String, dynamic>>.from(res.data as List? ?? []);
});

// ════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════
class OnlineOrdersScreen extends ConsumerStatefulWidget {
  const OnlineOrdersScreen({super.key});

  @override
  ConsumerState<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends ConsumerState<OnlineOrdersScreen> {
  int _tab = 0; // 0 = active (drafts + unpaid), 1 = history (settled)

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(onlineDraftsProvider);
    final ordersAsync = ref.watch(onlineOrdersProvider);
    final historyAsync = ref.watch(onlineOrderHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Online Orders',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(onlineOrdersProvider);
              ref.invalidate(onlineOrderHistoryProvider);
            },
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('New Online Order',
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
              onPressed: () => _openBuilder(context, null),
            )
          : null,
      body: Column(
        children: [
          _tabBar(ordersAsync.valueOrNull?.length ?? 0),
          Expanded(
            child: _tab == 0
                ? _activeList(context, drafts, ordersAsync)
                : _historyList(context, historyAsync),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(int unpaidCount) {
    Widget seg(int i, IconData icon, String label) {
      final sel = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: sel ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : AppColors.textSecondary)),
            ]),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        seg(0, Icons.receipt_long_rounded, 'Active'),
        seg(1, Icons.history_rounded, 'History'),
      ]),
    );
  }

  Widget _activeList(
    BuildContext context,
    List<OnlineDraft> drafts,
    AsyncValue<List<Map<String, dynamic>>> ordersAsync,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (drafts.isNotEmpty) ...[
          _sectionLabel('Drafts (not sent yet)'),
          ...drafts.map((d) => _DraftCard(
                draft: d,
                onEdit: () => _openBuilder(context, d),
                onDelete: () => ref.read(onlineDraftsProvider.notifier).remove(d.id),
                onSend: () => _sendAndPrint(context, d),
              )),
          const SizedBox(height: 20),
        ],
        _sectionLabel('Sent — awaiting payment'),
        ordersAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
          error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load: $e',
                  style: GoogleFonts.outfit(color: AppColors.textSecondary))),
          data: (orders) => orders.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No unpaid online orders.',
                      style: GoogleFonts.outfit(color: AppColors.textHint)))
              : Column(
                  children: orders
                      .map((o) => _OrderCard(
                            order: o,
                            onReprint: () => _reprint(context, o),
                            onSettle: () => _settle(context, o),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _historyList(
    BuildContext context,
    AsyncValue<List<Map<String, dynamic>>> historyAsync,
  ) {
    return historyAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Could not load history: $e',
              style: GoogleFonts.outfit(color: AppColors.textSecondary))),
      data: (orders) => orders.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.history_toggle_off_rounded, size: 48, color: AppColors.textHint),
              const SizedBox(height: 10),
              Text('No settled online orders yet.',
                  style: GoogleFonts.outfit(color: AppColors.textHint)),
            ]))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _sectionLabel('Settled — order history'),
                ...orders.map((o) => _HistoryCard(
                      order: o,
                      onReprint: () => _reprint(context, o),
                    )),
              ],
            ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: GoogleFonts.outfit(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );

  Future<void> _openBuilder(BuildContext context, OnlineDraft? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _OnlineOrderBuilder(existing: existing),
    );
  }

  // Create the online session + KOT, print the tickets, drop the draft.
  Future<void> _sendAndPrint(BuildContext context, OnlineDraft d) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!ref.read(connectivityProvider)) {
      messenger.showSnackBar(const SnackBar(
          backgroundColor: AppColors.warning,
          content: Text('Sending an online order needs an internet connection.')));
      return;
    }
    if (d.items.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          backgroundColor: AppColors.warning, content: Text('Add at least one item first.')));
      return;
    }
    try {
      final sessionRes = await ApiClient.instance.post(ApiConstants.onlineOrders, data: {
        'id': newOfflineId(),
        'customerName': d.customerName,
        if (d.customerPhone != null && d.customerPhone!.isNotEmpty) 'customerPhone': d.customerPhone,
        if (d.customerAddress != null && d.customerAddress!.isNotEmpty)
          'customerAddress': d.customerAddress,
      });
      final sessionId = (sessionRes.data as Map)['id'] as String;

      final kotRes = await ApiClient.instance.post(ApiConstants.kots, data: {
        'sessionId': sessionId,
        'items': d.items
            .map((i) =>
                {'menuItemId': i['menuItemId'], 'name': i['name'], 'quantity': i['quantity']})
            .toList(),
      });
      final kot = Kot.fromJson(kotRes.data as Map<String, dynamic>);

      await printOnlineOrderTickets(ref,
          kot: kot, customerName: d.customerName, customerPhone: d.customerPhone);

      await ref.read(onlineDraftsProvider.notifier).remove(d.id);
      ref.invalidate(onlineOrdersProvider);
      ref.invalidate(onlineOrderHistoryProvider);
      messenger.showSnackBar(const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Online order sent to kitchen/bar and printed.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(backgroundColor: AppColors.error, content: Text('Failed to send: $e')));
    }
  }

  // Reprint an already-sent order's tickets.
  Future<void> _reprint(BuildContext context, Map<String, dynamic> order) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sessionId = order['id'] as String;
      final kotsRes = await ApiClient.instance.get(ApiConstants.kotsBySession(sessionId));
      final kots = (kotsRes.data as List).cast<Map<String, dynamic>>();
      final name = (order['customer_name'] as String?) ?? 'Online';
      final phone = order['customer_phone'] as String?;
      for (final k in kots) {
        if ((k['status'] as String?) == 'cancelled') continue;
        await printOnlineOrderTickets(ref,
            kot: Kot.fromJson(k), customerName: name, customerPhone: phone);
      }
      messenger.showSnackBar(const SnackBar(
          backgroundColor: AppColors.success, content: Text('Reprinted.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(backgroundColor: AppColors.error, content: Text('Reprint failed: $e')));
    }
  }

  Future<void> _settle(BuildContext context, Map<String, dynamic> order) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SettleOnlineSheet(order: order),
    );
  }
}

// ── History card: a settled online order with its kitchen/bar items ─────────
class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onReprint;
  const _HistoryCard({required this.order, required this.onReprint});

  @override
  Widget build(BuildContext context) {
    final name = (order['customer_name'] as String?) ?? 'Online customer';
    final phone = order['customer_phone'] as String?;
    final bill = order['bill'] as Map<String, dynamic>?;
    final invoiceNo = bill?['invoice_number'] as String?;
    final total = (bill?['total_amount'] as num?)?.toDouble() ??
        (order['total_amount'] as num?)?.toDouble() ??
        0;
    final closedRaw = order['closed_at'] ?? order['created_at'];
    final when = DateTime.tryParse(closedRaw?.toString() ?? '');

    // Flatten every KOT's items and split by station.
    final kitchen = <String>[];
    final bar = <String>[];
    for (final k in (order['kots'] as List? ?? const [])) {
      if (k is! Map) continue;
      for (final i in (k['items'] as List? ?? const [])) {
        if (i is! Map) continue;
        final t = (i['type'] as String?) ?? 'food';
        final label = '${i['name'] ?? i['menu_item_name'] ?? 'Item'} x${i['quantity'] ?? 1}';
        (t == 'bar' || t == 'drink' ? bar : kitchen).add(label);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(
                [
                  if (phone != null && phone.isNotEmpty) phone,
                  if (invoiceNo != null && invoiceNo.isNotEmpty) invoiceNo,
                  if (when != null) DateFormat('dd MMM, hh:mm a').format(when),
                ].join('  ·  '),
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
              ),
            ]),
          ),
          Text('NPR ${_money.format(total)}',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 10),
        if (kitchen.isNotEmpty) _stationRow('KITCHEN', kitchen, AppColors.primary),
        if (bar.isNotEmpty) ...[
          if (kitchen.isNotEmpty) const SizedBox(height: 6),
          _stationRow('BAR', bar, const Color(0xFF8E44AD)),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onReprint,
            icon: const Icon(Icons.print_rounded, size: 15),
            label: const Text('Reprint tickets'),
          ),
        ),
      ]),
    );
  }

  Widget _stationRow(String station, List<String> items, Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        margin: const EdgeInsets.only(top: 1),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(station,
            style: GoogleFonts.outfit(
                fontSize: 9.5, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(items.join(', '),
            style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textSecondary)),
      ),
    ]);
  }
}

// ── cards ───────────────────────────────────────────────────
class _DraftCard extends StatelessWidget {
  final OnlineDraft draft;
  final VoidCallback onEdit, onDelete, onSend;
  const _DraftCard(
      {required this.draft, required this.onEdit, required this.onDelete, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.edit_note_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(draft.customerName,
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          Text('NPR ${_money.format(draft.total)}',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
        if (draft.customerPhone != null && draft.customerPhone!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${draft.customerPhone}  ·  ${draft.items.length} item(s)',
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
              onPressed: onEdit, icon: const Icon(Icons.edit_rounded, size: 15), label: const Text('Edit')),
          const SizedBox(width: 8),
          TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.error),
              label: const Text('Delete', style: TextStyle(color: AppColors.error))),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: onSend,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text('Send & Print'),
          ),
        ]),
      ]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onReprint, onSettle;
  const _OrderCard({required this.order, required this.onReprint, required this.onSettle});

  @override
  Widget build(BuildContext context) {
    final name = (order['customer_name'] as String?) ?? 'Online customer';
    final phone = order['customer_phone'] as String?;
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final no = (order['session_number'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.delivery_dining_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style:
                      GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text([if (phone != null && phone.isNotEmpty) phone, no].join('  ·  '),
                  style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          Text('NPR ${_money.format(total)}',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
              onPressed: onReprint,
              icon: const Icon(Icons.print_rounded, size: 15),
              label: const Text('Reprint')),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: onSettle,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success, foregroundColor: Colors.white),
            icon: const Icon(Icons.point_of_sale_rounded, size: 16),
            label: const Text('Settle'),
          ),
        ]),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  ORDER BUILDER (customer + menu + cart → save draft)
// ════════════════════════════════════════════════════════════
class _OnlineOrderBuilder extends ConsumerStatefulWidget {
  final OnlineDraft? existing;
  const _OnlineOrderBuilder({this.existing});
  @override
  ConsumerState<_OnlineOrderBuilder> createState() => _OnlineOrderBuilderState();
}

class _OnlineOrderBuilderState extends ConsumerState<_OnlineOrderBuilder> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.customerName ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.customerPhone ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.existing?.customerAddress ?? '');

  // menuItemId -> {menuItemId, name, quantity, price}
  late final Map<String, Map<String, dynamic>> _cart = {
    for (final i in widget.existing?.items ?? const []) i['menuItemId'] as String: Map.from(i),
  };
  String? _catId;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _search.dispose();
    super.dispose();
  }

  double get _total =>
      _cart.values.fold(0.0, (s, i) => s + ((i['price'] as num?)?.toDouble() ?? 0) * (i['quantity'] as int));

  void _add(MenuItem m) {
    setState(() {
      final e = _cart[m.id];
      if (e != null) {
        e['quantity'] = (e['quantity'] as int) + 1;
      } else {
        _cart[m.id] = {'menuItemId': m.id, 'name': m.name, 'quantity': 1, 'price': m.price};
      }
    });
  }

  void _dec(String id) {
    setState(() {
      final e = _cart[id];
      if (e == null) return;
      final q = (e['quantity'] as int) - 1;
      if (q <= 0) {
        _cart.remove(id);
      } else {
        e['quantity'] = q;
      }
    });
  }

  Future<void> _saveDraft() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(
          backgroundColor: AppColors.warning, content: Text('Customer name is required.')));
      return;
    }
    if (_cart.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          backgroundColor: AppColors.warning, content: Text('Add at least one item.')));
      return;
    }
    final draft = OnlineDraft(
      id: widget.existing?.id ?? newOfflineId(),
      customerName: _name.text.trim(),
      customerPhone: _phone.text.trim(),
      customerAddress: _address.text.trim(),
      items: _cart.values.map((e) => Map<String, dynamic>.from(e)).toList(),
    );
    await ref.read(onlineDraftsProvider.notifier).upsert(draft);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).value;
    final branchId = profile?.branchId;
    final catsAsync = branchId != null
        ? ref.watch(menuCategoriesProvider(branchId))
        : const AsyncValue.data(<MenuCategory>[]);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraftScaffold(
        title: widget.existing == null ? 'New Online Order' : 'Edit Online Order',
        total: _total,
        cartCount: _cart.length,
        onSave: _saveDraft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── customer ──
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Customer Name *', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Delivery Address', isDense: true),
            ),
            const SizedBox(height: 16),

            // ── menu search (name · category · price) ──
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search menu by name, category or price…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),

            // ── search results OR category browser ──
            catsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Text('Menu unavailable: $e',
                  style: GoogleFonts.outfit(color: AppColors.textSecondary)),
              data: (cats) {
                if (cats.isEmpty) {
                  return Text('No menu items yet.',
                      style: GoogleFonts.outfit(color: AppColors.textHint));
                }
                // While searching, ignore categories and show a flat filtered
                // list across the whole branch menu.
                if (_query.isNotEmpty && branchId != null) {
                  final catNameById = {for (final c in cats) c.id: c.name};
                  return _SearchResults(
                    branchId: branchId,
                    query: _query,
                    catNameById: catNameById,
                    cart: _cart,
                    onAdd: _add,
                    onDec: _dec,
                  );
                }
                _catId ??= cats.first.id;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: cats
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(c.name),
                                  selected: _catId == c.id,
                                  onSelected: (_) => setState(() => _catId = c.id),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MenuGrid(
                    categoryId: _catId!,
                    cart: _cart,
                    onAdd: _add,
                    onDec: _dec,
                  ),
                ]);
              },
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

// Simple scaffold with a sticky Save Draft footer.
class DraftScaffold extends StatelessWidget {
  final String title;
  final double total;
  final int cartCount;
  final VoidCallback onSave;
  final Widget child;
  const DraftScaffold({
    super.key,
    required this.title,
    required this.total,
    required this.cartCount,
    required this.onSave,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(children: [
            Expanded(
              child: Text(title,
                  style: GoogleFonts.outfit(
                      fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            IconButton(
                onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Expanded(child: child),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$cartCount item(s)',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                Text('NPR ${_money.format(total)}',
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ]),
            ),
            ElevatedButton.icon(
              onPressed: onSave,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Draft'),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MenuGrid extends ConsumerWidget {
  final String categoryId;
  final Map<String, Map<String, dynamic>> cart;
  final void Function(MenuItem) onAdd;
  final void Function(String) onDec;
  const _MenuGrid(
      {required this.categoryId, required this.cart, required this.onAdd, required this.onDec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(menuItemsProvider(categoryId));
    return itemsAsync.when(
      loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Text('Items unavailable: $e',
          style: GoogleFonts.outfit(color: AppColors.textSecondary)),
      data: (items) => Column(
        children: items
            .map((m) => _MenuItemTile(
                  item: m,
                  qty: (cart[m.id]?['quantity'] as int?) ?? 0,
                  onAdd: () => onAdd(m),
                  onDec: () => onDec(m.id),
                ))
            .toList(),
      ),
    );
  }
}

/// Flat, filtered results across the WHOLE branch menu — matches the query
/// against item name, its category name, and its price. Powers the search bar.
class _SearchResults extends ConsumerWidget {
  final String branchId;
  final String query;
  final Map<String, String> catNameById;
  final Map<String, Map<String, dynamic>> cart;
  final void Function(MenuItem) onAdd;
  final void Function(String) onDec;
  const _SearchResults({
    required this.branchId,
    required this.query,
    required this.catNameById,
    required this.cart,
    required this.onAdd,
    required this.onDec,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(allMenuItemsProvider(branchId));
    return itemsAsync.when(
      loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Text('Search unavailable: $e',
          style: GoogleFonts.outfit(color: AppColors.textSecondary)),
      data: (items) {
        final q = query.toLowerCase();
        final matches = items.where((m) {
          final cat = (catNameById[m.categoryId] ?? '').toLowerCase();
          return m.name.toLowerCase().contains(q) ||
              cat.contains(q) ||
              m.price.toStringAsFixed(0).contains(q) ||
              _money.format(m.price).contains(q);
        }).toList();

        if (matches.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No items match “$query”.',
                  style: GoogleFonts.outfit(color: AppColors.textHint)),
            ),
          );
        }
        return Column(
          children: matches
              .map((m) => _MenuItemTile(
                    item: m,
                    qty: (cart[m.id]?['quantity'] as int?) ?? 0,
                    subtitle: catNameById[m.categoryId],
                    onAdd: () => onAdd(m),
                    onDec: () => onDec(m.id),
                  ))
              .toList(),
        );
      },
    );
  }
}

/// One selectable menu row shared by the category grid and the search results.
class _MenuItemTile extends StatelessWidget {
  final MenuItem item;
  final int qty;
  final String? subtitle;
  final VoidCallback onAdd;
  final VoidCallback onDec;
  const _MenuItemTile({
    required this.item,
    required this.qty,
    required this.onAdd,
    required this.onDec,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: qty > 0 ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name,
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Row(children: [
              Text('NPR ${_money.format(item.price)}',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppColors.primary)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                Text('  ·  ',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textHint)),
                Flexible(
                  child: Text(subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textHint)),
                ),
              ],
            ]),
          ]),
        ),
        if (qty > 0) ...[
          IconButton(
              onPressed: onDec,
              icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error)),
          Text('$qty', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
        IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  SETTLE (payment) for a sent online order
// ════════════════════════════════════════════════════════════
class _SettleOnlineSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  const _SettleOnlineSheet({required this.order});
  @override
  ConsumerState<_SettleOnlineSheet> createState() => _SettleOnlineSheetState();
}

// The payment methods the backend accepts (see GenerateBillDto). "online" is
// NOT one of them — sending it was what triggered the validation error. These
// mirror the main cashier screen.
const _onlinePayMethods = <(String, String)>[
  ('cash', 'Cash'),
  ('esewa', 'eSewa'),
  ('khalti', 'Khalti'),
  ('fonepay', 'FonePay'),
  ('credit', 'Credit'),
];

class _SettleOnlineSheetState extends ConsumerState<_SettleOnlineSheet> {
  String _method = 'cash';
  bool _busy = false;
  final _discountCtrl = TextEditingController(text: '0');
  double _discount = 0;
  bool _applyServiceCharge = false;

  @override
  void dispose() {
    _discountCtrl.dispose();
    super.dispose();
  }

  double get _subtotal => (widget.order['total_amount'] as num?)?.toDouble() ?? 0;

  double get _serviceRate =>
      ((ref.read(currentBranchProvider).valueOrNull?['service_charge_rate']) as num?)?.toDouble() ?? 10;

  double get _serviceCharge => _applyServiceCharge ? _subtotal * _serviceRate / 100 : 0;

  /// Payable after service charge + discount (never below zero).
  double get _net {
    final n = _subtotal + _serviceCharge - _discount;
    return n < 0 ? 0 : n;
  }

  String? get _phone {
    final p = widget.order['customer_phone'] as String?;
    return (p != null && p.isNotEmpty) ? p : null;
  }

  /// The order's line items, flattened for the bill/receipt payload.
  Future<List<Map<String, dynamic>>> _fetchItems() async {
    final itemsRes = await ApiClient.instance
        .get(ApiConstants.kotsBySession(widget.order['id'] as String));
    return _flattenItems(itemsRes.data as List);
  }

  /// PRINT (before payment): a customer copy only. No invoice number is
  /// generated and nothing is recorded — printBill renders it as
  /// "BILL (not a tax invoice)". Use it to hand the guest a total to check.
  Future<void> _printCustomerCopy() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final items = await _fetchItems();
      if (mounted) {
        await printBillNow(context, ref, bill: {
          'session_number': widget.order['session_number'],
          'customer_name': widget.order['customer_name'],
          if (_phone != null) 'customer_phone': _phone,
          'sub_total': _subtotal,
          'discount': _discount,
          'service_charge': _serviceCharge,
          'total_amount': _net,
        }, items: items);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(backgroundColor: AppColors.error, content: Text('Print failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// SETTLE & PRINT (after payment received): generates the real bill +
  /// invoice number, records the payment, then prints the tax invoice.
  Future<void> _settle() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final res = await ApiClient.instance.post(
        ApiConstants.generateBill(widget.order['id'] as String),
        data: {
          'paymentMethod': _method,
          // No amountPaid: this is always a full settle, so let the server's
          // own total be recorded as paid (avoids a client-total rounding
          // shortfall being mis-flagged "partial paid"). discount +
          // applyServiceCharge are sent so the server computes the same total.
          'discount': _discount,
          'applyServiceCharge': _applyServiceCharge,
          if (widget.order['customer_name'] != null) 'customerName': widget.order['customer_name'],
          if (_phone != null) 'customerPhone': _phone,
        },
      );
      final bill = res.data as Map<String, dynamic>;
      // Print the invoice on the receipt printer (it reads the branch itself).
      // Carry the phone through in case the bill record didn't echo it back.
      final items = await _fetchItems();
      if (mounted) {
        await printBillNow(context, ref,
            bill: {if (_phone != null) 'customer_phone': _phone, ...bill}, items: items);
      }
      ref.invalidate(onlineOrdersProvider);
      ref.invalidate(onlineOrderHistoryProvider);
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(
            backgroundColor: AppColors.success, content: Text('Online order settled.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(
            SnackBar(backgroundColor: AppColors.error, content: Text('Settle failed: $e')));
      }
    }
  }

  List<Map<String, dynamic>> _flattenItems(List kots) {
    final out = <Map<String, dynamic>>[];
    for (final k in kots) {
      if (k is! Map) continue;
      if ((k['status'] as String?) == 'cancelled') continue;
      for (final i in (k['items'] as List? ?? [])) {
        if (i is! Map) continue;
        if ((i['status'] as String?) == 'cancelled') continue;
        out.add({
          'menu_item_name': i['name'] ?? i['menu_item_name'],
          'quantity': i['quantity'],
          'unit_price': i['unit_price'],
        });
      }
    }
    return out;
  }

  Widget _line(String label, double amount, {bool bold = false, Color? color}) {
    final style = GoogleFonts.outfit(
      fontSize: bold ? 15 : 12.5,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: color ?? (bold ? AppColors.textPrimary : AppColors.textSecondary),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: style),
        Text('${amount < 0 ? '-' : ''}NPR ${_money.format(amount.abs())}', style: style),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the branch so the service-charge rate/amount appears once loaded.
    ref.watch(currentBranchProvider);
    final net = _net;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Settle Online Order',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text([
            if ((widget.order['customer_name'] as String?)?.isNotEmpty ?? false)
              widget.order['customer_name'],
            if (_phone != null) _phone,
          ].whereType<String>().join('  ·  '),
              style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 18),

          // ── Adjustments: service charge + discount ──
          Row(children: [
            Expanded(
              child: Text('Service Charge (${_serviceRate.toStringAsFixed(0)}%)',
                  style: GoogleFonts.outfit(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            Text(_applyServiceCharge ? '+ NPR ${_money.format(_serviceCharge)}' : 'Off',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: _applyServiceCharge ? AppColors.warning : AppColors.textHint)),
            Switch(
              value: _applyServiceCharge,
              // `activeColor` (not `activeThumbColor`) — the latter only exists
              // from Flutter ~3.34, and the Vercel web build is pinned to 3.32.0.
              // ignore: deprecated_member_use
              activeColor: AppColors.primary,
              onChanged: _busy ? null : (v) => setState(() => _applyServiceCharge = v),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text('Discount (NPR)',
                  style: GoogleFonts.outfit(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _discountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                enabled: !_busy,
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.success),
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: 'NPR ',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() => _discount = double.tryParse(v) ?? 0),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // ── Live total breakdown ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              _line('Subtotal', _subtotal),
              if (_serviceCharge > 0) _line('Service charge', _serviceCharge),
              if (_discount > 0) _line('Discount', -_discount, color: AppColors.success),
              const Divider(height: 14),
              _line('Payable', net, bold: true),
            ]),
          ),
          const SizedBox(height: 18),

          Text('PAYMENT METHOD',
              style: GoogleFonts.outfit(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _onlinePayMethods
                .map((m) => ChoiceChip(
                      label: Text(m.$2),
                      selected: _method == m.$1,
                      onSelected: _busy ? null : (_) => setState(() => _method = m.$1),
                    ))
                .toList(),
          ),
          const SizedBox(height: 22),
          // ── Print a customer copy BEFORE taking payment (not an invoice) ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _busy ? null : _printCustomerCopy,
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.print_rounded, size: 18),
                SizedBox(width: 8),
                Flexible(
                    child: Text('Print Bill — Customer Copy', overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // ── Settle AFTER payment is received: invoice + payment recorded ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _settle,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (_busy)
                  const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else
                  const Icon(Icons.check_circle_rounded, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _busy ? 'Working…' : 'Settle & Print Invoice · NPR ${_money.format(net)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text('“Print Bill” gives the customer a copy only. “Settle” records the payment and generates the tax invoice.',
              style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint)),
        ]),
      ),
    );
  }
}
