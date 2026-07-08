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

class BarScreen extends ConsumerWidget {
  const BarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onPressed: () => _showAddDialog(context, ref),
          ),
        ],
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          final categories = {'spirits', 'beer', 'wine', 'other'};
          return ResponsiveContent(child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1A0A00), Color(0xFF2A1500)]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.local_bar_rounded, color: AppColors.primary, size: 32),
                    const SizedBox(width: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Bar Inventory', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      Text('${items.length} items tracked', style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
                    ]),
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Total Bottles', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                      Text(items.fold<double>(0, (s, i) => s + i.currentBottles).toStringAsFixed(1),
                          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 20),
                // By category
                ...categories.map((cat) {
                  final catItems = items.where((i) => i.category == cat).toList();
                  if (catItems.isEmpty) return const SizedBox();
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

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final bottlesCtrl = TextEditingController(text: '0');
    final capCtrl = TextEditingController(text: '750');
    final priceCtrl = TextEditingController(text: '0');
    String category = 'spirits';

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Bar Stock'),
      content: StatefulBuilder(builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Old Monk Rum)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: category,
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
        TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price per Peg (NPR)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final profile = ref.read(authNotifierProvider).value;
            await ApiClient.instance.post(
              ApiConstants.barStock,
              data: {
                'branchId': profile?.branchId,
                'name': nameCtrl.text.trim(),
                'category': category,
                'bottleCapacityMl': double.tryParse(capCtrl.text) ?? 750,
                'currentBottles': double.tryParse(bottlesCtrl.text) ?? 0,
                'pegsMl': 30.0,
                'pricePerPeg': double.tryParse(priceCtrl.text) ?? 0,
              },
            );
            ref.invalidate(barStockProvider);
            if (context.mounted) Navigator.pop(ctx);
          },
          child: const Text('Add'),
        ),
      ],
    ));
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
      ]),
    );
  }
}
