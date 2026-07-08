import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final auditLogsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.auditLogs,
    queryParameters: {
      if (profile.branchId != null) 'branchId': profile.branchId!,
      'limit': '100',
    },
  );
  final data = response.data as Map<String, dynamic>;
  final list = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  list.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
  return list.take(200).toList();
});

Color _actionColor(String action) {
  switch (action.toLowerCase()) {
    case 'create': return AppColors.success;
    case 'delete': return AppColors.error;
    case 'update': return AppColors.info;
    case 'refund': return AppColors.warning;
    case 'cancel': return AppColors.error;
    case 'login': return AppColors.primary;
    case 'logout': return AppColors.textSecondary;
    case 'credit': return AppColors.warning;
    default: return AppColors.textSecondary;
  }
}

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});
  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String _selectedAction = 'All';
  String _search = '';

  final List<String> _actionFilters = [
    'All', 'create', 'update', 'delete', 'login', 'logout', 'refund', 'cancel', 'credit',
  ];

  List<PlutoColumn> get _columns => [
    PlutoColumn(
      title: 'Time',
      field: 'time',
      type: PlutoColumnType.text(),
      width: 170,
      renderer: (ctx) => Text(
        ctx.cell.value as String,
        style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint),
      ),
    ),
    PlutoColumn(
      title: 'Action',
      field: 'action',
      type: PlutoColumnType.text(),
      width: 110,
      titleTextAlign: PlutoColumnTextAlign.center,
      textAlign: PlutoColumnTextAlign.center,
      renderer: (ctx) {
        final action = ctx.cell.value as String;
        final color = _actionColor(action);
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(action.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, color: color, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
        );
      },
    ),
    PlutoColumn(
      title: 'Module',
      field: 'module',
      type: PlutoColumnType.text(),
      width: 110,
      renderer: (ctx) => Text(
        ctx.cell.value as String,
        style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
      ),
    ),
    PlutoColumn(
      title: 'Description',
      field: 'description',
      type: PlutoColumnType.text(),
      width: 320,
      renderer: (ctx) => Tooltip(
        message: ctx.cell.value as String,
        child: Text(
          ctx.cell.value as String,
          style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textPrimary),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
    PlutoColumn(
      title: 'User',
      field: 'user',
      type: PlutoColumnType.text(),
      width: 150,
      renderer: (ctx) => Text(
        ctx.cell.value as String,
        style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
      ),
    ),
    PlutoColumn(
      title: 'Role',
      field: 'role',
      type: PlutoColumnType.text(),
      width: 110,
      titleTextAlign: PlutoColumnTextAlign.center,
      textAlign: PlutoColumnTextAlign.center,
      renderer: (ctx) {
        final role = ctx.cell.value as String;
        if (role.isEmpty) return const SizedBox();
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(role, style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ),
        );
      },
    ),
    PlutoColumn(
      title: 'Device',
      field: 'device',
      type: PlutoColumnType.text(),
      width: 120,
      renderer: (ctx) => Text(
        ctx.cell.value as String,
        style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint),
      ),
    ),
  ];

  List<PlutoRow> _buildRows(List<Map<String, dynamic>> logs) {
    return logs.map((log) {
      final createdAt = log['created_at'] != null
          ? DateFormat('dd MMM yy, HH:mm').format(DateTime.parse(log['created_at'] as String).toLocal())
          : '—';
      return PlutoRow(cells: {
        'time': PlutoCell(value: createdAt),
        'action': PlutoCell(value: (log['action'] as String? ?? '').toLowerCase()),
        'module': PlutoCell(value: log['module'] as String? ?? ''),
        'description': PlutoCell(value: log['description'] as String? ?? ''),
        'user': PlutoCell(value: log['user_name'] as String? ?? 'System'),
        'role': PlutoCell(value: log['user_role'] as String? ?? ''),
        'device': PlutoCell(value: log['device'] as String? ?? ''),
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(auditLogsProvider);

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
              child: const Icon(Icons.history,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Audit Logs',
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
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(auditLogsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by user, action, or description...',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          // Action filter chips
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _actionFilters.length,
              itemBuilder: (_, i) {
                final f = _actionFilters[i];
                final isSelected = f == _selectedAction;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAction = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      f == 'All' ? 'All' : f.toUpperCase(),
                      style: GoogleFonts.outfit(fontSize: 12, color: isSelected ? AppColors.primary : AppColors.textSecondary, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: logsAsync.when(
              loading: () => Skeletonizer(
                enabled: true,
                effect: const ShimmerEffect(
                  baseColor: AppColors.surfaceVariant,
                  highlightColor: AppColors.surface,
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: 10,
                  itemBuilder: (_, i) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(height: 12, width: 200, color: AppColors.surfaceVariant),
                        const SizedBox(height: 6),
                        Container(height: 11, width: 300, color: AppColors.surfaceVariant),
                        const SizedBox(height: 6),
                        Container(height: 10, width: 150, color: AppColors.surfaceVariant),
                      ])),
                    ]),
                  ),
                ),
              ),
              error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
              data: (logs) {
                var filtered = logs.where((log) {
                  final action = (log['action'] as String? ?? '').toLowerCase();
                  final user = (log['user_name'] as String? ?? '').toLowerCase();
                  final desc = (log['description'] as String? ?? '').toLowerCase();
                  if (_selectedAction != 'All' && !action.contains(_selectedAction.toLowerCase())) return false;
                  if (_search.isNotEmpty && !action.contains(_search) && !user.contains(_search) && !desc.contains(_search)) return false;
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.history_rounded, size: 64, color: AppColors.textHint),
                      const SizedBox(height: 16),
                      Text('No audit logs found', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                    ]),
                  );
                }

                return PlutoGrid(
                  columns: _columns,
                  rows: _buildRows(filtered),
                  onLoaded: (e) => e.stateManager.setShowColumnFilter(true),
                  configuration: PlutoGridConfiguration(
                    style: PlutoGridStyleConfig(
                      gridBackgroundColor: AppColors.background,
                      rowColor: AppColors.surface,
                      oddRowColor: AppColors.surfaceVariant,
                      activatedColor: AppColors.primary.withValues(alpha: 0.08),
                      activatedBorderColor: AppColors.primary,
                      gridBorderColor: AppColors.border,
                      columnTextStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      cellTextStyle: GoogleFonts.outfit(fontSize: 12, color: AppColors.textPrimary),
                      columnHeight: 46,
                      rowHeight: 50,
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
}
