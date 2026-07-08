// ============================================================
// KATIYA STATION RMS — BRANCH USERS (Manager)
// A branch manager fully manages the login accounts in their own
// branch: add, edit, block/unblock, reset password, and delete.
// Branch scoping is enforced server-side too (resolveBranchScope /
// assertCanManage) — this screen never lets a manager reach another
// branch or grant the super_admin role. The list stays live via the
// `user:changed` socket event (see realtime_sync.dart), so changes made
// on any device appear here without a manual refresh.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/reset_password_dialog.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final branchUsersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.users,
    queryParameters: {'branchId': profile!.branchId!, 'limit': '100'},
  );
  final data = response.data as Map<String, dynamic>;
  final list = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  list.sort((a, b) => (a['full_name'] as String? ?? '').compareTo(b['full_name'] as String? ?? ''));
  return list;
});

/// Roles a branch manager is allowed to assign. super_admin is intentionally
/// excluded — only a super admin can grant that role (enforced server-side).
const _assignableRoles = <String, String>{
  'branch_manager': 'Branch Manager',
  'cashier': 'Cashier',
  'waiter': 'Waiter',
  'kitchen': 'Kitchen',
  'inventory': 'Inventory',
  'accountant': 'Accountant',
};

const _roleColors = <String, Color>{
  'branch_manager': Color(0xFF42A5F5),
  'cashier': Color(0xFF66BB6A),
  'waiter': Color(0xFFFF7043),
  'kitchen': Color(0xFFFFCA28),
  'inventory': Color(0xFF26C6DA),
  'accountant': Color(0xFFEC407A),
};

const _roleLabels = <String, String>{
  'super_admin': 'Super Admin',
  'branch_manager': 'Branch Manager',
  'cashier': 'Cashier',
  'waiter': 'Waiter',
  'kitchen': 'Kitchen',
  'inventory': 'Inventory',
  'accountant': 'Accountant',
};

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _search = '';
  String? _busyUserId; // id of the user a block/delete request is in-flight for

  void _refresh() => ref.invalidate(branchUsersProvider);

  // ─────────────────────────────────────────────────────────
  //  ADD USER — always created inside the manager's own branch
  // ─────────────────────────────────────────────────────────
  Future<void> _showAddDialog() async {
    final profile = ref.read(authNotifierProvider).value;
    if (profile?.branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still loading your session — try again in a moment.')),
      );
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(branchId: profile!.branchId!),
    );
    if (created == true) _refresh();
  }

  Future<void> _showEditDialog(Map<String, dynamic> user) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(
        branchId: user['branch_id'] as String? ?? '',
        existing: user,
      ),
    );
    if (updated == true) _refresh();
  }

  // ─────────────────────────────────────────────────────────
  //  BLOCK / UNBLOCK — toggles is_active; a blocked user cannot log in
  // ─────────────────────────────────────────────────────────
  Future<void> _toggleActive(Map<String, dynamic> user) async {
    if (_busyUserId != null) return;
    final id = user['id'] as String;
    final isActive = user['is_active'] as bool? ?? true;
    final name = user['full_name'] as String? ?? 'this user';
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busyUserId = id);
    try {
      await ApiClient.instance.patch(ApiConstants.toggleUserActive(id));
      _refresh();
      messenger.showSnackBar(SnackBar(
        content: Text(isActive ? '$name has been blocked.' : '$name has been unblocked.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  // ─────────────────────────────────────────────────────────
  //  DELETE — permanent; operational history stays intact (SET NULL)
  // ─────────────────────────────────────────────────────────
  Future<void> _deleteUser(Map<String, dynamic> user) async {
    if (_busyUserId != null) return;
    final id = user['id'] as String;
    final name = user['full_name'] as String? ?? 'this user';

    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete User',
      message:
          'Permanently delete the account for "$name"? They will lose access immediately. '
          'Past bills, orders and reports they were involved in are kept. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busyUserId = id);
    try {
      await ApiClient.instance.delete(ApiConstants.userById(id));
      _refresh();
      messenger.showSnackBar(SnackBar(content: Text('$name deleted.'), backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(branchUsersProvider);
    final currentUserId = ref.watch(authNotifierProvider).value?.id;

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
              child: const Icon(Icons.manage_accounts,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Branch Users',
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
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Add User'),
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: Column(
        children: [
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
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (users) {
                final filtered = _search.isEmpty
                    ? users
                    : users.where((u) {
                        final name = (u['full_name'] as String? ?? '').toLowerCase();
                        final email = (u['email'] as String? ?? '').toLowerCase();
                        final role = (u['role'] as String? ?? '').toLowerCase();
                        return name.contains(_search) || email.contains(_search) || role.contains(_search);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text('No users found', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                  );
                }

                return ResponsiveContent(
                  alignment: Alignment.topLeft,
                  child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final user = filtered[i];
                    return _UserCard(
                      user: user,
                      isSelf: user['id'] == currentUserId,
                      isBusy: _busyUserId == user['id'],
                      onEdit: () => _showEditDialog(user),
                      onResetPassword: () => showResetPasswordDialog(
                        context,
                        userId: user['id'] as String,
                        userName: user['full_name'] as String? ?? '—',
                      ),
                      onToggleActive: () => _toggleActive(user),
                      onDelete: () => _deleteUser(user),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 30));
                  },
                ));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  USER CARD
// ═══════════════════════════════════════════════════════════════════════
class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isSelf;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.isSelf,
    required this.isBusy,
    required this.onEdit,
    required this.onResetPassword,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = user['full_name'] as String? ?? '—';
    final email = user['email'] as String? ?? '—';
    final role = user['role'] as String? ?? '—';
    final isActive = user['is_active'] as bool? ?? true;
    final roleColor = _roleColors[role] ?? AppColors.textSecondary;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: roleColor.withValues(alpha: 0.15),
          child: Text(initial,
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: roleColor)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
                if (isSelf) ...[
                  const SizedBox(width: 6),
                  _tag('YOU', AppColors.primary),
                ],
                if (!isActive) ...[
                  const SizedBox(width: 6),
                  _tag('BLOCKED', AppColors.error),
                ],
              ]),
              const SizedBox(height: 2),
              Text(email, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(_roleLabels[role] ?? role,
              style: GoogleFonts.outfit(fontSize: 10, color: roleColor, fontWeight: FontWeight.w600)),
        ),
        isBusy
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 20),
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      onEdit();
                      break;
                    case 'reset':
                      onResetPassword();
                      break;
                    case 'toggle':
                      onToggleActive();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_rounded, size: 18), title: Text('Edit')),
                  ),
                  const PopupMenuItem(
                    value: 'reset',
                    child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.lock_reset_rounded, size: 18), title: Text('Reset Password')),
                  ),
                  // A manager must not block or delete their own account —
                  // that would lock them out. Hidden for the current user.
                  if (!isSelf)
                    PopupMenuItem(
                      value: 'toggle',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(isActive ? Icons.block_rounded : Icons.check_circle_rounded, size: 18),
                        title: Text(isActive ? 'Block' : 'Unblock'),
                      ),
                    ),
                  if (!isSelf)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                        title: Text('Delete', style: TextStyle(color: AppColors.error)),
                      ),
                    ),
                ],
              ),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
      );
}

