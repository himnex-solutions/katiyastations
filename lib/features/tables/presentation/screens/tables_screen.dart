import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/tables_provider.dart';
import '../../domain/entities/table_entities.dart';
import '../../../orders/presentation/providers/order_provider.dart';

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedSection = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(tablesStreamProvider);
    final profile = ref.watch(authNotifierProvider).value;
    final isManager = profile?.isBranchManager == true;
    final isCashier = profile?.isCashier == true;
    final canManage = isManager || isCashier;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
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
              child: const Icon(Icons.grid_view,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Table Management',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: AppColors.textPrimary)),
          ],
        ),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              tooltip: 'Add Table',
              onPressed: () => _showAddTableDialog(context),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle:
              GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle:
              GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded, size: 18), text: 'Floor'),
            Tab(icon: Icon(Icons.event_note_rounded, size: 18), text: 'Reservations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Floor Layout Tab ──────────────────────────────────────────
          tablesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: AppColors.error))),
            data: (tables) => _FloorView(
              tables: tables,
              selectedSection: _selectedSection,
              onSectionChanged: (s) => setState(() => _selectedSection = s),
              canManage: canManage,
              isManager: isManager,
              onTableTap: (t) => _handleTableTap(context, t),
              onTableLongPress: (t) =>
                  canManage ? _showTableContextMenu(context, t) : null,
            ),
          ),
          // ── Reservations Tab ──────────────────────────────────────────
          _ReservationsTab(canManage: canManage),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  void _handleTableTap(BuildContext context, RestaurantTable table) async {
    if (table.isDisabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This table is currently disabled.'),
            backgroundColor: AppColors.textSecondary),
      );
      return;
    }

    if (table.isAvailable) {
      await _showOpenSessionDialog(context, table);
    } else if (table.isOccupied || table.isReadyForBilling) {
      // Navigate to existing session
      final session = await ref.read(tableSessionProvider(table.id).future);
      if (session != null && context.mounted) {
        _showSessionActionsDialog(context, table, session);
      }
    } else if (table.isReserved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Table is reserved. Convert from Reservations tab.'),
            backgroundColor: AppColors.tableReserved),
      );
    }
  }

  Future<void> _showOpenSessionDialog(
      BuildContext context, RestaurantTable table) async {
    int guests = 2;
    final notesCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Open Session',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text('Table ${table.tableNumber} · ${table.section}',
                style: GoogleFonts.outfit(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Text('Number of Guests',
                  style: GoogleFonts.outfit(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CircleIconBtn(
                    icon: Icons.remove,
                    onTap: () => setLocal(() {
                      if (guests > 1) guests--;
                    }),
                  ),
                  const SizedBox(width: 24),
                  Text('$guests',
                      style: GoogleFonts.outfit(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                  const SizedBox(width: 24),
                  _CircleIconBtn(
                    icon: Icons.add,
                    onTap: () => setLocal(() => guests++),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'e.g. Birthday table, Allergy info',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Open Session'),
            onPressed: () async {
              Navigator.pop(ctx);
              final session = await ref
                  .read(tableNotifierProvider.notifier)
                  .openSession(table.id,
                      guestCount: guests,
                      notes: notesCtrl.text.trim().isEmpty
                          ? null
                          : notesCtrl.text.trim());
              if (session != null && context.mounted) {
                context.go(
                    '/tables/${table.id}/order?sessionId=${session.id}');
              }
            },
          ),
        ],
      ),
    );
  }

  void _showSessionActionsDialog(
      BuildContext context, RestaurantTable table, TableSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: AppColors.tableOccupied,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Table ${table.tableNumber}',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
                '${session.sessionNumber} · ${session.guestCount} guests · ${session.durationLabel}',
                style: GoogleFonts.outfit(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        content: SizedBox(
          width: ctx.dialogWidth(320),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionTile(
                  icon: Icons.restaurant_menu_rounded,
                  label: 'View / Add Orders',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go(
                        '/tables/${table.id}/order?sessionId=${session.id}');
                  },
                ),
                // ── Hold / Resume Table session ──────────────────────────────
                if (session.onHold)
                  _ActionTile(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Resume Order (Unhold)',
                    color: AppColors.success,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await ref.read(tableNotifierProvider.notifier).unholdSession(session.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok ? 'Order resumed!' : 'Failed to resume order'),
                          backgroundColor: ok ? AppColors.success : AppColors.error,
                        ));
                      }
                    },
                  )
                else
                  _ActionTile(
                    icon: Icons.pause_circle_outline_rounded,
                    label: 'Hold Order',
                    color: AppColors.warning,
                    onTap: () async {
                      Navigator.pop(ctx);
                      String? reason;
                      await showDialog(
                        context: context,
                        builder: (holdCtx) {
                          final ctrl = TextEditingController();
                          return AlertDialog(
                            backgroundColor: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: Text('Hold Order', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Enter a reason for holding this order (optional):',
                                    style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary)),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: ctrl,
                                  decoration: InputDecoration(
                                    hintText: 'e.g. Guests stepped out...',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(holdCtx), child: const Text('Cancel')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.warning,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  reason = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
                                  Navigator.pop(holdCtx);
                                },
                                child: const Text('Hold'),
                              ),
                            ],
                          );
                        },
                      );
                      
                      final ok = await ref
                          .read(tableNotifierProvider.notifier)
                          .holdSession(session.id, reason: reason);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok ? 'Order placed on hold' : 'Failed to place order on hold'),
                          backgroundColor: ok ? AppColors.warning : AppColors.error,
                        ));
                      }
                    },
                  ),
                _ActionTile(
                  icon: Icons.receipt_long_rounded,
                  label: 'Request Bill',
                  color: AppColors.warning,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref
                        .read(tableNotifierProvider.notifier)
                        .requestBill(table.id, session.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Bill requested!'),
                          backgroundColor: AppColors.warning));
                    }
                  },
                ),
                _ActionTile(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Transfer Table',
                  color: AppColors.info,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTransferDialog(context, table, session);
                  },
                ),
                // ── Merge Table ──────────────────────────────────────────────
                _ActionTile(
                  icon: Icons.merge_type_rounded,
                  label: 'Merge Table',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMergeDialog(context, table, session);
                  },
                ),
                // ── Split Table ──────────────────────────────────────────────
                _ActionTile(
                  icon: Icons.call_split_rounded,
                  label: 'Split Table',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSplitDialog(context, table, session);
                  },
                ),
                _ActionTile(
                  icon: Icons.point_of_sale_rounded,
                  label: 'Go to Cashier',
                  color: AppColors.success,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go(
                        '/cashier?sessionId=${session.id}&tableId=${table.id}');
                  },
                ),
                _ActionTile(
                  icon: Icons.close_rounded,
                  label: 'Close & Free Table',
                  color: AppColors.error,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmCloseSession(context, table, session);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _showTransferDialog(
      BuildContext context, RestaurantTable fromTable, TableSession session) {
    final tablesAsync = ref.read(tablesStreamProvider);
    final availableTables = tablesAsync.value
            ?.where((t) => t.isAvailable && t.id != fromTable.id)
            .toList() ??
        [];

    if (availableTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No available tables to transfer to.'),
          backgroundColor: AppColors.error));
      return;
    }

    String? selectedId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Transfer to Table',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: ctx.dialogWidth(400),
            child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Move session ${session.sessionNumber} from '
                  'Table ${fromTable.tableNumber} to:',
                  style: GoogleFonts.outfit(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableTables.map((t) {
                  final isSelected = t.id == selectedId;
                  return GestureDetector(
                    onTap: () => setLocal(() => selectedId = t.id),
                    child: AnimatedContainer(
                      duration: 150.ms,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(t.tableNumber,
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textPrimary)),
                          Text('Cap: ${t.capacity}',
                              style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  color: isSelected
                                      ? Colors.white70
                                      : AppColors.textHint)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final ok = await ref
                          .read(tableNotifierProvider.notifier)
                          .transferSession(
                            fromTableId: fromTable.id,
                            toTableId: selectedId!,
                            sessionId: session.id,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Session transferred!'
                                : 'Transfer failed'),
                            backgroundColor:
                                ok ? AppColors.success : AppColors.error));
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMergeDialog(
      BuildContext context, RestaurantTable fromTable, TableSession fromSession) {
    final tablesAsync = ref.read(tablesStreamProvider);
    final occupiedTables = tablesAsync.value
            ?.where((t) => (t.isOccupied || t.isReadyForBilling) && t.id != fromTable.id)
            .toList() ??
        [];

    if (occupiedTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No active tables to merge into.'),
          backgroundColor: AppColors.error));
      return;
    }

    String? selectedTableId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Merge Table', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: ctx.dialogWidth(400),
            child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merge Table ${fromTable.tableNumber} into another active table:',
                style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: occupiedTables.map((t) {
                  final isSelected = t.id == selectedTableId;
                  return GestureDetector(
                    onTap: () => setLocal(() => selectedTableId = t.id),
                    child: AnimatedContainer(
                      duration: 150.ms,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                      ),
                      child: Text(
                        t.tableNumber,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedTableId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      
                      final targetTable = occupiedTables.firstWhere((t) => t.id == selectedTableId);
                      final targetSessionId = targetTable.currentSessionId;
                      if (targetSessionId == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Target table has no active session.'),
                              backgroundColor: AppColors.error));
                        }
                        return;
                      }

                      final ok = await ref
                          .read(tableNotifierProvider.notifier)
                          .mergeSessions(
                            fromTableId: fromTable.id,
                            toTableId: selectedTableId!,
                            fromSessionId: fromSession.id,
                            toSessionId: targetSessionId,
                          );

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok ? 'Tables merged successfully!' : 'Merge failed'),
                            backgroundColor: ok ? AppColors.success : AppColors.error));
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSplitDialog(
      BuildContext context, RestaurantTable fromTable, TableSession fromSession) {
    final tablesAsync = ref.read(tablesStreamProvider);
    final availableTables = tablesAsync.value
            ?.where((t) => t.isAvailable && t.id != fromTable.id)
            .toList() ??
        [];

    if (availableTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No available tables to split into.'),
          backgroundColor: AppColors.error));
      return;
    }

    String? selectedDestTableId;
    List<String> kotIdsToMove = [];
    int newGuestCount = 1;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Split Table & KOTs', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Consumer(
          builder: (context, ref, child) {
            final kotsAsync = ref.watch(sessionKotsProvider(fromSession.id));
            return kotsAsync.when(
              loading: () => const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ),
              error: (e, _) => Text('Error loading KOTs: $e'),
              data: (kots) {
                if (kots.isEmpty) {
                  return const Text('No KOTs sent for this session to split.');
                }
                return StatefulBuilder(
                  builder: (ctx, setLocal) => SizedBox(
                    width: ctx.dialogWidth(320),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Select KOTs to move to the new table:',
                              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(height: 8),
                          ...kots.map((kot) {
                            final isChecked = kotIdsToMove.contains(kot.id);
                            return CheckboxListTile(
                              dense: true,
                              title: Text(kot.kotNumber, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                'Items: ${kot.items.length} · Status: ${kot.status}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              value: isChecked,
                              onChanged: (val) {
                                setLocal(() {
                                  if (val == true) {
                                    kotIdsToMove.add(kot.id);
                                  } else {
                                    kotIdsToMove.remove(kot.id);
                                  }
                                });
                              },
                            );
                          }),
                          const Divider(height: 20),
                          Text('Select Destination Table:',
                              style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: availableTables.map((t) {
                              final isSelected = t.id == selectedDestTableId;
                              return GestureDetector(
                                onTap: () => setLocal(() => selectedDestTableId = t.id),
                                child: AnimatedContainer(
                                  duration: 150.ms,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                                  ),
                                  child: Text(
                                    t.tableNumber,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      color: isSelected ? Colors.white : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              Text('Guests on new table:',
                                  style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () => setLocal(() {
                                  if (newGuestCount > 1) newGuestCount--;
                                }),
                              ),
                              Text('$newGuestCount',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => setLocal(() => newGuestCount++),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (selectedDestTableId == null || kotIdsToMove.isEmpty) return;
              Navigator.pop(ctx);
              final ok = await ref.read(tableNotifierProvider.notifier).splitSession(
                    fromTableId: fromTable.id,
                    toTableId: selectedDestTableId!,
                    fromSessionId: fromSession.id,
                    kotIdsToMove: kotIdsToMove,
                    guestCount: newGuestCount,
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Session split successfully!' : 'Split failed'),
                  backgroundColor: ok ? AppColors.success : AppColors.error,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Split Table'),
          ),
        ],
      ),
    );
  }


  void _confirmCloseSession(
      BuildContext context, RestaurantTable table, TableSession session) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Close Session?',
      message: 'Are you sure you want to close session ${session.sessionNumber} '
          'and free Table ${table.tableNumber}?\n\n'
          'This should only be done if no payment is required.',
      confirmLabel: 'Close Session',
      icon: Icons.event_available_rounded,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref
        .read(tableNotifierProvider.notifier)
        .closeSession(table.id, session.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Table freed!' : 'Failed to close session'),
          backgroundColor: ok ? AppColors.success : AppColors.error));
    }
  }

  void _showTableContextMenu(BuildContext context, RestaurantTable table) {
    final isOccupiedOrHasOrders = table.isOccupied ||
        table.isReadyForBilling ||
        table.currentSessionId != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_restaurant_rounded,
                    color: AppColors.primary),
                const SizedBox(width: 10),
                Text('Table ${table.tableNumber}',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: AppColors.textPrimary)),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary)),
              ],
            ),
            const Divider(height: 20),
            _ActionTile(
              icon: Icons.edit_rounded,
              label: 'Edit Table',
              color: AppColors.info,
              enabled: !isOccupiedOrHasOrders,
              subtitle: isOccupiedOrHasOrders
                  ? 'Cannot edit occupied tables or tables with active orders'
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _showEditTableDialog(context, table);
              },
            ),
            if (table.isEnabled)
              _ActionTile(
                icon: Icons.block_rounded,
                label: 'Disable Table',
                color: AppColors.textSecondary,
                enabled: !isOccupiedOrHasOrders,
                subtitle: isOccupiedOrHasOrders
                    ? 'Cannot disable occupied tables or tables with active orders'
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await ref
                      .read(tableNotifierProvider.notifier)
                      .setTableEnabled(table.id, false);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Failed to disable table.'),
                        backgroundColor: AppColors.error));
                  }
                },
              ),
            if (!table.isEnabled)
              _ActionTile(
                icon: Icons.check_circle_rounded,
                label: 'Enable Table',
                color: AppColors.success,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await ref
                      .read(tableNotifierProvider.notifier)
                      .setTableEnabled(table.id, true);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Failed to enable table.'),
                        backgroundColor: AppColors.error));
                  }
                },
              ),
            _ActionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Delete Table',
              color: AppColors.error,
              enabled: !isOccupiedOrHasOrders,
              subtitle: isOccupiedOrHasOrders
                  ? 'Cannot delete occupied tables or tables with active orders'
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteTable(context, table);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTableDialog(BuildContext context) {
    final numCtrl = TextEditingController();
    final sectionCtrl = TextEditingController(text: 'Ground Floor');
    final descCtrl = TextEditingController();
    int capacity = 4;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Add Table',
            style:
                GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18)),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FormField(
                    controller: numCtrl,
                    label: 'Table Number',
                    hint: 'e.g. A-01, T-05'),
                const SizedBox(height: 12),
                _FormField(
                    controller: sectionCtrl,
                    label: 'Floor / Section',
                    hint: 'e.g. Ground Floor, Terrace'),
                const SizedBox(height: 12),
                _FormField(
                    controller: descCtrl,
                    label: 'Description (optional)',
                    hint: 'e.g. Window table, Private',
                    maxLines: 2),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Capacity',
                        style: GoogleFonts.outfit(
                            color: AppColors.textSecondary, fontSize: 14)),
                    const Spacer(),
                    _CircleIconBtn(
                        icon: Icons.remove,
                        onTap: () =>
                            setLocal(() => capacity > 1 ? capacity-- : null)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('$capacity',
                          style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                    _CircleIconBtn(
                        icon: Icons.add,
                        onTap: () => setLocal(() => capacity++)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              if (numCtrl.text.trim().isEmpty) return;
              final ok = await ref
                  .read(tableNotifierProvider.notifier)
                  .addTable(
                    tableNumber: numCtrl.text.trim(),
                    section: sectionCtrl.text.trim().isEmpty
                        ? 'Main'
                        : sectionCtrl.text.trim(),
                    capacity: capacity,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                  );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Failed to add table'),
                      backgroundColor: AppColors.error));
                }
              }
            },
            child: const Text('Add Table'),
          ),
        ],
      ),
    );
  }

  void _showEditTableDialog(BuildContext context, RestaurantTable table) {
    final numCtrl = TextEditingController(text: table.tableNumber);
    final sectionCtrl = TextEditingController(text: table.section);
    final descCtrl = TextEditingController(text: table.description ?? '');
    int capacity = table.capacity;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Edit Table ${table.tableNumber}',
            style:
                GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18)),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FormField(controller: numCtrl, label: 'Table Number'),
                const SizedBox(height: 12),
                _FormField(
                    controller: sectionCtrl, label: 'Floor / Section'),
                const SizedBox(height: 12),
                _FormField(
                    controller: descCtrl,
                    label: 'Description',
                    maxLines: 2),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Capacity',
                        style: GoogleFonts.outfit(
                            color: AppColors.textSecondary, fontSize: 14)),
                    const Spacer(),
                    _CircleIconBtn(
                        icon: Icons.remove,
                        onTap: () =>
                            setLocal(() => capacity > 1 ? capacity-- : null)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('$capacity',
                          style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                    _CircleIconBtn(
                        icon: Icons.add,
                        onTap: () => setLocal(() => capacity++)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              if (numCtrl.text.trim().isEmpty) return;
              final ok = await ref
                  .read(tableNotifierProvider.notifier)
                  .editTable(
                    tableId: table.id,
                    tableNumber: numCtrl.text.trim(),
                    section: sectionCtrl.text.trim().isEmpty
                        ? 'Main'
                        : sectionCtrl.text.trim(),
                    capacity: capacity,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Failed to update table'),
                    backgroundColor: AppColors.error));
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTable(BuildContext context, RestaurantTable table) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Table ${table.tableNumber}?',
      message: 'This will permanently delete Table ${table.tableNumber}. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !context.mounted) return;
    final ok =
        await ref.read(tableNotifierProvider.notifier).deleteTable(table.id);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Failed to delete table. Make sure it is not occupied.'),
          backgroundColor: AppColors.error));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Floor View
