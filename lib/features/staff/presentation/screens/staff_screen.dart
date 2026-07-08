import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;
  bool _addingStaff = false;
  String? _loadingAttendanceStaffId;
  String? _deletingStaffId;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); _load(); }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    final profile = ref.read(authNotifierProvider).value;
    if (profile?.branchId == null) return;
    final response = await ApiClient.instance.get(
      ApiConstants.staff,
      queryParameters: {'branchId': profile!.branchId!},
    );
    final data = response.data as Map<String, dynamic>;
    final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? [])
        .where((s) => (s['status'] as String?) != 'terminated')
        .toList();
    rows.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    if (mounted) setState(() { _staff = rows; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
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
              child: const Icon(Icons.badge,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Staff Management',
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
            icon: _addingStaff
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Add Staff'),
            onPressed: _addingStaff ? null : () => _showAddDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Staff Members'), Tab(text: 'Salary')],
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // Staff list
          _loading
              ? Skeletonizer(
                  enabled: true,
                  effect: const ShimmerEffect(
                    baseColor: AppColors.surfaceVariant,
                    highlightColor: AppColors.surface,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 6,
                    itemBuilder: (_, i) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        const CircleAvatar(radius: 22, backgroundColor: AppColors.surfaceVariant),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(height: 14, width: 140, color: AppColors.surfaceVariant),
                          const SizedBox(height: 6),
                          Container(height: 11, width: 100, color: AppColors.surfaceVariant),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Container(height: 22, width: 60, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8))),
                          const SizedBox(height: 4),
                          Container(height: 11, width: 80, color: AppColors.surfaceVariant),
                        ]),
                      ]),
                    ),
                  ),
                )
              : _staff.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.badge_outlined, size: 64, color: AppColors.textHint),
                      const SizedBox(height: 16),
                      Text('No staff members added', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _addingStaff ? null : () => _showAddDialog(context),
                        child: const Text('Add First Staff'),
                      ),
                    ]))
                  : ResponsiveContent(child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _staff.length,
                      itemBuilder: (ctx, i) => _StaffCard(
                        staff: _staff[i],
                        isLoadingAttendance: _loadingAttendanceStaffId == _staff[i]['id'],
                        isDeleting: _deletingStaffId == _staff[i]['id'],
                        onViewAttendance: () => _showAttendanceHistory(context, _staff[i]),
                        onEdit: () => _showEditDialog(context, _staff[i]),
                        onDelete: () => _deleteStaff(context, _staff[i]),
                      ).animate().fadeIn(delay: Duration(milliseconds: i * 30)),
                    )),
          // Salary tab
          _SalaryView(staff: _staff, ref: ref),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  ADD STAFF — links a StaffMember to an existing user login
  //  (branch is always the manager's own branch; enforced server-side too)
  // ─────────────────────────────────────────────────────────
  Future<void> _showAddDialog(BuildContext context) async {
    if (_addingStaff) return;
    final profile = ref.read(authNotifierProvider).value;
    if (profile?.branchId == null) {
      // Your session is still (re)loading — e.g. right after a token
      // refresh. Silently no-op-ing here is what made this button look
      // broken; tell the user to try again instead.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still loading your session — try again in a moment.')),
      );
      return;
    }
    final branchId = profile!.branchId!;

    // Loading state lives on the button itself (spinner + disabled) rather
    // than as a separate dialog route — a "show a dialog, await a network
    // call, then Navigator.pop() it" dance is fragile with go_router: if
    // the router state changes underneath during the await (e.g. a token
    // refresh triggering a rebuild), the pop can hit the wrong route and
    // crash the whole navigator instead of just closing a spinner.
    setState(() => _addingStaff = true);

    List<Map<String, dynamic>> eligibleUsers = [];
    try {
      final response = await ApiClient.instance.get(
        ApiConstants.users,
        queryParameters: {'branchId': branchId},
      );
      final data = response.data as Map<String, dynamic>;
      final users = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
      final linkedUserIds = _staff.map((s) => s['user_id'] as String?).whereType<String>().toSet();
      eligibleUsers = users.where((u) => !linkedUserIds.contains(u['id'] as String)).toList();
    } catch (_) {
      // handled below via empty list
    }

    if (!mounted) return;
    setState(() => _addingStaff = false);
    if (!context.mounted) return;

    if (eligibleUsers.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Available Accounts'),
          content: Text(
            'Every user account in your branch is already linked to a staff record, or none exist yet. '
            'Ask your Super Admin to create a login for this person first — then come back here to link it.',
            style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AddStaffDialog(branchId: branchId, eligibleUsers: eligibleUsers),
    );
    if (added == true) _load();
  }

  // ─────────────────────────────────────────────────────────
  //  EDIT STAFF — update name, phone, role, salary
  // ─────────────────────────────────────────────────────────
  Future<void> _showEditDialog(BuildContext context, Map<String, dynamic> staff) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => _EditStaffDialog(staff: staff),
    );
    if (updated == true) _load();
  }

  // ─────────────────────────────────────────────────────────
  //  DELETE STAFF — soft-delete via status: 'terminated' so
  //  attendance & payroll history stay intact for reporting.
  // ─────────────────────────────────────────────────────────
  Future<void> _deleteStaff(BuildContext context, Map<String, dynamic> staff) async {
    if (_deletingStaffId != null) return;
    final staffId = staff['id'] as String;
    final staffName = staff['name'] as String;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Staff Member',
      message:
          'Remove "$staffName" from the active staff list? Their attendance and salary '
          'history will be preserved for reporting, and this can be undone by re-adding them.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _deletingStaffId = staffId);
    try {
      await ApiClient.instance.patch(
        ApiConstants.staffById(staffId),
        data: {'status': 'terminated'},
      );
      await _load();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingStaffId = null);
    }
  }

  // ─────────────────────────────────────────────────────────
  //  VIEW ATTENDANCE — manager-facing history for one staff member
  // ─────────────────────────────────────────────────────────
  Future<void> _showAttendanceHistory(BuildContext context, Map<String, dynamic> staff) async {
    if (_loadingAttendanceStaffId != null) return;
    final staffId = staff['id'] as String;
    final staffName = staff['name'] as String;

    setState(() => _loadingAttendanceStaffId = staffId);

    List<Map<String, dynamic>> records = [];
    String? error;
    try {
      final response = await ApiClient.instance.get(ApiConstants.attendanceByStaff(staffId));
      records = List<Map<String, dynamic>>.from(response.data as List? ?? []);
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    setState(() => _loadingAttendanceStaffId = null);
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$staffName — Attendance'),
        content: SizedBox(
          width: ctx.dialogWidth(380),
          child: error != null
              ? Text('Error: $error', style: const TextStyle(color: AppColors.error))
              : records.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No attendance recorded yet',
                            style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = records[i];
                          final date = DateTime.parse(r['date'] as String);
                          final clockIn = DateTime.parse(r['clock_in'] as String);
                          final clockOut = r['clock_out'] != null ? DateTime.parse(r['clock_out'] as String) : null;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(DateFormat('EEE, dd MMM yyyy').format(date),
                                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                      const SizedBox(height: 2),
                                      Text(
                                        'In: ${DateFormat('hh:mm a').format(clockIn)}'
                                        '${clockOut != null ? '  •  Out: ${DateFormat('hh:mm a').format(clockOut)}' : ''}',
                                        style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (clockOut != null ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    clockOut != null ? 'COMPLETE' : 'ONGOING',
                                    style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: clockOut != null ? AppColors.success : AppColors.warning),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ADD STAFF DIALOG
// ═══════════════════════════════════════════════════════════════════════
class _AddStaffDialog extends StatefulWidget {
  final String branchId;
  final List<Map<String, dynamic>> eligibleUsers;
  const _AddStaffDialog({required this.branchId, required this.eligibleUsers});

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _salaryCtrl = TextEditingController();
  String _role = 'waiter';
  Map<String, dynamic>? _selectedUser;
  bool _submitting = false;

  @override
  void dispose() {
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedUser == null) return;
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post(
        ApiConstants.staff,
        data: {
          'branchId': widget.branchId,
          'name': _selectedUser!['full_name'],
          'phone': _selectedUser!['phone'],
          'role': _role,
          'salary': double.tryParse(_salaryCtrl.text) ?? 0,
          'userId': _selectedUser!['id'],
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Staff Member'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick the login account this staff member will use — they\'ll be able to '
              'mark their own daily attendance from that account.',
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedUser?['id'] as String?,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'User Account (Email) *'),
              hint: const Text('Select a user'),
              items: widget.eligibleUsers
                  .map((u) => DropdownMenuItem<String>(
                        value: u['id'] as String,
                        child: Text('${u['full_name']} — ${u['email']}', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(
                () => _selectedUser = widget.eligibleUsers.firstWhere((u) => u['id'] == v),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              onChanged: (v) => setState(() => _role = v!),
              items: const [
                DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
                DropdownMenuItem(value: 'kitchen', child: Text('Kitchen Staff')),
                DropdownMenuItem(value: 'inventory', child: Text('Inventory Manager')),
                DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _salaryCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monthly Salary (NPR)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: (_selectedUser == null || _submitting) ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  EDIT STAFF DIALOG — updates name, phone, role, salary
// ═══════════════════════════════════════════════════════════════════════
class _EditStaffDialog extends StatefulWidget {
  final Map<String, dynamic> staff;
  const _EditStaffDialog({required this.staff});

  @override
  State<_EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends State<_EditStaffDialog> {
  late final _nameCtrl = TextEditingController(text: widget.staff['name'] as String? ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.staff['phone'] as String? ?? '');
  late final _salaryCtrl =
      TextEditingController(text: ((widget.staff['salary'] as num?)?.toString() ?? ''));
  late String _role = widget.staff['role'] as String? ?? 'waiter';
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.patch(
        ApiConstants.staffById(widget.staff['id'] as String),
        data: {
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          'role': _role,
          'salary': double.tryParse(_salaryCtrl.text) ?? 0,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Staff Member'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              onChanged: (v) => setState(() => _role = v!),
              items: const [
                DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
                DropdownMenuItem(value: 'kitchen', child: Text('Kitchen Staff')),
                DropdownMenuItem(value: 'inventory', child: Text('Inventory Manager')),
                DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _salaryCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Monthly Salary (NPR)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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

class _StaffCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final bool isLoadingAttendance;
  final bool isDeleting;
  final VoidCallback onViewAttendance;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _StaffCard({
    required this.staff,
    required this.isLoadingAttendance,
    required this.isDeleting,
    required this.onViewAttendance,
    required this.onEdit,
    required this.onDelete,
  });

  Color _roleColor(String? role) {
    switch (role) {
      case 'cashier': return AppColors.roleCashier;
      case 'kitchen': return AppColors.roleKitchen;
      case 'inventory': return AppColors.roleInventory;
      case 'accountant': return AppColors.warning;
      default: return AppColors.roleWaiter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = staff['role'] as String? ?? 'waiter';
    final color = _roleColor(role);
    final isLinked = staff['user_id'] != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text((staff['name'] as String).substring(0, 1).toUpperCase(),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(staff['name'] as String, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Row(children: [
            Text(staff['phone'] as String? ?? '—', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
            if (!isLinked) ...[
              const SizedBox(width: 8),
              const Icon(Icons.link_off_rounded, size: 12, color: AppColors.textHint),
              const SizedBox(width: 3),
              Text('No login linked', style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint)),
            ],
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(role.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          Text('NPR ${NumberFormat('#,##0').format((staff['salary'] as num?)?.toInt() ?? 0)}/mo',
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
        ]),
        if (isLinked)
          IconButton(
            icon: isLoadingAttendance
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fingerprint_rounded, size: 20, color: AppColors.primary),
            tooltip: 'View Attendance',
            onPressed: isLoadingAttendance ? null : onViewAttendance,
          ),
        isDeleting
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 20),
                onSelected: (val) {
                  if (val == 'edit') {
                    onEdit();
                  } else if (val == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
      ]),
    );
  }
}

class _SalaryView extends StatelessWidget {
  final List<Map<String, dynamic>> staff;
  final WidgetRef ref;
  const _SalaryView({required this.staff, required this.ref});

  @override
  Widget build(BuildContext context) {
    final total = staff.fold<double>(0, (s, m) => s + ((m['salary'] as num?)?.toDouble() ?? 0));
    return Column(
      children: [
        Container(
          color: AppColors.surface, padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.payments_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Monthly Salary Expense', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
              Text('NPR ${NumberFormat('#,##0.00').format(total)}',
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ]),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: staff.isEmpty
          ? Center(child: Text('No staff added', style: GoogleFonts.outfit(color: AppColors.textSecondary)))
          : ResponsiveContent(child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: staff.length,
              itemBuilder: (ctx, i) {
                final m = staff[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Expanded(child: Text(m['name'] as String, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                    Text('NPR ${NumberFormat('#,##0').format((m['salary'] as num?)?.toInt() ?? 0)}',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ]),
                );
              },
            ))),
      ],
    );
  }
}
