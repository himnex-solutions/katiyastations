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

// ════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════
class OnlineOrdersScreen extends ConsumerWidget {
  const OnlineOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(onlineDraftsProvider);
    final ordersAsync = ref.watch(onlineOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Online Orders',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(onlineOrdersProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('New Online Order',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => _openBuilder(context, ref, null),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (drafts.isNotEmpty) ...[
            _sectionLabel('Drafts (not sent yet)'),
            ...drafts.map((d) => _DraftCard(
                  draft: d,
                  onEdit: () => _openBuilder(context, ref, d),
                  onDelete: () => ref.read(onlineDraftsProvider.notifier).remove(d.id),
                  onSend: () => _sendAndPrint(context, ref, d),
                )),
            const SizedBox(height: 20),
          ],
          _sectionLabel('Sent — awaiting payment'),
          ordersAsync.when(
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
                              onReprint: () => _reprint(context, ref, o),
                              onSettle: () => _settle(context, ref, o),
                            ))
                        .toList(),
                  ),
          ),
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

  Future<void> _openBuilder(BuildContext context, WidgetRef ref, OnlineDraft? existing) async {
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
  Future<void> _sendAndPrint(BuildContext context, WidgetRef ref, OnlineDraft d) async {
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
      messenger.showSnackBar(const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Online order sent to kitchen/bar and printed.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(backgroundColor: AppColors.error, content: Text('Failed to send: $e')));
    }
  }

  // Reprint an already-sent order's tickets.
  Future<void> _reprint(BuildContext context, WidgetRef ref, Map<String, dynamic> order) async {
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

  Future<void> _settle(BuildContext context, WidgetRef ref, Map<String, dynamic> order) async {
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

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
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

            // ── categories ──
            catsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Text('Menu unavailable: $e',
                  style: GoogleFonts.outfit(color: AppColors.textSecondary)),
              data: (cats) {
                if (cats.isEmpty) {
                  return Text('No menu items yet.',
                      style: GoogleFonts.outfit(color: AppColors.textHint));
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
        children: items.map((m) {
          final qty = (cart[m.id]?['quantity'] as int?) ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name,
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text('NPR ${_money.format(m.price)}',
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.primary)),
                ]),
              ),
              if (qty > 0) ...[
                IconButton(
                    onPressed: () => onDec(m.id),
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error)),
                Text('$qty',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
              IconButton(
                  onPressed: () => onAdd(m),
                  icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary)),
            ]),
          );
        }).toList(),
      ),
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

  double get _total => (widget.order['total_amount'] as num?)?.toDouble() ?? 0;

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
      final total = _total > 0
          ? _total
          : items.fold(0.0,
              (s, i) => s + ((i['unit_price'] as num?)?.toDouble() ?? 0) * (i['quantity'] as int));
      if (mounted) {
        await printBillNow(context, ref, bill: {
          'session_number': widget.order['session_number'],
          'customer_name': widget.order['customer_name'],
          'sub_total': total,
          'total_amount': total,
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
    final total = _total;
    setState(() => _busy = true);
    try {
      final res = await ApiClient.instance.post(
        ApiConstants.generateBill(widget.order['id'] as String),
        data: {
          'paymentMethod': _method,
          'amountPaid': total,
          if (widget.order['customer_name'] != null) 'customerName': widget.order['customer_name'],
          if (widget.order['customer_phone'] != null) 'customerPhone': widget.order['customer_phone'],
        },
      );
      final bill = res.data as Map<String, dynamic>;
      // Print the invoice on the receipt printer (it reads the branch itself).
      final items = await _fetchItems();
      if (mounted) {
        await printBillNow(context, ref, bill: bill, items: items);
      }
      ref.invalidate(onlineOrdersProvider);
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

  @override
  Widget build(BuildContext context) {
    final total = _total;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Settle Online Order',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('${widget.order['customer_name'] ?? ''}  ·  NPR ${_money.format(total)}',
              style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
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
                    _busy ? 'Working…' : 'Settle & Print Invoice · NPR ${_money.format(total)}',
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
