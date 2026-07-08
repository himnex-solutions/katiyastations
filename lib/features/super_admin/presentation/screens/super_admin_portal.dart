import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/widgets/reset_password_dialog.dart';

final allUsersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.get(
    ApiConstants.users,
    queryParameters: {'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final list = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  list.sort((a, b) {
    final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
    final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.now();
    return bTime.compareTo(aTime);
  });
  return list;
});

// Branches for dropdowns
final allBranchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.get(ApiConstants.branches);
  final rows = response.data as List<dynamic>;
  final list = List<Map<String, dynamic>>.from(rows);
  list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  return list;
});

// ── Super Admin Portal ─────────────────────────────────────────
class SuperAdminPortal extends ConsumerStatefulWidget {
  const SuperAdminPortal({super.key});
  @override
  ConsumerState<SuperAdminPortal> createState() => _SuperAdminPortalState();
}

class _SuperAdminPortalState extends ConsumerState<SuperAdminPortal>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.verified_user,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Super Admin Portal',
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text('Katiya Station — Developer Console',
                  style: GoogleFonts.outfit(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ]),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'User Accounts'),
            Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'Access Logs'),
            Tab(icon: Icon(Icons.restaurant_menu_rounded, size: 18), text: 'Menu Import'),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Create User'),
            onPressed: () => _showCreateUserDialog(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ── Tab 1: Users List ────────────────────────────────
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search by name, email or role...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
            ),
            Expanded(
              child: usersAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (users) {
                  final filtered = _search.isEmpty
                      ? users
                      : users.where((u) {
                          final name = (u['full_name'] as String? ?? '').toLowerCase();
                          final email = (u['email'] as String? ?? '').toLowerCase();
                          final role = (u['role'] as String? ?? '').toLowerCase();
                          return name.contains(_search) ||
                              email.contains(_search) ||
                              role.contains(_search);
                        }).toList();

                  return ResponsiveContent(child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _UserCard(
                      user: filtered[i],
                      onBlock: () => _toggleBlock(filtered[i]),
                      onEdit: () => _showEditUserDialog(context, filtered[i]),
                      onResetPassword: () => showResetPasswordDialog(
                        context,
                        userId: filtered[i]['id'] as String,
                        userName: filtered[i]['full_name'] as String? ?? 'this user',
                      ),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 40)),
                  ));
                },
              ),
            ),
          ]),

          // ── Tab 2: Access Logs ───────────────────────────────
          const _AccessLogsTab(),

          // ── Tab 3: Menu Import ───────────────────────────────
          const _MenuImportTab(),
        ],
      ),
    );
  }

  Future<void> _toggleBlock(Map<String, dynamic> user) async {
    final isActive = user['is_active'] as bool? ?? true;
    final name = user['full_name'] as String? ?? 'this user';
    final action = isActive ? 'Block' : 'Unblock';

    // Capture messenger before async gap
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showConfirmDialog(
      context,
      title: '$action Account',
      message:
          '${isActive ? 'This will prevent' : 'This will restore'} $name\'s ability to log in.',
      confirmLabel: action,
      confirmColor: isActive ? AppColors.error : AppColors.success,
      icon: isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
    );
    if (!confirmed) return;
    try {
      await ApiClient.instance.patch(ApiConstants.toggleUserActive(user['id'] as String));
      ref.invalidate(allUsersProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('$name has been ${isActive ? 'blocked' : 'unblocked'}.'),
        backgroundColor: isActive ? AppColors.error : AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
  }

  void _showCreateUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'cashier';
    String? selectedBranchId;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final branchesAsync = ref.watch(allBranchesProvider);
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.person_add_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('Create User Account',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ]),
          content: SizedBox(
            width: ctx.dialogWidth(400),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Full Name *', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email Address *', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setS(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                      labelText: 'Role *', prefixIcon: Icon(Icons.badge_outlined)),
                  items: const [
                    DropdownMenuItem(value: 'branch_manager', child: Text('Branch Manager')),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                    DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
                    DropdownMenuItem(value: 'kitchen', child: Text('Kitchen Staff')),
                    DropdownMenuItem(value: 'inventory', child: Text('Inventory Manager')),
                    DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
                  ],
                  onChanged: (v) => setS(() => selectedRole = v ?? 'cashier'),
                ),
                const SizedBox(height: 12),
                branchesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox(),
                  data: (branches) => DropdownButtonFormField<String>(
                    initialValue: selectedBranchId,
                    decoration: const InputDecoration(
                        labelText: 'Assign Branch', prefixIcon: Icon(Icons.store_outlined)),
                    hint: const Text('Select branch'),
                    items: branches.map((b) => DropdownMenuItem<String>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String),
                        )).toList(),
                    onChanged: (v) => setS(() => selectedBranchId = v),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Create Account'),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty ||
                    emailCtrl.text.trim().isEmpty ||
                    passCtrl.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Fill all fields. Password min 6 chars.')));
                  return;
                }
                Navigator.pop(ctx);
                await _createUser(
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  password: passCtrl.text,
                  role: selectedRole,
                  branchId: selectedBranchId,
                );
              },
            ),
          ],
        );
      }),
    );
  }

  Future<void> _createUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? branchId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient.instance.post(
        ApiConstants.users,
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'fullName': name,
          'role': role,
          if (branchId != null) 'branchId': branchId,
        },
      );

      ref.invalidate(allUsersProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('✓ Account created for $name ($email)'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
  }

  void _showEditUserDialog(BuildContext context, Map<String, dynamic> user) {
    final nameCtrl = TextEditingController(text: user['full_name'] as String? ?? '');
    String selectedRole = user['role'] as String? ?? 'cashier';
    String? selectedBranchId = user['branch_id'] as String?;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final branchesAsync = ref.watch(allBranchesProvider);
        return AlertDialog(
          title: Text('Edit — ${user['full_name']}',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: ctx.dialogWidth(380),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'branch_manager', child: Text('Branch Manager')),
                  DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                  DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
                  DropdownMenuItem(value: 'kitchen', child: Text('Kitchen')),
                  DropdownMenuItem(value: 'inventory', child: Text('Inventory')),
                  DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
                ],
                onChanged: (v) => setS(() => selectedRole = v ?? selectedRole),
              ),
              const SizedBox(height: 12),
              branchesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox(),
                data: (branches) => DropdownButtonFormField<String>(
                  initialValue: selectedBranchId,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  hint: const Text('Select branch'),
                  items: branches.map((b) => DropdownMenuItem<String>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String),
                      )).toList(),
                  onChanged: (v) => setS(() => selectedBranchId = v),
                ),
              ),
            ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                try {
                  await ApiClient.instance.patch(
                    ApiConstants.userById(user['id'] as String),
                    data: {
                      'role': selectedRole,
                      if (selectedBranchId != null) 'branchId': selectedBranchId,
                      'fullName': nameCtrl.text.trim(),
                    },
                  );
                  ref.invalidate(allUsersProvider);
                  messenger.showSnackBar(const SnackBar(
                      content: Text('User updated successfully'),
                      backgroundColor: AppColors.success));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(
                      content: Text('Error: $e'), backgroundColor: AppColors.error));
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      }),
    );
  }
}

