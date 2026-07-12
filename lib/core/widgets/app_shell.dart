import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:responsive_framework/responsive_framework.dart';
import '../constants/app_colors.dart';
import 'confirm_dialog.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../router/app_router.dart';
import '../network/realtime_sync.dart';
import '../printing/kot_auto_print.dart';

/// Human label for a role — shared by the desktop rail footer and the mobile
/// account sheet so both name the role the same way.
String roleLabelFor(String? role) {
  switch (role) {
    case 'super_admin': return 'Super Admin';
    case 'branch_manager': return 'Manager';
    case 'cashier': return 'Cashier';
    case 'waiter': return 'Waiter';
    case 'kitchen': return 'Kitchen';
    case 'inventory': return 'Inventory';
    case 'accountant': return 'Accountant';
    default: return 'Staff';
  }
}

Color roleColorFor(String? role) {
  switch (role) {
    case 'branch_manager': return AppColors.roleManager;
    case 'cashier': return AppColors.roleCashier;
    case 'waiter': return AppColors.roleWaiter;
    case 'kitchen': return AppColors.roleKitchen;
    case 'inventory': return AppColors.roleInventory;
    default: return AppColors.textSecondary;
  }
}

class AppShell extends ConsumerWidget {
  final Widget child;
  final String currentPath;

