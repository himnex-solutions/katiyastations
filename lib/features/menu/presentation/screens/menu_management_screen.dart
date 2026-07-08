import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../menu/domain/entities/menu_entities.dart';
import '../widgets/recipe_dialog.dart';
import 'package:file_picker/file_picker.dart';

// All categories for the branch
final menuCategoriesStreamProvider =
    FutureProvider<List<MenuCategory>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.menuCategories,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final rows = response.data as List<dynamic>;
  return rows
      .map((r) => MenuCategory.fromJson(r as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});

// Items by category
final menuItemsByCatProvider =
    FutureProvider.family<List<MenuItem>, String>((ref, catId) async {
  final response = await ApiClient.instance.get(
    ApiConstants.menuItems,
    queryParameters: {'categoryId': catId},
  );
  final rows = response.data as List<dynamic>;
  return rows.map((r) => MenuItem.fromJson(r as Map<String, dynamic>)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

// All items across every category for the branch — used by menu search
final menuItemsAllProvider = FutureProvider<List<MenuItem>>((ref) async {
  final profile = ref.watch(authNotifierProvider).value;
  if (profile?.branchId == null) return [];
  final response = await ApiClient.instance.get(
    ApiConstants.menuItems,
    queryParameters: {'branchId': profile!.branchId!},
  );
  final rows = response.data as List<dynamic>;
  return rows.map((r) => MenuItem.fromJson(r as Map<String, dynamic>)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

// Design constants local to this screen, kept in one place so the whole
// surface reads as one considered system rather than ad-hoc numbers.
class _MenuUi {
  _MenuUi._();
  static const double cardRadius = 16;
  static const Color subtleFill = Color(0xFFF7F8FA);
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x05121212), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A121212), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static Color typeColor(String type) {
    switch (type) {
      case 'drink':
        return AppColors.info;
      case 'bar':
        return AppColors.roleInventory;
      default:
        return AppColors.primary;
    }
  }
}

InputDecoration _premiumFieldDecoration(
    {required String label, IconData? icon}) {
  return InputDecoration(
    labelText: label,
    labelStyle:
        GoogleFonts.outfit(fontSize: 13, color: AppColors.textSecondary),
    prefixIcon:
        icon == null ? null : Icon(icon, size: 18, color: AppColors.textHint),
    filled: true,
    fillColor: _MenuUi.subtleFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
    ),
  );
}

class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});
  @override
  ConsumerState<MenuManagementScreen> createState() =>
      _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen> {
  String? _selectedCatId;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(menuCategoriesStreamProvider);
    final allItemsAsync = ref.watch(menuItemsAllProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.32),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.restaurant_menu,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 13),
            Flexible(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Menu Management',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                catsAsync.when(
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                  data: (cats) {
                    final itemCount = allItemsAsync.value?.length;
                    return Text(
                      itemCount == null
                          ? '${cats.length} categories'
                          : '${cats.length} categories · $itemCount items',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
            )),
          ],
        ),
        actions: [
          if (context.isMobile) ...[
            IconButton(
              onPressed: () => _importBulkExcel(context),
              icon: const Icon(Icons.file_upload_outlined, size: 20),
              tooltip: 'Import',
              color: AppColors.textPrimary,
            ),
            IconButton(
              onPressed: () => _showCategoryDialog(context),
              icon: const Icon(Icons.create_new_folder_outlined, size: 20),
              tooltip: 'Add Category',
              color: AppColors.textPrimary,
            ),
            if (_selectedCatId != null)
              IconButton(
                onPressed: () => _showItemDialog(context),
                icon: const Icon(Icons.add_rounded, size: 24),
                tooltip: 'Add Item',
                color: AppColors.primary,
              ),
            const SizedBox(width: 6),
          ] else ...[
            OutlinedButton.icon(
              onPressed: () => _importBulkExcel(context),
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: Text('Import',
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _showCategoryDialog(context),
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: Text('Category',
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            if (_selectedCatId != null)
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gradientStart, AppColors.gradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _showItemDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Add Item',
                      style: GoogleFonts.outfit(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            const SizedBox(width: 16),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: catsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cats) {
          if (cats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.restaurant_menu_rounded,
                        size: 44, color: AppColors.primary),
                  ),
                  const SizedBox(height: 18),
                  Text('No categories yet',
                      style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  Text('Create your first category to start building the menu.',
                      style: GoogleFonts.outfit(
                          fontSize: 12.5, color: AppColors.textSecondary)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _showCategoryDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add First Category'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            );
          }
          if (_selectedCatId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedCatId = cats.first.id);
            });
          }
          final Widget contentBody = _searchQuery.trim().isNotEmpty
              ? _SearchItemsGrid(
                  query: _searchQuery,
                  categories: cats,
                  onEdit: (item) => _showItemDialog(context, item),
                  onDelete: (item) => _deleteItem(item),
                )
              : (_selectedCatId == null
                  ? Center(
                      child: Text('Select a category',
                          style: GoogleFonts.outfit(
                              color: AppColors.textSecondary)))
                  : _ItemsGrid(
                      catId: _selectedCatId!,
                      onEdit: (item) => _showItemDialog(context, item),
                      onDelete: (item) => _deleteItem(item),
                    ));

          final content = Column(
            children: [
              _buildSearchBar(),
              _buildContentHeader(cats),
              Expanded(child: contentBody),
            ],
          );

          // Narrow screens: swap the fixed side rail for a horizontal
          // category strip so the item grid gets the full width.
          if (context.isMobile) {
            return Column(
              children: [
                _buildCategoryStrip(cats),
                Expanded(child: content),
              ],
            );
          }

          return Row(
            children: [
              _buildCategorySidebar(cats),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  CATEGORY SIDEBAR
  // ─────────────────────────────────────────────────────────
  Widget _buildCategorySidebar(List<MenuCategory> cats) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.category_rounded,
                      color: AppColors.primary, size: 14),
                ),
                const SizedBox(width: 9),
                Text(
                  'Categories',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${cats.length}',
                    style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final cat = cats[i];
                final isSelected = cat.id == _selectedCatId;
                final typeColor = _MenuUi.typeColor(cat.type);
                return InkWell(
                  onTap: () => setState(() => _selectedCatId = cat.id),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.3)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: typeColor.withValues(
                                alpha: isSelected ? 0.16 : 0.1),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            cat.name.isNotEmpty
                                ? cat.name[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: typeColor),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                cat.type.toUpperCase(),
                                style: GoogleFonts.outfit(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _IconAction(
                          icon: Icons.delete_rounded,
                          color: AppColors.error,
                          tooltip: 'Delete category',
                          size: 15,
                          onTap: () => _deleteCategory(cat.id, cat.name),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal category selector used on narrow screens in place of the
  /// vertical side rail. Tap to select, long-press to delete (parity with
  /// the sidebar). Scrolls horizontally so any number of categories fit.
  Widget _buildCategoryStrip(List<MenuCategory> cats) {
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final cat = cats[i];
          final isSelected = cat.id == _selectedCatId;
          final typeColor = _MenuUi.typeColor(cat.type);
          return GestureDetector(
            onTap: () => setState(() => _selectedCatId = cat.id),
            onLongPress: () => _deleteCategory(cat.id, cat.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : _MenuUi.subtleFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: typeColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cat.name,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Search bar for filtering menu items by name, price, or category
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search menu by name, price or category',
          hintStyle:
              GoogleFonts.outfit(fontSize: 13, color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.textSecondary, size: 20),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: _MenuUi.subtleFill,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  /// Context strip above the item grid: which category is open (or that a
  /// search is running) and how many items it holds.
  Widget _buildContentHeader(List<MenuCategory> cats) {
    if (_searchQuery.trim().isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 3),
        child: Row(
          children: [
            const Icon(Icons.search_rounded,
                size: 17, color: AppColors.textSecondary),
            const SizedBox(width: 9),
            Text(
              'Search results',
              style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                '“${_searchQuery.trim()}”',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    GoogleFonts.outfit(fontSize: 13, color: AppColors.textHint),
              ),
            ),
          ],
        ),
      );
    }

    MenuCategory? cat;
    for (final c in cats) {
      if (c.id == _selectedCatId) {
        cat = c;
        break;
      }
    }
    if (cat == null) return const SizedBox.shrink();
    final typeColor = _MenuUi.typeColor(cat.type);
    final count = ref.watch(menuItemsByCatProvider(cat.id)).value?.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 3),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(_categoryIcon(cat.type), size: 18, color: typeColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2),
                ),
                Text(
                  count == null
                      ? cat.type.toUpperCase()
                      : '${cat.type.toUpperCase()} · $count item${count == 1 ? '' : 's'}',
                  style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: AppColors.textHint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String type) {
    switch (type) {
      case 'drink':
        return Icons.local_cafe_rounded;
      case 'bar':
        return Icons.local_bar_rounded;
      default:
        return Icons.restaurant_rounded;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  ADD CATEGORY DIALOG
  // ─────────────────────────────────────────────────────────
  Future<void> _showCategoryDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    String type = 'food';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.create_new_folder_rounded,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Text('Add Category',
                style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        content: StatefulBuilder(
          builder: (ctx, set) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: _premiumFieldDecoration(
                    label: 'Category Name', icon: Icons.label_outline_rounded),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: _premiumFieldDecoration(
                    label: 'Type', icon: Icons.tune_rounded),
                onChanged: (v) => set(() => type = v!),
                items: const [
                  DropdownMenuItem(value: 'food', child: Text('Food')),
                  DropdownMenuItem(value: 'drink', child: Text('Drink')),
                  DropdownMenuItem(value: 'bar', child: Text('Bar')),
                ],
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                final profile = ref.read(authNotifierProvider).value;
                if (profile?.branchId == null) {
                  throw Exception(
                      'Branch ID not found in user profile. Cannot add category.');
                }
                await ApiClient.instance.post(
                  ApiConstants.menuCategories,
                  data: {
                    'branchId': profile!.branchId,
                    'name': nameCtrl.text.trim(),
                    'type': type,
                  },
                );
                ref.invalidate(menuCategoriesStreamProvider);
                if (context.mounted) Navigator.pop(ctx);
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.error),
                );
              }
            },
            child: Text('Add',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  ADD / EDIT ITEM DIALOG
  // ─────────────────────────────────────────────────────────
  Future<void> _showItemDialog(BuildContext context,
      [MenuItem? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl =
        TextEditingController(text: existing?.price.toString() ?? '');
    final imageUrlCtrl = TextEditingController(text: existing?.imageUrl ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                existing == null
                    ? Icons.add_circle_outline_rounded
                    : Icons.edit_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Text(existing == null ? 'Add Menu Item' : 'Edit Item',
                style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: _premiumFieldDecoration(
                    label: 'Item Name *', icon: Icons.fastfood_rounded),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: _premiumFieldDecoration(
                    label: 'Selling Price (NPR) *',
                    icon: Icons.payments_rounded),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: imageUrlCtrl,
                decoration: _premiumFieldDecoration(
                    label: 'Image URL (paste image link)',
                    icon: Icons.image_outlined),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: _premiumFieldDecoration(
                    label: 'Description', icon: Icons.notes_rounded),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                final profile = ref.read(authNotifierProvider).value;
                if (profile?.branchId == null) {
                  throw Exception(
                      'Branch ID not found in user profile. Cannot save item.');
                }
                final targetCatId = existing?.categoryId ?? _selectedCatId;
                final data = {
                  'branchId': profile!.branchId,
                  'categoryId': targetCatId,
                  'name': nameCtrl.text.trim(),
                  'price': double.tryParse(priceCtrl.text) ?? 0,
                  'imageUrl': imageUrlCtrl.text.trim().isEmpty
                      ? null
                      : imageUrlCtrl.text.trim(),
                  'description': descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  'isAvailable': existing?.isAvailable ?? true,
                };
                if (existing == null) {
                  await ApiClient.instance
                      .post(ApiConstants.menuItems, data: data);
                } else {
                  await ApiClient.instance.patch(
                      ApiConstants.menuItemById(existing.id),
                      data: data);
                }
                if (targetCatId != null) {
                  ref.invalidate(menuItemsByCatProvider(targetCatId));
                }
                ref.invalidate(menuItemsAllProvider);
                if (context.mounted) Navigator.pop(ctx);
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.error),
                );
              }
            },
            child: Text('Save',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _importBulkExcel(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) {
        throw Exception(
            'Failed to read file bytes. Make sure the file is not empty.');
      }

      final profile = ref.read(authNotifierProvider).value;
      final branchId = profile?.branchId;
      if (branchId == null) {
        throw Exception('Branch ID not found in user profile.');
      }

      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text('Importing menu items… please wait.',
                      style: GoogleFonts.outfit(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      );

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: result.files.first.name,
        ),
      });

      final response = await ApiClient.instance.upload(
        '${ApiConstants.menuImportExcel}?branchId=$branchId',
        formData,
      );
      final resultData = response.data as Map<String, dynamic>;
      final created = resultData['created'] as int? ?? 0;

      if (context.mounted) Navigator.pop(context);

      ref.invalidate(menuCategoriesStreamProvider);
      if (_selectedCatId != null) {
        ref.invalidate(menuItemsByCatProvider(_selectedCatId!));
      }
      ref.invalidate(menuItemsAllProvider);

      messenger.showSnackBar(
        SnackBar(
          content: Text('Imported $created menu items!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context)
            .popUntil((route) => route.isFirst || route.settings.name != null);
      }
      messenger.showSnackBar(
        SnackBar(
            content: Text('Failed to import: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _deleteCategory(String id, String name) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Category?',
      message:
          'This will permanently remove "$name". Items inside this category will not be deleted but will need to be recategorized.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.error,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await ApiClient.instance.delete(ApiConstants.menuCategoryById(id));
    ref.invalidate(menuCategoriesStreamProvider);
    if (_selectedCatId == id) setState(() => _selectedCatId = null);
  }

  Future<void> _deleteItem(MenuItem item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Menu Item?',
      message:
          'This will permanently remove "${item.name}" from your menu. This action cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.error,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await ApiClient.instance.delete(ApiConstants.menuItemById(item.id));
    ref.invalidate(menuItemsByCatProvider(item.categoryId));
    ref.invalidate(menuItemsAllProvider);
  }
}

class _ItemsGrid extends ConsumerWidget {
  final String catId;
  final ValueChanged<MenuItem> onEdit;
  final ValueChanged<MenuItem> onDelete;
  const _ItemsGrid(
      {required this.catId, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(menuItemsByCatProvider(catId));
    return itemsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) => items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.textHint.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.no_food_rounded,
                        size: 40, color: AppColors.textHint),
                  ),
                  const SizedBox(height: 14),
                  Text('No items in this category',
                      style: GoogleFonts.outfit(
                          fontSize: 13.5, color: AppColors.textSecondary)),
                ],
              ),
            )
          : _ItemsGridView(
              items: items, ref: ref, onEdit: onEdit, onDelete: onDelete),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Search results across every category — filters by name, price, or category
// ════════════════════════════════════════════════════════════════════════════
class _SearchItemsGrid extends ConsumerWidget {
  final String query;
  final List<MenuCategory> categories;
  final ValueChanged<MenuItem> onEdit;
  final ValueChanged<MenuItem> onDelete;
  const _SearchItemsGrid({
    required this.query,
    required this.categories,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(menuItemsAllProvider);
    final q = query.trim().toLowerCase();

    return itemsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final catNameById = {
          for (final c in categories) c.id: c.name.toLowerCase()
        };
        final filtered = items.where((item) {
          final nameMatch = item.name.toLowerCase().contains(q);
          final categoryMatch =
              (catNameById[item.categoryId] ?? '').contains(q);
          final priceMatch = item.price.toStringAsFixed(0).contains(q) ||
              item.price.toStringAsFixed(2).contains(q);
          return nameMatch || categoryMatch || priceMatch;
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.textHint.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.search_off_rounded,
                      size: 40, color: AppColors.textHint),
                ),
                const SizedBox(height: 14),
                Text('No items match "$query"',
                    style: GoogleFonts.outfit(
                        fontSize: 13.5, color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return _ItemsGridView(
            items: filtered, ref: ref, onEdit: onEdit, onDelete: onDelete);
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Shared grid layout for a resolved list of menu items
// ════════════════════════════════════════════════════════════════════════════
class _ItemsGridView extends StatelessWidget {
  final List<MenuItem> items;
  final WidgetRef ref;
  final ValueChanged<MenuItem> onEdit;
  final ValueChanged<MenuItem> onDelete;
  const _ItemsGridView(
      {required this.items,
      required this.ref,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(18),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent:
            context.responsiveValue(mobile: 190, tablet: 220, desktop: 250),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _MenuItemCard(
        item: items[i],
        ref: ref,
        onEdit: () => onEdit(items[i]),
        onDelete: () => onDelete(items[i]),
      )
          .animate()
          .fadeIn(delay: Duration(milliseconds: i * 30))
          .scale(begin: const Offset(0.95, 0.95)),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final WidgetRef ref;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _MenuItemCard({
    required this.item,
    required this.ref,
    required this.onEdit,
    required this.onDelete,
  });

  Future<void> _toggleAvailability(BuildContext context) async {
    final turningOff = item.isAvailable;
    final confirmed = await showConfirmDialog(
      context,
      title: turningOff ? 'Turn Off Item?' : 'Turn On Item?',
      message: turningOff
          ? '"${item.name}" will be switched off and hidden from ordering screens until you turn it back on.'
          : '"${item.name}" will be switched on and become orderable again.',
      confirmLabel: turningOff ? 'Turn Off' : 'Turn On',
      confirmColor: turningOff ? AppColors.warning : AppColors.success,
      icon: turningOff ? Icons.toggle_off_rounded : Icons.toggle_on_rounded,
    );
    if (!confirmed) return;
    await ApiClient.instance.patch(
      ApiConstants.menuItemById(item.id),
      data: {'isAvailable': !item.isAvailable},
    );
    ref.invalidate(menuItemsByCatProvider(item.categoryId));
    ref.invalidate(menuItemsAllProvider);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final typeColor = _MenuUi.typeColor(item.type);
    final available = item.isAvailable;
    final hasDesc =
        item.description != null && item.description!.trim().isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(_MenuUi.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: _MenuUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Image header ──────────────────────────────────
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 1.5,
                child: hasImage
                    ? Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: AppColors.surfaceVariant,
                            child: const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => _placeholder(typeColor),
                      )
                    : _placeholder(typeColor),
              ),
              // Gradient scrim so the price badge stays legible on any image.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.42),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!available)
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.42)),
                ),
              // Floating price badge
              Positioned(
                left: 10,
                bottom: 9,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text('NPR ${fmt.format(item.price)}',
                      style: GoogleFonts.outfit(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                ),
              ),
              if (!available)
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('OFF',
                        style: GoogleFonts.outfit(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Colors.white)),
                  ),
                ),
              // Overflow menu (Edit · Recipe)
              Positioned(top: 8, right: 8, child: _cardMenu(context)),
            ],
          ),
          // ── Body ──────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    hasDesc
                        ? item.description!.trim()
                        : item.type.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontWeight: hasDesc ? FontWeight.w400 : FontWeight.w600,
                      letterSpacing: hasDesc ? 0 : 0.4,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      // Professional on/off control — a real Material switch.
                      SizedBox(
                        width: 38,
                        height: 24,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Switch(
                            value: available,
                            onChanged: (_) => _toggleAvailability(context),
                            activeThumbColor: Colors.white,
                            activeTrackColor: AppColors.success,
                            inactiveThumbColor: Colors.white,
                            inactiveTrackColor: const Color(0xFFCBD2D9),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        available ? 'Available' : 'Hidden',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: available
                              ? AppColors.success
                              : AppColors.textHint,
                        ),
                      ),
                      const Spacer(),
                      _IconAction(
                        icon: Icons.delete_rounded,
                        color: AppColors.error,
                        tooltip: 'Delete item',
                        onTap: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Frosted circular overflow menu shown on the item image.
  Widget _cardMenu(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz_rounded,
            color: AppColors.textPrimary, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        itemBuilder: (ctx) => [
          _cardMenuRow('edit', Icons.edit_rounded, AppColors.info, 'Edit'),
          _cardMenuRow('recipe', Icons.menu_book_rounded,
              AppColors.roleInventory, 'Recipe'),
        ],
        onSelected: (val) {
          if (val == 'edit') {
            onEdit();
          } else if (val == 'recipe') {
            showDialog(
                context: context, builder: (ctx) => RecipeDialog(item: item));
          }
        },
      ),
    );
  }

  PopupMenuItem<String> _cardMenuRow(
      String value, IconData icon, Color color, String label) {
    return PopupMenuItem(
      value: value,
      height: 44,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 11),
          Text(label,
              style: GoogleFonts.outfit(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _placeholder(Color typeColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            typeColor.withValues(alpha: 0.12),
            typeColor.withValues(alpha: 0.03)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
          child:
              Icon(Icons.restaurant_menu_rounded, color: typeColor, size: 26)),
    );
  }
}

/// Clean, borderless circular icon button — a soft tinted fill with a ripple,
/// no outline. Shared by the card and category-row actions.
class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  const _IconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: color.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}