// ── User Card ──────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onBlock;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;

  const _UserCard({
    required this.user,
    required this.onBlock,
    required this.onEdit,
    required this.onResetPassword,
  });

  static const _roleColors = {
    'super_admin': Color(0xFFE040FB),
    'branch_manager': Color(0xFF42A5F5),
    'cashier': Color(0xFF66BB6A),
    'waiter': Color(0xFFFF7043),
    'kitchen': Color(0xFFFFCA28),
    'inventory': Color(0xFF26C6DA),
    'accountant': Color(0xFFEC407A),
  };

  static const _roleLabels = {
    'super_admin': 'Super Admin',
    'branch_manager': 'Branch Manager',
    'cashier': 'Cashier',
    'waiter': 'Waiter',
    'kitchen': 'Kitchen',
    'inventory': 'Inventory',
    'accountant': 'Accountant',
  };

  @override
  Widget build(BuildContext context) {
    final isActive = user['is_active'] as bool? ?? true;
    final name = user['full_name'] as String? ?? '—';
    final email = user['email'] as String? ?? '—';
    final role = user['role'] as String? ?? '—';
    final branch = user['branch_name'] as String? ?? 'No branch';
    final roleColor = _roleColors[role] ?? AppColors.textSecondary;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppColors.border
              : AppColors.error.withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Stack(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: roleColor.withValues(alpha: 0.15),
            child: Text(initial,
                style: GoogleFonts.outfit(
                    fontSize: 18, fontWeight: FontWeight.w700, color: roleColor)),
          ),
          if (!isActive)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 2)),
              ),
            ),
        ]),
        title: Row(children: [
          Expanded(
            child: Text(name,
                style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.textPrimary : AppColors.textHint,
                    decoration: isActive ? null : TextDecoration.lineThrough)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _roleLabels[role] ?? role,
              style: GoogleFonts.outfit(
                  fontSize: 10, color: roleColor, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 2),
          Text(email,
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          Row(children: [
            const Icon(Icons.store_outlined, size: 12, color: AppColors.textHint),
            const SizedBox(width: 4),
            Text(branch,
                style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textHint)),
            if (!isActive) ...[
              const SizedBox(width: 8),
              const Icon(Icons.block_rounded, size: 12, color: AppColors.error),
              const SizedBox(width: 2),
              Text('BLOCKED',
                  style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: AppColors.error,
                      fontWeight: FontWeight.w700)),
            ],
          ]),
        ]),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
          onSelected: (s) {
            if (s == 'edit') onEdit();
            if (s == 'block') onBlock();
            if (s == 'reset_password') onResetPassword();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('Edit User'),
                ])),
            const PopupMenuItem(
                value: 'reset_password',
                child: Row(children: [
                  Icon(Icons.lock_reset_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('Reset Password'),
                ])),
            PopupMenuItem(
              value: 'block',
              child: Row(children: [
                Icon(
                    isActive ? Icons.block_rounded : Icons.check_circle_outline,
                    size: 16,
                    color: isActive ? AppColors.error : AppColors.success),
                const SizedBox(width: 8),
                Text(isActive ? 'Block Login' : 'Restore Access',
                    style: TextStyle(
                        color: isActive ? AppColors.error : AppColors.success)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Access Logs Tab (backed by the audit trail, filtered to user actions) ──
final _accessLogsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.get(
    ApiConstants.auditLogs,
    queryParameters: {'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  final list = rows.where((log) => log['table_name'] == 'users').toList();
  list.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
  return list.take(100).toList();
});

class _AccessLogsTab extends ConsumerWidget {
  const _AccessLogsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(_accessLogsProvider);
    final usersAsync = ref.watch(allUsersProvider);
    return logsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (logs) {
        if (logs.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.history_rounded, size: 56, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text('No access logs yet',
                  style: GoogleFonts.outfit(color: AppColors.textSecondary)),
            ]),
          );
        }
        final users = usersAsync.value ?? [];
        return ResponsiveContent(child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          itemBuilder: (_, i) {
            final log = logs[i];
            final action = log['action'] as String? ?? '—';
            final performer = log['user_name'] as String? ?? 'System';
            final targetUser = users.where((u) => u['id'] == log['row_id']).firstOrNull;
            final target = targetUser?['full_name'] as String? ?? '—';
            final at = log['created_at'] != null
                ? DateTime.parse(log['created_at'] as String).toLocal()
                : null;

            final (color, icon) = switch (action) {
              'created'      => (AppColors.success, Icons.person_add_rounded),
              'blocked'      => (AppColors.error, Icons.block_rounded),
              'unblocked'    => (AppColors.success, Icons.check_circle_rounded),
              'role_changed' => (AppColors.info, Icons.badge_rounded),
              'deleted'      => (AppColors.error, Icons.delete_rounded),
              _              => (AppColors.textSecondary, Icons.info_rounded),
            };

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(action.replaceAll('_', ' ').toUpperCase(),
                        style: GoogleFonts.outfit(
                            fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                    Text('By: $performer | Target: $target',
                        style: GoogleFonts.outfit(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                ),
                if (at != null)
                  Text(
                    '${at.day}/${at.month} ${at.hour}:${at.minute.toString().padLeft(2, '0')}',
                    style: GoogleFonts.outfit(
                        fontSize: 11, color: AppColors.textHint),
                  ),
              ]),
            ).animate().fadeIn(delay: Duration(milliseconds: i * 20));
          },
        ));
      },
    );
  }
}

