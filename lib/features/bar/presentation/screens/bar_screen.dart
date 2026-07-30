// ignore_for_file: deprecated_member_use  // DropdownButtonFormField.value kept for Flutter 3.32.0 web build
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../inventory/domain/entities/inventory_entities.dart';
import '../../../../core/widgets/notification_bell.dart';

final barStockProvider = FutureProvider<List<BarStockItem>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.barStock,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = data['data'] as List<dynamic>;
  return rows.map((r) => BarStockItem.fromJson(r as Map<String, dynamic>)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

class BarScreen extends ConsumerStatefulWidget {
  const BarScreen({super.key});

  @override
  ConsumerState<BarScreen> createState() => _BarScreenState();
}

class _BarScreenState extends ConsumerState<BarScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(barStockProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.wine_bar,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Bar Management',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Stock'),
            onPressed: () => showBarStockDialog(context, ref),
          ),
          const NotificationBell(),
        ],
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allItems) {
          // Filter by the search query (name or category).
          final q = _query.toLowerCase();
          final items = q.isEmpty
              ? allItems
              : allItems
                  .where((i) =>
                      i.name.toLowerCase().contains(q) ||
                      i.category.toLowerCase().contains(q))
                  .toList();

          // Group by the categories that ACTUALLY exist in the data (falling
          // back to "other" for a blank one) — a fixed spirits/beer/wine/other
          // set silently hid any item with a different or differently-cased
          // category, so it never showed even though the count included it.
          final grouped = <String, List<BarStockItem>>{};
          for (final i in items) {
            final key = i.category.trim().isEmpty ? 'other' : i.category.trim();
            grouped.putIfAbsent(key, () => []).add(i);
          }
          final categories = grouped.keys.toList()..sort();

          return ResponsiveContent(child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary (always reflects the full inventory, not the filter).
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    const Icon(Icons.local_bar_rounded, color: AppColors.onPrimary, size: 32),
                    const SizedBox(width: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Bar Inventory', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onPrimary)),
                      Text('${allItems.length} items tracked', style: GoogleFonts.outfit(fontSize: 13, color: Colors.white.withValues(alpha: 0.75))),
                    ]),
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Total Bottles', style: GoogleFonts.outfit(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
                      Text(allItems.fold<double>(0, (s, i) => s + i.currentBottles).toStringAsFixed(1),
                          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onPrimary)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),
                // Search
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search stock by name or category…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _query = '';
                            }),
                          ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(children: [
                        const Icon(Icons.search_off_rounded, size: 42, color: AppColors.textHint),
                        const SizedBox(height: 10),
                        Text(
                          _query.isEmpty ? 'No bar stock yet.' : 'No stock matches “$_query”.',
                          style: GoogleFonts.outfit(color: AppColors.textHint),
                        ),
                      ]),
                    ),
                  ),
                // By category
                ...categories.map((cat) {
                  final catItems = grouped[cat]!;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(cat.toUpperCase(),
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 1.5)),
                    ),
                    ...catItems.map((item) => _BarStockCard(item: item, ref: ref)
                        .animate().fadeIn(duration: 300.ms)),
                    const SizedBox(height: 16),
                  ]);
                }),
              ],
            ),
          ));
        },
      ),
    );
  }

}

/// Add a new bottle, or edit an existing one when [existing] is passed. The
/// same form serves both; on edit it PATCHes and omits branchId (a bottle
/// never moves branches).
void showBarStockDialog(BuildContext context, WidgetRef ref, {BarStockItem? existing}) {
  final isEdit = existing != null;
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final bottlesCtrl =
      TextEditingController(text: (existing?.currentBottles ?? 0).toString());
  final capCtrl =
      TextEditingController(text: (existing?.bottleCapacityMl ?? 750).toStringAsFixed(0));
  final pegCtrl =
      TextEditingController(text: (existing?.pegsMl ?? 30).toStringAsFixed(0));
  final priceCtrl =
      TextEditingController(text: (existing?.pricePerPeg ?? 0).toStringAsFixed(0));
  String category = existing?.category ?? 'spirits';

  showDialog(context: context, builder: (ctx) => AlertDialog(
    title: Text(isEdit ? 'Edit Bar Stock' : 'Add Bar Stock'),
    content: StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Old Monk Rum)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: category,
          decoration: const InputDecoration(labelText: 'Category'),
          onChanged: (v) => set(() => category = v!),
          items: const [
            DropdownMenuItem(value: 'spirits', child: Text('Spirits')),
            DropdownMenuItem(value: 'beer', child: Text('Beer')),
            DropdownMenuItem(value: 'wine', child: Text('Wine')),
            DropdownMenuItem(value: 'other', child: Text('Other')),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: bottlesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bottles'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: capCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity (ml)'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: pegCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Peg size (ml)'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price/Peg (NPR)'))),
        ]),
      ]),
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ElevatedButton(
        onPressed: () async {
          final name = nameCtrl.text.trim();
          if (name.isEmpty) return;
          final profile = ref.read(authNotifierProvider).value;
          final data = <String, dynamic>{
            if (!isEdit) 'branchId': profile?.branchId,
            'name': name,
            'category': category,
            'bottleCapacityMl': double.tryParse(capCtrl.text) ?? 750,
            'currentBottles': double.tryParse(bottlesCtrl.text) ?? 0,
            'pegsMl': double.tryParse(pegCtrl.text) ?? 30,
            'pricePerPeg': double.tryParse(priceCtrl.text) ?? 0,
          };
          try {
            if (isEdit) {
              await ApiClient.instance.patch(ApiConstants.barStockById(existing.id), data: data);
            } else {
              await ApiClient.instance.post(ApiConstants.barStock, data: data);
            }
            ref.invalidate(barStockProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(backgroundColor: AppColors.error, content: Text('Failed: $e')));
            }
          }
        },
        child: Text(isEdit ? 'Save' : 'Add'),
      ),
    ],
  ));
}

/// Confirm, then permanently delete a bottle from Bar Inventory.
Future<void> confirmDeleteBarStock(
    BuildContext context, WidgetRef ref, BarStockItem item) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Bar Stock?'),
      content: Text(
          'Permanently remove "${item.name}" from Bar Inventory? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ApiClient.instance.delete(ApiConstants.barStockById(item.id));
    ref.invalidate(barStockProvider);
    messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.success, content: Text('"${item.name}" deleted.')));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.error, content: Text('Delete failed: $e')));
  }
}

class _BarStockCard extends StatelessWidget {
  final BarStockItem item; final WidgetRef ref;
  const _BarStockCard({required this.item, required this.ref});

  @override
  Widget build(BuildContext context) {
    final pct = (item.currentBottles / (item.currentBottles + 1)).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.wine_bar_rounded, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text('${item.bottleCapacityMl.toInt()}ml • ${item.pegsRemaining} pegs remaining',
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct, minHeight: 4,
              backgroundColor: AppColors.surfaceVariant,
              color: AppColors.primary,
            ),
          ),
        ])),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${item.currentBottles}', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
          Text('bottles', style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textSecondary)),
        ]),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
          onSelected: (v) {
            if (v == 'edit') showBarStockDialog(context, ref, existing: item);
            if (v == 'delete') confirmDeleteBarStock(context, ref, item);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Row(children: [
              Icon(Icons.edit_rounded, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 10), Text('Edit'),
            ])),
            PopupMenuItem(value: 'delete', child: Row(children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
              SizedBox(width: 10), Text('Delete', style: TextStyle(color: AppColors.error)),
            ])),
          ],
        ),
      ]),
    );
  }
}
