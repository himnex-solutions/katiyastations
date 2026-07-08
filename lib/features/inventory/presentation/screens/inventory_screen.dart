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
  Map<String, InventoryItem> _itemsById = {};

  List<PlutoColumn> get _columns => [
    PlutoColumn(
      title: 'ID',
      field: 'id',
      type: PlutoColumnType.text(),
      width: 100,
      hide: true,
    ),
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
    PlutoColumn(
      title: 'Actions',
      field: 'actions',
      type: PlutoColumnType.text(),
      width: 120,
      enableEditingMode: false,
      enableSorting: false,
      enableColumnDrag: false,
      enableContextMenu: false,
      enableFilterMenuItem: false,
      titleTextAlign: PlutoColumnTextAlign.center,
      renderer: (ctx) {
        final id = ctx.row.cells['id']?.value as String?;
        final item = id == null ? null : _itemsById[id];
        if (item == null) return const SizedBox.shrink();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.add_box_rounded, size: 18, color: AppColors.success),
              tooltip: 'Restock',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _showAdjustDialog(item, restock: true),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.textSecondary),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                switch (v) {
                  case 'reduce':
                    _showAdjustDialog(item, restock: false);
                    break;
                  case 'edit':
                    _showEditDialog(item);
                    break;
                  case 'delete':
                    _deleteItem(item);
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reduce', child: Text('Reduce / Waste')),
                PopupMenuItem(value: 'edit', child: Text('Edit item')),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
              ],
            ),
          ],
        );
      },
    ),
  ];

  List<PlutoRow> _buildRows(List<InventoryItem> items) {
    _itemsById = {for (final it in items) it.id: it};
    return items.map((item) {
      final status = item.isOut ? 'out' : item.isLow ? 'low' : 'ok';
      return PlutoRow(cells: {
        'id': PlutoCell(value: item.id),
        'name': PlutoCell(value: item.name),
        'unit': PlutoCell(value: item.unit),
        'stock': PlutoCell(value: item.currentStock),
        'reorder': PlutoCell(value: item.reorderLevel),
        'status': PlutoCell(value: status),
        'actions': PlutoCell(value: ''),
      });
    }).toList();
  }

  // ── Stock actions ──────────────────────────────────────────
  Future<void> _showAdjustDialog(InventoryItem item, {required bool restock}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AdjustStockDialog(item: item, restock: restock),
    );
    if (changed == true) ref.invalidate(inventoryProvider);
  }

  Future<void> _showEditDialog(InventoryItem item) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EditItemDialog(item: item),
    );
    if (changed == true) ref.invalidate(inventoryProvider);
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(
          'Remove "${item.name}" from inventory? Past stock movements are kept for reporting. This cannot be undone.',
          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
        ),
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
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete(ApiConstants.inventoryById(item.id));
      ref.invalidate(inventoryProvider);
      messenger.showSnackBar(SnackBar(content: Text('${item.name} deleted.'), backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
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
                  // Rebuild the grid when stock/reorder values change so live
                  // updates and edits are reflected (PlutoGrid caches its rows).
                  key: ValueKey(Object.hashAll([
                    for (final i in filtered) '${i.id}:${i.currentStock}:${i.reorderLevel}',
                  ])),
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

String _trimNum(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

// ═══════════════════════════════════════════════════════════════════════
//  ADJUST STOCK DIALOG — restock (in) / consume (out) / waste
//  Posts to /inventory/:id/adjust, which records a stock_movement and
//  re-checks the reorder level (firing a low-stock alert if crossed).
// ═══════════════════════════════════════════════════════════════════════
class _AdjustStockDialog extends StatefulWidget {
  final InventoryItem item;
  final bool restock;
  const _AdjustStockDialog({required this.item, required this.restock});
  @override
  State<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends State<_AdjustStockDialog> {
  final _qtyCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  late String _type = widget.restock ? 'in' : 'out';
  bool _submitting = false;
  String? _error;

  static const _types = [
    ['in', 'Add'],
    ['out', 'Remove'],
    ['waste', 'Waste'],
  ];

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a quantity greater than 0');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post(
        ApiConstants.adjustStock(widget.item.id),
        data: {
          'type': _type,
          'quantity': qty,
          if (_reasonCtrl.text.trim().isNotEmpty) 'reason': _reasonCtrl.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final projected = _type == 'in' ? widget.item.currentStock + qty : widget.item.currentStock - qty;

    return AlertDialog(
      title: Text(widget.restock ? 'Restock ${widget.item.name}' : 'Adjust ${widget.item.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current: ${_trimNum(widget.item.currentStock)} ${widget.item.unit}',
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            for (final t in _types)
              ChoiceChip(
                label: Text(t[1]),
                selected: _type == t[0],
                onSelected: (_) => setState(() => _type = t[0]),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(labelText: 'Quantity (${widget.item.unit}) *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(labelText: 'Reason / note'),
          ),
          const SizedBox(height: 12),
          Text('New stock: ${_trimNum(projected)} ${widget.item.unit}',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: projected <= widget.item.reorderLevel ? AppColors.warning : AppColors.success,
              )),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  EDIT ITEM DIALOG — name, unit, reorder level, cost per unit
// ═══════════════════════════════════════════════════════════════════════
class _EditItemDialog extends StatefulWidget {
  final InventoryItem item;
  const _EditItemDialog({required this.item});
  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  late final _nameCtrl = TextEditingController(text: widget.item.name);
  late final _unitCtrl = TextEditingController(text: widget.item.unit);
  late final _reorderCtrl = TextEditingController(text: _trimNum(widget.item.reorderLevel));
  late final _costCtrl =
      TextEditingController(text: widget.item.costPerUnit != null ? _trimNum(widget.item.costPerUnit!) : '');
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _unitCtrl.dispose();
    _reorderCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _unitCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name and unit are required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.instance.patch(
        ApiConstants.inventoryById(widget.item.id),
        data: {
          'name': _nameCtrl.text.trim(),
          'unit': _unitCtrl.text.trim(),
          'reorderLevel': double.tryParse(_reorderCtrl.text.trim()) ?? widget.item.reorderLevel,
          if (_costCtrl.text.trim().isNotEmpty) 'costPerUnit': double.tryParse(_costCtrl.text.trim()),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Inventory Item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Item Name *')),
            const SizedBox(height: 12),
            TextField(controller: _unitCtrl, decoration: const InputDecoration(labelText: 'Unit (kg, litre, piece...) *')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _reorderCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Reorder Level'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _costCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cost / Unit'),
                ),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
