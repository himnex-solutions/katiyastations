import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'package:katiya_station_rms/features/branches/presentation/providers/branch_provider.dart';
import 'package:katiya_station_rms/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:katiya_station_rms/features/kitchen/presentation/screens/kitchen_screen.dart';
import 'package:katiya_station_rms/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:katiya_station_rms/features/orders/domain/entities/order_entities.dart';

/// A ticket as the kitchen really receives it — the KOT number is a full
/// `KOT-20260712-4F82`, which is what used to burst the card header open.
Kot _kot(String suffix, String table) => Kot.fromJson({
      'id': 'kot-$suffix',
      'session_id': 'sess-1',
      'branch_id': 'branch-1',
      'table_id': 'table-1',
      'kot_number': 'KOT-20260712-$suffix',
      'table_number': table,
      'status': 'pending',
      'items_count': 2,
      'created_at': DateTime.now().toIso8601String(),
    });

final _items = [
  KotItem.fromJson(const {
    'id': 'i1',
    'kot_id': 'kot-4F82',
    'menu_item_id': 'm1',
    'name': 'Chicken Sekuwa with Extra Garlic Sauce',
    'quantity': 2,
    'unit_price': 450,
    'status': 'pending',
  }),
];

Widget _app(List<Kot> kots) => ProviderScope(
      overrides: [
        kitchenKotsProvider.overrideWith((ref) async => kots),
        kotItemsProvider.overrideWith((ref, id) async => _items),
        currentBranchProvider.overrideWith((ref) async => null),
        unreadNotificationCountProvider.overrideWithValue(0),
      ],
      child: MaterialApp(
        home: const KitchenScreen(),
        builder: (context, child) => ResponsiveBreakpoints.builder(
          child: child!,
          breakpoints: const [
            Breakpoint(start: 0, end: 599, name: MOBILE),
            Breakpoint(start: 600, end: 899, name: TABLET),
            Breakpoint(start: 900, end: double.infinity, name: DESKTOP),
          ],
        ),
      ),
    );

void main() {
  // Every size a Katiya kitchen actually runs on. The Kanban splits the width
  // three ways, so a 600px tablet gives each column ~200px — the case that was
  // overflowing by ~100px.
  const sizes = <String, Size>{
    'phone (360x740)': Size(360, 740),
    'small tablet (600x960)': Size(600, 960),
    'tablet portrait (800x1280)': Size(800, 1280),
    'tablet landscape (1280x800)': Size(1280, 800),
  };

  for (final entry in sizes.entries) {
    testWidgets('kitchen screen lays out with no overflow on ${entry.key}',
        (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app([_kot('4F82', '12'), _kot('9A1C', '7')]));

      // An overflow is only reported when the offending row is *painted*, and
      // the cards fade in — at zero opacity nothing paints, so a single pump
      // sees nothing. Walk the entry animation frame by frame instead, keeping
      // the first complaint any of them makes.
      Object? overflow;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        overflow ??= tester.takeException();
      }

      expect(overflow, isNull);
      expect(find.textContaining('KOT-20260712'), findsWidgets);

      // Tears the tree down inside the test, so the overdue-alarm ticker is
      // cancelled in its dispose() rather than tripping the pending-timer check.
      await tester.pumpWidget(const SizedBox());
    });
  }
}