// ═══════════════════════════════════════════════════════════════════════════
class _FloorView extends StatelessWidget {
  final List<RestaurantTable> tables;
  final String selectedSection;
  final ValueChanged<String> onSectionChanged;
  final bool canManage;
  final bool isManager;
  final ValueChanged<RestaurantTable> onTableTap;
  final ValueChanged<RestaurantTable>? onTableLongPress;

  const _FloorView({
    required this.tables,
    required this.selectedSection,
    required this.onSectionChanged,
    required this.canManage,
    required this.isManager,
    required this.onTableTap,
    this.onTableLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final sections = ['All', ...{...tables.map((t) => t.section)}];
    final filtered = selectedSection == 'All'
        ? tables
        : tables.where((t) => t.section == selectedSection).toList();

    final available = tables.where((t) => t.isAvailable).length;
    final occupied = tables.where((t) => t.isOccupied).length;
    final reserved = tables.where((t) => t.isReserved).length;
    final billing = tables.where((t) => t.isReadyForBilling).length;
    final disabled = tables.where((t) => t.isDisabled).length;

    return Column(
      children: [
        // ── Occupancy Summary ──────────────────────────────────────────
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StatusBadge('Available', available, AppColors.tableAvailable),
                const SizedBox(width: 10),
                _StatusBadge('Occupied', occupied, AppColors.tableOccupied),
                const SizedBox(width: 10),
                _StatusBadge('Reserved', reserved, AppColors.tableReserved),
                const SizedBox(width: 10),
                _StatusBadge('Billing', billing, AppColors.warning),
                const SizedBox(width: 10),
                _StatusBadge('Disabled', disabled, AppColors.textHint),
              ],
            ),
          ),
        ),
        // ── Section Tabs ───────────────────────────────────────────────
        if (sections.length > 2)
          Container(
            height: 44,
            color: AppColors.surface,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: sections.length,
              itemBuilder: (ctx, i) {
                final sec = sections[i];
                final isSelected = sec == selectedSection;
                return GestureDetector(
                  onTap: () => onSectionChanged(sec),
                  child: AnimatedContainer(
                    duration: 150.ms,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(sec,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        )),
                  ),
                );
              },
            ),
          ),
        const Divider(height: 1, color: AppColors.divider),
        // ── Tables Grid ────────────────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.table_restaurant_outlined,
                          size: 56, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      Text('No tables in this section',
                          style: GoogleFonts.outfit(
                              color: AppColors.textSecondary, fontSize: 15)),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (ctx, constraints) {
                    final isNarrow = constraints.maxWidth < 600;
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: isNarrow ? 160 : 180,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: isNarrow ? 0.85 : 0.82,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _TableCard(
                        table: filtered[i],
                        onTap: () => onTableTap(filtered[i]),
                        onLongPress: onTableLongPress != null
                            ? () => onTableLongPress!(filtered[i])
                            : null,
                      )
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: i * 35))
                          .scale(
                              begin: const Offset(0.92, 0.92),
                              duration: 200.ms),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reservations Tab