  const AppShell({super.key, required this.child, required this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the Socket.IO -> provider-invalidation bridge alive for the
    // whole authenticated session so every screen under this shell gets
    // live updates without a manual refresh.
    ref.watch(realtimeSyncProvider);
    // Print-station devices (kitchen tablet/PC with a thermal printer) auto-
    // print each incoming KOT the moment a waiter sends it. No-op on web.
    ref.watch(kotAutoPrintProvider);
    final profileAsync = ref.watch(authNotifierProvider);
    final profile = profileAsync.value;
    final navItems = getNavItemsForRole(profile?.role);
    final isWide = ResponsiveBreakpoints.of(context).isDesktop;

    // Auth is still resolving (e.g. a background token refresh, or the
    // brief window right after a hard page refresh) — profile/navItems
    // aren't known yet. Render the page content as-is without nav chrome
    // rather than crash: Material's NavigationBar hard-asserts on having
    // at least 2 destinations, which too few navItems would violate.
    if (navItems.length < 2) {
      return Scaffold(body: child);
    }

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _SideNavRail(
              navItems: navItems,
              currentPath: currentPath,
              profile: profile,
              onSignOut: () async {
                final confirmed = await showSignOutDialog(context);
                if (!confirmed) return;
                await ref.read(authNotifierProvider.notifier).signOut();
                if (context.mounted) context.go('/login');
              },
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    // Mobile / Tablet: bottom nav with "More" overflow.
    // 4 rather than 5 so that "More" still fits inside Material's
    // 5-destination guidance for a NavigationBar.
    const maxVisible = 4;
    final visibleItems = navItems.take(maxVisible).toList();
    final overflowItems = navItems.skip(maxVisible).toList();

    // "More" is the last destination when it has a reason to exist: either
    // nav overflowed into it, or the role has no Settings screen — Settings
    // is where Sign Out otherwise lives at this breakpoint, and there's no
    // side rail down here to fall back on. A role with neither (super_admin,
    // kitchen) would get an empty sheet, so drop the tab entirely.
    final hasSettings = navItems.any((i) => i.path == '/settings');
    final showMore = overflowItems.isNotEmpty || !hasSettings;
    final moreIndex = showMore ? visibleItems.length : -1;

    // Determine selected index; -1 if current path is in overflow
    int currentIdx = visibleItems
        .indexWhere((i) => currentPath.startsWith(i.path));
    final isInOverflow = currentIdx < 0 &&
        overflowItems.any((i) => currentPath.startsWith(i.path));

    final selectedIndex = isInOverflow
        ? moreIndex
        : (currentIdx < 0 ? 0 : currentIdx);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        onDestinationSelected: (i) {
          if (showMore && i == moreIndex) {
            _showMoreSheet(context, overflowItems, ref, profile);
          } else {
            context.go(visibleItems[i].path);
          }
        },
        destinations: [
          ...visibleItems.map((item) => NavigationDestination(
                icon: Icon(item.icon, color: AppColors.textSecondary),
                selectedIcon: Icon(item.activeIcon, color: AppColors.primary),
                label: item.label,
              )),
          if (showMore)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded,
                  color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.more_horiz_rounded,
                  color: AppColors.primary),
              label: 'More',
            ),
        ],
      ),
    );
  }

  void _showMoreSheet(
      BuildContext context, List<NavItem> items, WidgetRef ref, dynamic profile) {
    final role = profile?.role as String?;
    final fullName = (profile?.fullName as String?)?.trim();
    final roleColor = roleColorFor(role);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Who's signed in — the mobile/tablet nav has no side rail to
              // carry this, so the name and role live here alongside Sign Out.
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: roleColor.withValues(alpha: 0.2),
                    child: Text(
                      (fullName?.isNotEmpty ?? false)
                          ? fullName!.substring(0, 1).toUpperCase()
                          : 'U',
                      style: TextStyle(
                          color: roleColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (fullName?.isNotEmpty ?? false) ? fullName! : 'User',
                          style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(roleLabelFor(role),
                            style: GoogleFonts.outfit(
                                fontSize: 12, color: roleColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (items.isNotEmpty)
              Flexible(
                child: GridView.builder(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final isActive = currentPath.startsWith(item.path);
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.go(item.path);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.icon,
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              size: 24),
                          const SizedBox(height: 6),
                          Text(
                            item.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ),
              const SizedBox(height: 8),
              // Matches the Sign Out card at the bottom of Settings, so the
              // action looks the same wherever a role happens to reach it.
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      final confirmed = await showSignOutDialog(context);
                      if (!confirmed || !context.mounted) return;
                      await ref.read(authNotifierProvider.notifier).signOut();
                      if (context.mounted) context.go('/login');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout_rounded,
                              size: 18, color: AppColors.onPrimary),
                          const SizedBox(width: 8),
                          Text('Sign Out',
                              style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onPrimary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _railExpandedWidth = 240;
const double _railCollapsedWidth = 72;
const double _railPadding = 12;

class _SideNavRail extends StatefulWidget {
  final List<NavItem> navItems;
  final String currentPath;
  final dynamic profile;
  final VoidCallback onSignOut;

  const _SideNavRail({
    required this.navItems,
    required this.currentPath,
    required this.profile,
    required this.onSignOut,
  });

  @override
  State<_SideNavRail> createState() => _SideNavRailState();
}

class _SideNavRailState extends State<_SideNavRail> {
  bool _collapsed = false;

  String get _roleLabel => roleLabelFor(widget.profile?.role);
  Color get _roleColor => roleColorFor(widget.profile?.role);

  Widget _avatar() => CircleAvatar(
        radius: 18,
        backgroundColor: _roleColor.withValues(alpha: 0.2),
        child: Text(
          widget.profile?.fullName?.substring(0, 1).toUpperCase() ?? 'U',
          style: TextStyle(color: _roleColor, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = _collapsed ? _railCollapsedWidth : _railExpandedWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: w,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: _railPadding),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: _RailContent(
              collapsed: _collapsed,
              collapsedChild: Tooltip(
                message: 'Expand menu',
                child: InkWell(
                  onTap: () => setState(() => _collapsed = false),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/katiyastationlogo.jpeg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/katiyastationlogo.jpeg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('KATIYA', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 1.5)),
                        Text('STATION RMS', style: GoogleFonts.outfit(fontSize: 9, color: AppColors.textSecondary, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: AppColors.textSecondary, size: 18),
                    tooltip: 'Collapse menu',
                    onPressed: () => setState(() => _collapsed = true),
                  ),
                ],
              ),
            ),
          ),
          // Nav Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ...widget.navItems.map((item) {
                  final isActive = widget.currentPath.startsWith(item.path);
                  return _NavTile(
                    item: item,
                    isActive: isActive,
                    collapsed: _collapsed,
                    onTap: () => context.go(item.path),
                  );
                }),
              ],
            ),
          ),
          // User profile footer
          Container(
            height: 72,
            padding: const EdgeInsets.all(_railPadding),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: _RailContent(
              collapsed: _collapsed,
              collapsedChild: Tooltip(
                message: '$_roleLabel — Sign Out',
                child: InkWell(
                  onTap: widget.onSignOut,
                  customBorder: const CircleBorder(),
                  child: _avatar(),
                ),
              ),
              child: Row(
                children: [
                  _avatar(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.profile?.fullName ?? 'User',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(_roleLabel, style: GoogleFonts.outfit(fontSize: 11, color: _roleColor)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                    onPressed: widget.onSignOut,
                    tooltip: 'Sign Out',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays the rail's header/footer content out at the width its state will settle
/// at, and clips it. The rail's width is animated, so laying content out against
/// the live width overflows on the frames where the two disagree — and the
/// expanded content never fits the 48px the collapsed rail leaves anyway.
class _RailContent extends StatelessWidget {
  final bool collapsed;
  final Widget collapsedChild;
  final Widget child;

  const _RailContent({
    required this.collapsed,
    required this.collapsedChild,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = (collapsed ? _railCollapsedWidth : _railExpandedWidth) - _railPadding * 2;

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: width,
        maxWidth: width,
        child: collapsed ? Center(child: collapsedChild) : child,
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool isActive;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavTile({required this.item, required this.isActive, required this.collapsed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? item.label : '',
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive ? Border.all(color: AppColors.primary.withValues(alpha: 0.25)) : null,
          ),
          child: Row(
            mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              // Red left accent bar on active item
              if (!collapsed)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: 20,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Icon(
                isActive ? item.activeIcon : item.icon,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
                size: 20,
              ),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
