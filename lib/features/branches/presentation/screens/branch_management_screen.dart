import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final branchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.get(ApiConstants.branches);
  final rows = response.data as List<dynamic>;
  final list = List<Map<String, dynamic>>.from(rows);
  list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  return list;
});

class BranchManagementScreen extends ConsumerWidget {
  const BranchManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(branchesProvider);
    final profile = ref.watch(authNotifierProvider).value;

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
              child: const Icon(Icons.store,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Branch Management',
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
          if (profile?.isSuperAdmin == true || profile?.isBranchManager == true)
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Branch'),
              onPressed: () => _showBranchDialog(context, ref, null),
            ),
        ],
      ),
      body: branchesAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (branches) {
          if (branches.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.store_outlined, size: 64, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('No branches configured',
                      style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _showBranchDialog(context, ref, null),
                    child: const Text('Add First Branch'),
                  ),
                ],
              ),
            );
          }

          return ResponsiveContent(
            alignment: Alignment.topLeft,
            child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: branches.length,
            itemBuilder: (ctx, i) => _BranchCard(
              branch: branches[i],
              canEdit: profile?.isSuperAdmin == true || profile?.isBranchManager == true,
              onEdit: () => _showBranchDialog(context, ref, branches[i]),
              onDelete: () => _deleteBranch(context, ref, branches[i]['id'] as String),
              onToggle: () => _toggleActive(ref, branches[i]),
            ).animate().fadeIn(delay: Duration(milliseconds: i * 50)).slideY(begin: 0.1),
          ));
        },
      ),
    );
  }

  void _showBranchDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic>? existing) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
    final addressCtrl =
        TextEditingController(text: existing?['address'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] as String? ?? '');
    final emailCtrl = TextEditingController(text: existing?['email'] as String? ?? '');
    final cityCtrl = TextEditingController(text: existing?['city'] as String? ?? '');
    final taxRegCtrl =
        TextEditingController(text: existing?['tax_reg_number'] as String? ?? '');
    final vatRateCtrl = TextEditingController(
        text: ((existing?['vat_rate'] as num?)?.toString()) ?? '13');
    final serviceChargeCtrl = TextEditingController(
        text: ((existing?['service_charge_rate'] as num?)?.toString()) ?? '10');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Branch' : 'Add New Branch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Branch Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cityCtrl,
                decoration: const InputDecoration(labelText: 'City / Location'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Full Address'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Contact Phone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: taxRegCtrl,
                decoration: const InputDecoration(labelText: 'PAN / Tax Registration Number'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: vatRateCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'VAT Rate (%)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: serviceChargeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Service Charge (%)'),
                  ),
                ),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final messenger = ScaffoldMessenger.of(context);

              final payload = {
                'name': nameCtrl.text.trim(),
                'city': cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
                'address':
                    addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                'taxRegNumber':
                    taxRegCtrl.text.trim().isEmpty ? null : taxRegCtrl.text.trim(),
                'vatRate': double.tryParse(vatRateCtrl.text) ?? 13.0,
                'serviceChargeRate':
                    double.tryParse(serviceChargeCtrl.text) ?? 10.0,
              };

              try {
                if (existing != null) {
                  await ApiClient.instance.patch(
                    ApiConstants.branchById(existing['id'] as String),
                    data: payload,
                  );
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Branch updated successfully'),
                    backgroundColor: AppColors.success,
                  ));
                } else {
                  await ApiClient.instance.post(ApiConstants.branches, data: payload);
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Branch added successfully'),
                    backgroundColor: AppColors.success,
                  ));
                }

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                ref.invalidate(branchesProvider);
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                  content: Text('Failed to save branch: $e'),
                  backgroundColor: AppColors.error,
                ));
              }
            },
            child: Text(isEdit ? 'Update' : 'Add Branch'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBranch(BuildContext context, WidgetRef ref, String id) async {
    // Capture messenger before async gap
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Branch',
      message:
          'This will permanently delete the branch. All data linked to this branch will remain but the branch will be removed.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;

    try {
      await ApiClient.instance.delete(ApiConstants.branchById(id));
      ref.invalidate(branchesProvider);
      messenger.showSnackBar(const SnackBar(
        content: Text('Branch deleted successfully'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Failed to delete branch: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _toggleActive(WidgetRef ref, Map<String, dynamic> branch) async {
    final isActive = branch['is_active'] as bool? ?? true;
    try {
      await ApiClient.instance.patch(
        ApiConstants.branchById(branch['id'] as String),
        data: {'isActive': !isActive},
      );
      ref.invalidate(branchesProvider);
    } catch (e) {
      // Quietly log or ignore
    }
  }
}

// ── Branch Card ──
class _BranchCard extends StatelessWidget {
  final Map<String, dynamic> branch;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _BranchCard({
    required this.branch,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = branch['is_active'] as bool? ?? true;
    final name = branch['name'] as String? ?? 'Branch';
    final city = branch['city'] as String?;
    final address = branch['address'] as String?;
    final phone = branch['phone'] as String?;
    final vat = (branch['vat_rate'] as num?)?.toDouble() ?? 13.0;
    final sc = (branch['service_charge_rate'] as num?)?.toDouble() ?? 10.0;
    final taxReg = branch['tax_reg_number'] as String?;
    final createdAt = branch['created_at'] != null
        ? DateFormat('dd MMM yyyy')
            .format(DateTime.parse(branch['created_at'] as String))
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.25)
                : AppColors.border),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.06)
                  : AppColors.surfaceVariant,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.store_rounded, color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      if (city != null)
                        Text(city,
                            style: GoogleFonts.outfit(
                                fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isActive ? AppColors.success : AppColors.error)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? 'ACTIVE' : 'INACTIVE',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isActive ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ),
                    if (canEdit)
                      PopupMenuButton<String>(
                        child: const Icon(Icons.more_vert_rounded,
                            color: AppColors.textSecondary, size: 18),
                        onSelected: (s) {
                          if (s == 'edit') onEdit();
                          if (s == 'toggle') onToggle();
                          if (s == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                              value: 'toggle',
                              child: Text(isActive ? 'Deactivate' : 'Activate')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (address != null)
                  _InfoRow(Icons.location_on_outlined, address),
                if (phone != null) _InfoRow(Icons.phone_outlined, phone),
                if (taxReg != null) _InfoRow(Icons.receipt_outlined, 'PAN: $taxReg'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _RateChip('VAT ${vat.toInt()}%', AppColors.info),
                    const SizedBox(width: 8),
                    _RateChip('SC ${sc.toInt()}%', AppColors.warning),
                    const Spacer(),
                    Text('Since $createdAt',
                        style: GoogleFonts.outfit(
                            fontSize: 11, color: AppColors.textHint)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textHint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _RateChip extends StatelessWidget {
  final String label;
  final Color color;
  const _RateChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label,
          style: GoogleFonts.outfit(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}