class _MenuImportTab extends ConsumerStatefulWidget {
  const _MenuImportTab();

  @override
  ConsumerState<_MenuImportTab> createState() => _MenuImportTabState();
}

class _MenuImportTabState extends ConsumerState<_MenuImportTab> {
  String? _selectedBranchId;
  String? _fileName;
  Uint8List? _fileBytes;
  bool _isLoading = false;

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xml'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() {
        _fileName = file.name;
        _fileBytes = file.bytes;
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error picking file: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _startImport() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_selectedBranchId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please select a branch first.'), backgroundColor: AppColors.warning),
      );
      return;
    }
    if (_fileBytes == null || _fileName == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please select an Excel or XML file to import.'), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> importedItems = [];

      final lowerName = _fileName!.toLowerCase();
      if (lowerName.endsWith('.xlsx')) {
        importedItems = _parseExcel(_fileBytes!);
      } else if (lowerName.endsWith('.xml')) {
        final xmlText = utf8.decode(_fileBytes!);
        importedItems = _parseXml(xmlText);
      } else {
        throw Exception('Unsupported file format. Please upload .xlsx or .xml file.');
      }

      if (importedItems.isEmpty) {
        throw Exception('No valid menu items found in the file.');
      }

      final branchId = _selectedBranchId!;
      final catsResponse = await ApiClient.instance.get(
        ApiConstants.menuCategories,
        queryParameters: {'branchId': branchId},
      );
      final catRows = List<Map<String, dynamic>>.from(catsResponse.data as List? ?? []);
      final existingCats = {for (var r in catRows) (r['name'] as String).toLowerCase(): r['id'] as String};

      final neededCategories = importedItems.map((item) => item['categoryName'] as String).toSet();
      final Map<String, String> categoryNameToId = {};

      for (final catName in neededCategories) {
        final key = catName.toLowerCase();
        if (existingCats.containsKey(key)) {
          categoryNameToId[catName] = existingCats[key]!;
        } else {
          final firstItemOfType = importedItems.firstWhere((item) => (item['categoryName'] as String).toLowerCase() == key, orElse: () => {'type': 'food'});
          final catType = firstItemOfType['type'] ?? 'food';

          final created = await ApiClient.instance.post(
            ApiConstants.menuCategories,
            data: {'branchId': branchId, 'name': catName, 'type': catType},
          );
          final newId = (created.data as Map<String, dynamic>)['id'] as String;
          existingCats[key] = newId;
          categoryNameToId[catName] = newId;
        }
      }

      for (final item in importedItems) {
        await ApiClient.instance.post(
          ApiConstants.menuItems,
          data: {
            'branchId': branchId,
            'categoryId': categoryNameToId[item['categoryName']],
            'name': item['name'],
            'price': item['price'],
            'description': item['description'],
            'imageUrl': item['image_url'],
            'type': item['type'],
            'isAvailable': item['is_available'] ?? true,
          },
        );
      }

      setState(() {
        _fileName = null;
        _fileBytes = null;
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('✓ Successfully imported ${importedItems.length} items across ${neededCategories.length} categories!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _parseExcel(Uint8List fileBytes) {
    final excel = Excel.decodeBytes(fileBytes);
    final items = <Map<String, dynamic>>[];
    
    String getVal(dynamic cell) {
      if (cell == null) return '';
      final v = cell.value;
      if (v == null) return '';
      return v.toString().trim();
    }

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;
      if (sheet.maxRows <= 1) continue;

      final headers = sheet.rows.first.map((c) => getVal(c).toLowerCase()).toList();
      final catIdx = headers.indexOf('category');
      final nameIdx = headers.indexOf('name');
      final priceIdx = headers.indexOf('price');
      final descIdx = headers.indexOf('description');
      final imgIdx = headers.indexOf('image url');
      final typeIdx = headers.indexOf('type');

      if (nameIdx == -1 || priceIdx == -1 || catIdx == -1) {
        throw Exception('Excel sheet "$table" must contain "Category", "Name", and "Price" columns.');
      }

      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;
        final name = nameIdx < row.length ? getVal(row[nameIdx]) : '';
        final priceStr = priceIdx < row.length ? getVal(row[priceIdx]) : '';
        final category = catIdx < row.length ? getVal(row[catIdx]) : '';

        if (name.isEmpty || priceStr.isEmpty || category.isEmpty) continue;

        final price = double.tryParse(priceStr) ?? 0.0;
        final desc = descIdx != -1 && descIdx < row.length ? getVal(row[descIdx]) : '';
        final imgUrl = imgIdx != -1 && imgIdx < row.length ? getVal(row[imgIdx]) : '';
        final type = typeIdx != -1 && typeIdx < row.length ? getVal(row[typeIdx]).toLowerCase() : 'food';

        items.add({
          'categoryName': category,
          'name': name,
          'price': price,
          'description': desc.isEmpty ? null : desc,
          'image_url': imgUrl.isEmpty ? null : imgUrl,
          'type': ['food', 'drink', 'bar'].contains(type) ? type : 'food',
          'is_available': true,
        });
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _parseXml(String xmlText) {
    final items = <Map<String, dynamic>>[];
    final itemRegex = RegExp(r'<item>([\s\S]*?)<\/item>', caseSensitive: false);
    final matches = itemRegex.allMatches(xmlText);
    
    for (final match in matches) {
      final itemContent = match.group(1) ?? '';
      
      String extractTag(String tag) {
        final tagRegex = RegExp('<$tag>([\\s\\S]*?)<\\/$tag>', caseSensitive: false);
        return tagRegex.firstMatch(itemContent)?.group(1)?.trim() ?? '';
      }
      
      final category = extractTag('category');
      final name = extractTag('name');
      final priceStr = extractTag('price');
      final description = extractTag('description');
      
      var imageUrl = extractTag('imageUrl');
      if (imageUrl.isEmpty) {
        imageUrl = extractTag('image_url');
      }
      
      var isAvailableStr = extractTag('isAvailable');
      if (isAvailableStr.isEmpty) {
        isAvailableStr = extractTag('is_available');
      }
      
      final type = extractTag('type').toLowerCase();

      if (name.isNotEmpty && priceStr.isNotEmpty && category.isNotEmpty) {
        final price = double.tryParse(priceStr) ?? 0.0;
        items.add({
          'categoryName': category,
          'name': name,
          'price': price,
          'description': description.isEmpty ? null : description,
          'image_url': imageUrl.isEmpty ? null : imageUrl,
          'type': ['food', 'drink', 'bar'].contains(type) ? type : 'food',
          'is_available': isAvailableStr.toLowerCase() != 'false',
        });
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(allBranchesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 550),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.upload_file_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bulk Import Menu',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Import categories and items from Excel (.xlsx) or XML (.xml)',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                
                Text(
                  'Select Target Branch',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                branchesAsync.when(
                  loading: () => const LinearProgressIndicator(color: AppColors.primary),
                  error: (e, _) => Text('Error loading branches: $e', style: const TextStyle(color: AppColors.error)),
                  data: (branches) => DropdownButtonFormField<String>(
                    initialValue: _selectedBranchId,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.store_outlined, size: 20),
                      hintText: 'Choose branch to import menu into',
                    ),
                    items: branches.map((b) => DropdownMenuItem<String>(
                      value: b['id'] as String,
                      child: Text(b['name'] as String),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedBranchId = v),
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Upload Menu File',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickFile,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _fileName != null ? AppColors.success : AppColors.border,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _fileName != null 
                            ? (_fileName!.endsWith('.xlsx') ? Icons.table_view_rounded : Icons.code_rounded)
                            : Icons.cloud_upload_outlined,
                          color: _fileName != null ? AppColors.success : AppColors.textHint,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _fileName ?? 'Click to select file',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: _fileName != null ? FontWeight.w600 : FontWeight.w400,
                            color: _fileName != null ? AppColors.textPrimary : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fileName != null ? 'File loaded successfully' : 'Supports Excel (.xlsx) & XML (.xml)',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isLoading ? null : _startImport,
                    child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Start Import Process',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
