import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/inventory_entities.dart';

final inventoryProvider = FutureProvider<List<InventoryItem>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.inventory,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = data['data'] as List<dynamic>;
  return rows.map((r) => InventoryItem.fromJson(r as Map<String, dynamic>)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _filter = 'all';
  String _search = '';
  PlutoGridStateManager? _gridManager;

  List<PlutoColumn> get _columns => [
    PlutoColumn(
      title: 'Item Name',
      field: 'name',
      type: PlutoColumnType.text(),
      width: 220,
      titleTextAlign: PlutoColumnTextAlign.left,
      renderer: (ctx) => Text(
        ctx.cell.value as String,
        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),
    ),
    PlutoColumn(
      title: 'Unit',
      field: 'unit',
      type: PlutoColumnType.text(),
      width: 90,
      titleTextAlign: PlutoColumnTextAlign.center,
      textAlign: PlutoColumnTextAlign.center,
    ),
    PlutoColumn(
      title: 'Current Stock',
      field: 'stock',
      type: PlutoColumnType.number(format: '#,##0.##'),
      width: 140,
      titleTextAlign: PlutoColumnTextAlign.right,
      textAlign: PlutoColumnTextAlign.right,
      renderer: (ctx) {
        final row = ctx.row;
        final status = row.cells['status']?.value as String? ?? 'ok';
        final color = status == 'out'
            ? AppColors.error
            : status == 'low'
                ? AppColors.warning
                : AppColors.success;
        final unit = row.cells['unit']?.value as String? ?? '';
        return Text(
          '${ctx.cell.value} $unit',
          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          textAlign: TextAlign.right,
        );
      },
    ),
    PlutoColumn(
      title: 'Reorder Level',
      field: 'reorder',
      type: PlutoColumnType.number(format: '#,##0.##'),
      width: 130,
      titleTextAlign: PlutoColumnTextAlign.right,
      textAlign: PlutoColumnTextAlign.right,
    ),
    PlutoColumn(
      title: 'Status',
      field: 'status',
      type: PlutoColumnType.text(),
      width: 110,
      titleTextAlign: PlutoColumnTextAlign.center,
      textAlign: PlutoColumnTextAlign.center,
      renderer: (ctx) {
        final status = ctx.cell.value as String;
        final color = status == 'out'
            ? AppColors.error
            : status == 'low'
                ? AppColors.warning
                : AppColors.success;
        final label = status == 'out' ? 'OUT' : status == 'low' ? 'LOW' : 'OK';
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(label, style: GoogleFonts.outfit(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ),
        );
      },
    ),
  ];

  List<PlutoRow> _buildRows(List<InventoryItem> items) {
    return items.map((item) {
      final status = item.isOut ? 'out' : item.isLow ? 'low' : 'ok';
      return PlutoRow(cells: {
        'name': PlutoCell(value: item.name),
        'unit': PlutoCell(value: item.unit),
        'stock': PlutoCell(value: item.currentStock),
        'reorder': PlutoCell(value: item.reorderLevel),
        'status': PlutoCell(value: status),
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inventoryProvider);

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
              child: const Icon(Icons.inventory_2,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Inventory',
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
          TextButton.icon(icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add Item'), onPressed: () => _showAddDialog(context)),
        ],
      ),
      body: Column(
        children: [
          // Search + filter bar
          Container(
            color: AppColors.surface, padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: TextField(
                decoration: const InputDecoration(hintText: 'Search items...', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
                onChanged: (v) {
                  setState(() => _search = v.toLowerCase());
                  _applyGridFilter();
                },
              )),
              const SizedBox(width: 12),
              ...['all', 'low', 'out'].map((f) => GestureDetector(
                onTap: () {
                  setState(() => _filter = f);
                  _applyGridFilter();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _filter == f ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _filter == f ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(f.toUpperCase(), style: GoogleFonts.outfit(fontSize: 11, color: _filter == f ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w600)),
                ),
              )),
            ]),
          ),
          // Stats chips
          itemsAsync.when(
            loading: () => const SizedBox(height: 40, child: LinearProgressIndicator()),
            error: (_, __) => const SizedBox(),
            data: (items) {
              final low = items.where((i) => i.isLow).length;
              final out = items.where((i) => i.isOut).length;
              return Container(
                color: AppColors.surface, padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _SChip('Total', '${items.length}', AppColors.info),
                    const SizedBox(width: 8),
                    _SChip('Low Stock', '$low', AppColors.warning),
                    const SizedBox(width: 8),
                    _SChip('Out of Stock', '$out', AppColors.error),
                  ]),
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: itemsAsync.when(
              loading: () => Skeletonizer(
                enabled: true,
                effect: const ShimmerEffect(
                  baseColor: AppColors.surfaceVariant,
                  highlightColor: AppColors.surface,
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: 8,
                  itemBuilder: (_, i) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10))),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(height: 14, width: 140, color: AppColors.surfaceVariant),
                        const SizedBox(height: 6),
                        Container(height: 11, width: 100, color: AppColors.surfaceVariant),
                      ])),
                      Container(height: 14, width: 60, color: AppColors.surfaceVariant),
                    ]),
                  ),
                ),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                var filtered = items.where((i) {
                  if (_search.isNotEmpty && !i.name.toLowerCase().contains(_search)) return false;
                  if (_filter == 'low') return i.isLow;
                  if (_filter == 'out') return i.isOut;
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textHint),
                    const SizedBox(height: 16),
                    Text('No items found', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 16)),
                  ]));
                }

                return PlutoGrid(
                  columns: _columns,
                  rows: _buildRows(filtered),
                  onLoaded: (e) {
                    _gridManager = e.stateManager;
                    _gridManager!.setShowColumnFilter(true);
                  },
                  configuration: PlutoGridConfiguration(
                    style: PlutoGridStyleConfig(
                      gridBackgroundColor: AppColors.background,
                      rowColor: AppColors.surface,
                      oddRowColor: AppColors.surfaceVariant,
                      activatedColor: AppColors.primary.withValues(alpha: 0.08),
                      activatedBorderColor: AppColors.primary,
                      gridBorderColor: AppColors.border,
                      columnTextStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      cellTextStyle: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary),
                      columnHeight: 46,
                      rowHeight: 52,
                      borderColor: AppColors.border,
                      inactivatedBorderColor: AppColors.border,
                    ),
                  ),
                ).animate().fadeIn(duration: 300.ms);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _applyGridFilter() {
    // PlutoGrid filter is applied by rebuilding with filtered rows via state
    setState(() {});
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'kg');
    final stockCtrl = TextEditingController(text: '0');
    final reorderCtrl = TextEditingController(text: '1');

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Inventory Item'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item Name *')),
        const SizedBox(height: 12),
        TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Unit (kg, litre, piece...)')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current Stock'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: reorderCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Reorder Level'))),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final profile = ref.read(authNotifierProvider).value;
            await ApiClient.instance.post(
              ApiConstants.inventory,
              data: {
                'branchId': profile?.branchId,
                'name': nameCtrl.text.trim(),
                'unit': unitCtrl.text.trim(),
                'currentStock': double.tryParse(stockCtrl.text) ?? 0,
                'reorderLevel': double.tryParse(reorderCtrl.text) ?? 0,
              },
            );
            ref.invalidate(inventoryProvider);
            if (context.mounted) Navigator.pop(ctx);
          },
          child: const Text('Add'),
        ),
      ],
    ));
  }
}

class _SChip extends StatelessWidget {
  final String label, value; final Color color;
  const _SChip(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Text('$label: $value', style: GoogleFonts.outfit(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
  );
}
