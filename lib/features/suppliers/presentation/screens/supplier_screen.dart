import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:google_fonts/google_fonts.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final suppliersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.suppliers,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final data = response.data as Map<String, dynamic>;
  final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  rows.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  return rows;
});

class SupplierScreen extends ConsumerStatefulWidget {
  const SupplierScreen({super.key});
  @override
  ConsumerState<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends ConsumerState<SupplierScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);

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
              child: const Icon(Icons.local_shipping,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Suppliers',
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
            label: const Text('Add Supplier'),
            onPressed: () => _showSupplierDialog(context, null),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search suppliers...',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: suppliersAsync.when(
              loading: () => Skeletonizer(
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
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                    child: ListTile(
                      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10))),
                      title: Container(height: 14, width: 140, color: AppColors.surfaceVariant),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(height: 11, width: 100, color: AppColors.surfaceVariant),
                          const SizedBox(height: 4),
                          Container(height: 11, width: 80, color: AppColors.surfaceVariant),
                        ]),
                      ),
                      trailing: Container(width: 24, height: 24, color: AppColors.surfaceVariant),
                    ),
                  ),
                ),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (suppliers) {
                final filtered = _search.isEmpty
                    ? suppliers
                    : suppliers.where((s) {
                        final name = (s['name'] as String? ?? '').toLowerCase();
                        final contact = (s['contact_person'] as String? ?? '').toLowerCase();
                        final phone = (s['phone'] as String? ?? '').toLowerCase();
                        return name.contains(_search) ||
                            contact.contains(_search) ||
                            phone.contains(_search);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_shipping_outlined,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text(
                          _search.isEmpty ? 'No suppliers added yet' : 'No suppliers found',
                          style: GoogleFonts.outfit(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        if (_search.isEmpty)
                          ElevatedButton(
                            onPressed: () => _showSupplierDialog(context, null),
                            child: const Text('Add First Supplier'),
                          ),
                      ],
                    ),
                  );
                }

                return ResponsiveContent(child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _SupplierCard(
                    supplier: filtered[i],
                    onEdit: () => _showSupplierDialog(context, filtered[i]),
                    onDelete: () => _deleteSupplier(filtered[i]['id'] as String),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 30)),
                ));
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSupplierDialog(BuildContext context, Map<String, dynamic>? existing) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
    final contactCtrl =
        TextEditingController(text: existing?['contact_person'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] as String? ?? '');
    final emailCtrl = TextEditingController(text: existing?['email'] as String? ?? '');
    final addressCtrl =
        TextEditingController(text: existing?['address'] as String? ?? '');
    final categoryCtrl =
        TextEditingController(text: existing?['category'] as String? ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes'] as String? ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Supplier' : 'Add Supplier'),
        content: SizedBox(
          width: context.dialogWidth(440),
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Supplier / Company Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contactCtrl,
                decoration: const InputDecoration(labelText: 'Contact Person'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryCtrl,
                decoration:
                    const InputDecoration(labelText: 'Category (e.g. Vegetables, Meat)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final profile = ref.read(authNotifierProvider).value;

              final payload = {
                'name': nameCtrl.text.trim(),
                'contactPerson':
                    contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim(),
                'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                'category':
                    categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim(),
                'address':
                    addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
              };

              if (existing != null) {
                await ApiClient.instance.patch(
                  ApiConstants.supplierById(existing['id'] as String),
                  data: payload,
                );
              } else {
                await ApiClient.instance.post(
                  ApiConstants.suppliers,
                  data: {'branchId': profile?.branchId, ...payload},
                );
              }
              ref.invalidate(suppliersProvider);

              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSupplier(String id) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Supplier',
      message:
          'Are you sure? This supplier will be removed. Existing purchases will not be affected.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await ApiClient.instance.delete(ApiConstants.supplierById(id));
    ref.invalidate(suppliersProvider);
  }
}

// ── Supplier Card ──
class _SupplierCard extends StatelessWidget {
  final Map<String, dynamic> supplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SupplierCard({
    required this.supplier,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = supplier['name'] as String? ?? 'Unknown';
    final contact = supplier['contact_person'] as String?;
    final phone = supplier['phone'] as String?;
    final email = supplier['email'] as String?;
    final category = supplier['category'] as String?;
    final isActive = supplier['is_active'] as bool? ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_shipping_rounded,
                  color: AppColors.primary, size: 22),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                if (!isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('Inactive',
                        style: GoogleFonts.outfit(fontSize: 10, color: AppColors.error)),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact != null)
                  Text(contact,
                      style:
                          GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                if (phone != null)
                  Text(phone,
                      style:
                          GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                if (category != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(category,
                          style: GoogleFonts.outfit(
                              fontSize: 10, color: AppColors.info, fontWeight: FontWeight.w500)),
                    ),
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
              onSelected: (s) {
                if (s == 'edit') onEdit();
                if (s == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
          if (email != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.email_outlined, size: 14, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  Text(email,
                      style: GoogleFonts.outfit(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
