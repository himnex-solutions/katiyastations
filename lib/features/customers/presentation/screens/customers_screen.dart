import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _search = '';
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final profile = ref.read(authNotifierProvider).value;
    if (profile?.branchId == null) return;
    final response = await ApiClient.instance.get(
      ApiConstants.customers,
      queryParameters: {'branchId': profile!.branchId!},
    );
    final data = response.data as Map<String, dynamic>;
    final rows = List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
    rows.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    if (mounted) setState(() { _customers = rows; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty ? _customers : _customers.where((c) =>
        (c['name'] as String).toLowerCase().contains(_search) ||
        (c['phone'] as String? ?? '').contains(_search)).toList();

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
              child: const Icon(Icons.people,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Customer Management',
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
          TextButton.icon(icon: const Icon(Icons.person_add_rounded, size: 18), label: const Text('Add Customer'), onPressed: () => _showAddDialog(context)),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface, padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: TextField(
                decoration: const InputDecoration(hintText: 'Search customers...', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              )),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.info.withValues(alpha: 0.2))),
                child: Text('${filtered.length} customers', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.info, fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : filtered.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.people_outline_rounded, size: 64, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('No customers found', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: () => _showAddDialog(context), child: const Text('Add Customer')),
                ]))
              : ResponsiveContent(child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final c = filtered[i];
                    final pts = (c['loyalty_points'] as num?)?.toInt() ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                          child: Text((c['name'] as String).substring(0, 1).toUpperCase(),
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c['name'] as String, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text(c['phone'] as String? ?? '—', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.stars_rounded, size: 14, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text('$pts pts', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ]),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 25));
                  },
                ))),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Customer'),
      content: SizedBox(
        width: context.dialogWidth(400),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name *')),
            const SizedBox(height: 12),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
            const SizedBox(height: 12),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Address')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          final profile = ref.read(authNotifierProvider).value;
          await ApiClient.instance.post(
            ApiConstants.customers,
            data: {
              'branchId': profile?.branchId,
              'name': nameCtrl.text.trim(),
              'phone': phoneCtrl.text.trim(),
              'address': addrCtrl.text.trim().isEmpty ? null : addrCtrl.text.trim(),
            },
          );
          if (context.mounted) { Navigator.pop(ctx); _load(); }
        }, child: const Text('Save')),
      ],
    ));
  }
}