// ═══════════════════════════════════════════════════════════════════════
//  ADD / EDIT USER DIALOG
//  Reused for both flows — `existing == null` means create.
// ═══════════════════════════════════════════════════════════════════════
class _UserFormDialog extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? existing;
  const _UserFormDialog({required this.branchId, this.existing});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final _nameCtrl = TextEditingController(text: widget.existing?['full_name'] as String? ?? '');
  late final _emailCtrl = TextEditingController(text: widget.existing?['email'] as String? ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.existing?['phone'] as String? ?? '');
  final _passCtrl = TextEditingController();
  late String _role = () {
    final r = widget.existing?['role'] as String?;
    return _assignableRoles.containsKey(r) ? r! : 'waiter';
  }();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Full name is required');
      return;
    }
    if (!_isEdit) {
      if (!_validEmail(email)) {
        setState(() => _error = 'Enter a valid email address');
        return;
      }
      if (_passCtrl.text.length < 8) {
        setState(() => _error = 'Password must be at least 8 characters');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_isEdit) {
        await ApiClient.instance.patch(
          ApiConstants.userById(widget.existing!['id'] as String),
          data: {
            'fullName': name,
            'phone': phone.isEmpty ? null : phone,
            'role': _role,
          },
        );
      } else {
        await ApiClient.instance.post(
          ApiConstants.users,
          data: {
            'email': email,
            'password': _passCtrl.text,
            'fullName': name,
            'role': _role,
            'branchId': widget.branchId,
            if (phone.isNotEmpty) 'phone': phone,
          },
        );
      }
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
      title: Row(children: [
        Icon(_isEdit ? Icons.manage_accounts_rounded : Icons.person_add_rounded, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_isEdit ? 'Edit User' : 'Add User',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        ),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name *'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              enabled: !_isEdit, // email is the login identity; not editable here
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email *',
                helperText: _isEdit ? 'Email cannot be changed' : null,
              ),
            ),
            const SizedBox(height: 12),
            if (!_isEdit) ...[
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password *',
                  helperText: 'Minimum 8 characters',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Role'),
              onChanged: (v) => setState(() => _role = v!),
              items: _assignableRoles.entries
                  .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                  .toList(),
            ),
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
              : Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