// ═══════════════════════════════════════════════════════════════════════════
class _ReservationsTab extends ConsumerStatefulWidget {
  final bool canManage;
  const _ReservationsTab({required this.canManage});

  @override
  ConsumerState<_ReservationsTab> createState() => _ReservationsTabState();
}

class _ReservationsTabState extends ConsumerState<_ReservationsTab> {
  String _filter = 'today'; // today | upcoming | all

  @override
  Widget build(BuildContext context) {
    final reservationsAsync = ref.watch(reservationsStreamProvider);

    return Column(
      children: [
        // ── Filter Bar ─────────────────────────────────────────────────
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _FilterChip('Today', 'today', _filter,
                        (v) => setState(() => _filter = v)),
                    const SizedBox(width: 8),
                    _FilterChip('Upcoming', 'upcoming', _filter,
                        (v) => setState(() => _filter = v)),
                    const SizedBox(width: 8),
                    _FilterChip(
                        'All', 'all', _filter, (v) => setState(() => _filter = v)),
                  ],
                ),
              ),
              if (widget.canManage)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Book', style: TextStyle(fontSize: 13)),
                  onPressed: () => _showAddReservationDialog(context),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: reservationsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: AppColors.error))),
            data: (reservations) {
              final filtered = reservations.where((r) {
                if (_filter == 'today') return r.isToday && !r.isCancelled;
                if (_filter == 'upcoming') return r.isUpcoming;
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_busy_rounded,
                          size: 56, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      Text('No reservations',
                          style: GoogleFonts.outfit(
                              color: AppColors.textSecondary, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text(
                          _filter == 'today'
                              ? 'No reservations for today'
                              : 'No upcoming reservations',
                          style: GoogleFonts.outfit(
                              color: AppColors.textHint, fontSize: 12)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) => _ReservationCard(
                  reservation: filtered[i],
                  canManage: widget.canManage,
                  onEdit: () =>
                      _showEditReservationDialog(context, filtered[i]),
                  onCancel: () => _confirmCancel(context, filtered[i]),
                  onNoShow: () async {
                    await ref
                        .read(reservationNotifierProvider.notifier)
                        .markNoShow(filtered[i].id);
                  },
                  onSeat: () => _seatReservation(context, filtered[i]),
                ).animate().fadeIn(delay: Duration(milliseconds: i * 40)),
              );
            },
          ),
        ),
      ],
    );
  }

  void _seatReservation(BuildContext context, TableReservation reservation) {
    final tablesAsync = ref.read(tablesStreamProvider);
    final availableTables = tablesAsync.value
            ?.where((t) => t.isAvailable)
            .toList() ??
        [];

    if (availableTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No available tables to seat the guest.'),
          backgroundColor: AppColors.error));
      return;
    }

    String? selectedId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Seat ${reservation.customerName}',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
              Text('${reservation.guestCount} guests',
                  style: GoogleFonts.outfit(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          content: SizedBox(
            width: ctx.dialogWidth(400),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableTables.map((t) {
              final isSelected = t.id == selectedId;
              return GestureDetector(
                onTap: () => setLocal(() => selectedId = t.id),
                child: AnimatedContainer(
                  duration: 150.ms,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(t.tableNumber,
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textPrimary)),
                      Text('Cap: ${t.capacity}',
                          style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.white70
                                  : AppColors.textHint)),
                    ],
                  ),
                ),
              );
            }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      // Mark reservation as seated
                      await ref
                          .read(reservationNotifierProvider.notifier)
                          .updateReservation(
                            id: reservation.id,
                            customerName: reservation.customerName,
                            customerPhone: reservation.customerPhone,
                            guestCount: reservation.guestCount,
                            reservationTime: reservation.reservationTime,
                            status: 'seated',
                          );
                      // Open table session
                      if (context.mounted) {
                        final session = await ref
                            .read(tableNotifierProvider.notifier)
                            .openSession(selectedId!,
                                guestCount: reservation.guestCount,
                                notes:
                                    'Reservation: ${reservation.customerName}');
                        if (session != null && context.mounted) {
                          context.go(
                              '/tables/$selectedId/order?sessionId=${session.id}');
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Seat & Open'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddReservationDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    int guestCount = 2;
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime =
        TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text('New Reservation',
              style:
                  GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FormField(
                    controller: nameCtrl,
                    label: 'Customer Name',
                    hint: 'Full name'),
                const SizedBox(height: 12),
                _FormField(
                    controller: phoneCtrl,
                    label: 'Phone Number',
                    hint: '+977-',
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Guests',
                        style: GoogleFonts.outfit(
                            color: AppColors.textSecondary, fontSize: 14)),
                    const Spacer(),
                    _CircleIconBtn(
                        icon: Icons.remove,
                        onTap: () => setLocal(
                            () => guestCount > 1 ? guestCount-- : null)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('$guestCount',
                          style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                    _CircleIconBtn(
                        icon: Icons.add,
                        onTap: () => setLocal(() => guestCount++)),
                  ],
                ),
                const SizedBox(height: 16),
                // Date picker
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(
                      DateFormat('EEE, MMM d, yyyy').format(selectedDate),
                      style: GoogleFonts.outfit(fontSize: 14)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 90)),
                    );
                    if (d != null) setLocal(() => selectedDate = d);
                  },
                ),
                const SizedBox(height: 8),
                // Time picker
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.access_time_rounded, size: 16),
                  label: Text(selectedTime.format(context),
                      style: GoogleFonts.outfit(fontSize: 14)),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (t != null) setLocal(() => selectedTime = t);
                  },
                ),
                const SizedBox(height: 12),
                _FormField(
                    controller: notesCtrl,
                    label: 'Notes (optional)',
                    maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final dt = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
                final ok = await ref
                    .read(reservationNotifierProvider.notifier)
                    .addReservation(
                      customerName: nameCtrl.text.trim(),
                      customerPhone: phoneCtrl.text.trim().isEmpty
                          ? null
                          : phoneCtrl.text.trim(),
                      guestCount: guestCount,
                      reservationTime: dt,
                      notes: notesCtrl.text.trim().isEmpty
                          ? null
                          : notesCtrl.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Failed to save reservation'),
                      backgroundColor: AppColors.error));
                }
              },
              child: const Text('Book Table'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditReservationDialog(
      BuildContext context, TableReservation reservation) {
    final nameCtrl =
        TextEditingController(text: reservation.customerName);
    final phoneCtrl =
        TextEditingController(text: reservation.customerPhone ?? '');
    final notesCtrl =
        TextEditingController(text: reservation.notes ?? '');
    int guestCount = reservation.guestCount;
    DateTime selectedDate = reservation.reservationTime;
    TimeOfDay selectedTime =
        TimeOfDay.fromDateTime(reservation.reservationTime);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text('Edit Reservation',
              style:
                  GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FormField(controller: nameCtrl, label: 'Customer Name'),
                const SizedBox(height: 12),
                _FormField(
                    controller: phoneCtrl,
                    label: 'Phone',
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Guests',
                        style: GoogleFonts.outfit(
                            color: AppColors.textSecondary, fontSize: 14)),
                    const Spacer(),
                    _CircleIconBtn(
                        icon: Icons.remove,
                        onTap: () => setLocal(
                            () => guestCount > 1 ? guestCount-- : null)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('$guestCount',
                          style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                    _CircleIconBtn(
                        icon: Icons.add,
                        onTap: () => setLocal(() => guestCount++)),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(
                      DateFormat('EEE, MMM d, yyyy').format(selectedDate),
                      style: GoogleFonts.outfit(fontSize: 14)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 90)),
                    );
                    if (d != null) setLocal(() => selectedDate = d);
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.access_time_rounded, size: 16),
                  label: Text(selectedTime.format(context),
                      style: GoogleFonts.outfit(fontSize: 14)),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (t != null) setLocal(() => selectedTime = t);
                  },
                ),
                const SizedBox(height: 12),
                _FormField(
                    controller: notesCtrl,
                    label: 'Notes',
                    maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final dt = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
                await ref
                    .read(reservationNotifierProvider.notifier)
                    .updateReservation(
                      id: reservation.id,
                      customerName: nameCtrl.text.trim(),
                      customerPhone: phoneCtrl.text.trim().isEmpty
                          ? null
                          : phoneCtrl.text.trim(),
                      guestCount: guestCount,
                      reservationTime: dt,
                      notes: notesCtrl.text.trim().isEmpty
                          ? null
                          : notesCtrl.text.trim(),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context, TableReservation reservation) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Reservation?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text(
            'Cancel the reservation for ${reservation.customerName}?',
            style: GoogleFonts.outfit(
                color: AppColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(reservationNotifierProvider.notifier)
                  .cancelReservation(reservation.id);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Cancel Reservation'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Table Card Widget
// ═══════════════════════════════════════════════════════════════════════════
class _TableCard extends ConsumerWidget {
  final RestaurantTable table;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _TableCard(
      {required this.table, required this.onTap, this.onLongPress});

  Color _statusColor(bool isOnHold) {
    if (table.isDisabled) return AppColors.textHint;
    if (isOnHold) return AppColors.warning;
    if (table.isReadyForBilling) return AppColors.warning;
    if (table.isAvailable) return AppColors.tableAvailable;
    if (table.isOccupied) return AppColors.tableOccupied;
    if (table.isReserved) return AppColors.tableReserved;
    return AppColors.textHint;
  }

  String _statusLabel(bool isOnHold) {
    if (table.isDisabled) return 'DISABLED';
    if (isOnHold) return 'ON HOLD';
    if (table.isReadyForBilling) return 'BILLING';
    if (table.isAvailable) return 'AVAILABLE';
    if (table.isOccupied) return 'OCCUPIED';
    if (table.isReserved) return 'RESERVED';
    return table.status.toUpperCase();
  }

  IconData _statusIcon(bool isOnHold) {
    if (table.isDisabled) return Icons.block_rounded;
    if (isOnHold) return Icons.pause_circle_filled_rounded;
    if (table.isReadyForBilling) return Icons.receipt_long_rounded;
    if (table.isAvailable) return Icons.table_restaurant_rounded;
    if (table.isOccupied) return Icons.people_rounded;
    if (table.isReserved) return Icons.event_available_rounded;
    return Icons.table_restaurant_rounded;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(activeSessionsStreamProvider);
    final session = sessionsAsync.value?.where((s) => s.tableId == table.id).firstOrNull;
    final isOnHold = session?.onHold ?? false;

    final isBilling = table.isReadyForBilling;
    final isDisabled = table.isDisabled;
    final color = _statusColor(isOnHold);
    final label = _statusLabel(isOnHold);
    final iconData = _statusIcon(isOnHold);

    Widget card = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isDisabled
              ? AppColors.surfaceVariant
              : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDisabled
                ? AppColors.border
                : (isBilling || isOnHold)
                    ? AppColors.warning
                    : color.withValues(alpha: 0.4),
            width: (isBilling || isOnHold) ? 2 : 1.5,
          ),
          boxShadow: isDisabled
              ? null
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (isDisabled ? AppColors.textHint : color)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(iconData,
                    color: isDisabled ? AppColors.textHint : color, size: 18),
              ),
              const Spacer(),
              // ── Table Number ───────────────────────────────────────
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(table.tableNumber,
                    maxLines: 1,
                    style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDisabled
                            ? AppColors.textHint
                            : AppColors.textPrimary)),
              ),
              Text(table.section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppColors.textHint)),
              const SizedBox(height: 6),
              // ── Status Badge ───────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDisabled
                            ? AppColors.textHint.withValues(alpha: 0.1)
                            : color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 8,
                          color: isDisabled
                              ? AppColors.textHint
                              : color,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Row(
                    children: [
                      const Icon(Icons.people_outline_rounded,
                          size: 11, color: AppColors.textHint),
                      const SizedBox(width: 2),
                      Text('${table.capacity}',
                          style: GoogleFonts.outfit(
                              fontSize: 10, color: AppColors.textHint)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (isBilling || isOnHold) {
      card = card
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .tint(
              color: AppColors.warning.withValues(alpha: 0.04),
              duration: 900.ms);
    }

    return card;
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// Reservation Card
// ═══════════════════════════════════════════════════════════════════════════
class _ReservationCard extends StatelessWidget {
  final TableReservation reservation;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onNoShow;
  final VoidCallback onSeat;

  const _ReservationCard({
    required this.reservation,
    required this.canManage,
    required this.onEdit,
    required this.onCancel,
    required this.onNoShow,
    required this.onSeat,
  });

  Color get _statusColor {
    switch (reservation.status) {
      case 'confirmed':
        return AppColors.info;
      case 'seated':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'no_show':
        return AppColors.textSecondary;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPast = reservation.reservationTime.isBefore(DateTime.now()) &&
        !reservation.isSeated;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _statusColor.withValues(alpha: 0.12),
                  child: Text(
                    reservation.customerName.isNotEmpty
                        ? reservation.customerName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        color: _statusColor,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reservation.customerName,
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                      if (reservation.customerPhone != null)
                        Text(reservation.customerPhone!,
                            style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(reservation.status.toUpperCase(),
                      style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _statusColor,
                          letterSpacing: 0.5)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Details ──────────────────────────────────────────────
            Wrap(
              spacing: 16,
              children: [
                _InfoChip(
                    Icons.schedule_rounded,
                    DateFormat('hh:mm a').format(reservation.reservationTime),
                    isPast ? AppColors.error : AppColors.textSecondary),
                _InfoChip(
                    Icons.calendar_month_rounded,
                    DateFormat('MMM d').format(reservation.reservationTime),
                    AppColors.textSecondary),
                _InfoChip(Icons.people_outline_rounded,
                    '${reservation.guestCount} guests', AppColors.textSecondary),
              ],
            ),
            if (reservation.notes != null && reservation.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(reservation.notes!,
                  style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontStyle: FontStyle.italic)),
            ],
            // ── Actions ───────────────────────────────────────────────
            if (canManage &&
                !reservation.isCancelled &&
                !reservation.isNoShow) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (!reservation.isSeated) ...[
                    _SmallBtn(
                        'Seat',
                        AppColors.success,
                        Icons.chair_rounded,
                        onSeat),
                    const SizedBox(width: 8),
                    _SmallBtn(
                        'Edit',
                        AppColors.info,
                        Icons.edit_rounded,
                        onEdit),
                    const SizedBox(width: 8),
                    _SmallBtn(
                        'No Show',
                        AppColors.textSecondary,
                        Icons.person_off_rounded,
                        onNoShow),
                    const SizedBox(width: 8),
                    _SmallBtn(
                        'Cancel',
                        AppColors.error,
                        Icons.cancel_rounded,
                        onCancel),
                  ] else
                    Text('✓ Seated',
                        style: GoogleFonts.outfit(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper Widgets
// ═══════════════════════════════════════════════════════════════════════════
class _StatusBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatusBadge(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 2.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: GoogleFonts.outfit(
                  fontSize: 13, color: color, fontWeight: FontWeight.w800)),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;
  final String? subtitle;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = enabled ? color : AppColors.textHint;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: displayColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: displayColor, size: 18),
      ),
      title: Text(label,
          style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: enabled ? AppColors.textPrimary : AppColors.textSecondary)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppColors.textHint))
          : null,
      onTap: enabled ? onTap : null,
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onChanged;
  const _FilterChip(this.label, this.value, this.selected, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: 150.ms,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;

  const _FormField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style:
                GoogleFonts.outfit(fontSize: 11, color: color)),
      ],
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _SmallBtn(this.label, this.color, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
