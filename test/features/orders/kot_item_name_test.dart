import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/features/orders/domain/entities/order_entities.dart';

void main() {
  group('kotItemNameOf', () {
    test('reads the name off a real /sessions/:id/kots item', () {
      // Exactly what the backend sends: a `kot_items` row, camelCase fields
      // snake_cased by SnakeCaseInterceptor. Note there is no
      // `menu_item_name` — reaching for that key is what showed "Item".
      final item = <String, dynamic>{
        'id': 'a1',
        'kot_id': 'k1',
        'menu_item_id': 'm1',
        'name': 'Chicken Momo',
        'quantity': 2,
        'unit_price': 250,
        'status': 'pending',
        'note': null,
      };

      expect(kotItemNameOf(item), 'Chicken Momo');
      expect(item['menu_item_name'], isNull, reason: 'the old key never existed');
    });

    test('still reads bill/receipt payloads, which use menu_item_name', () {
      expect(
        kotItemNameOf({'menu_item_name': 'Veg Chowmein', 'quantity': 1}),
        'Veg Chowmein',
      );
    });

    test('falls back through a nested menu_item', () {
      expect(
        kotItemNameOf({
          'menu_item': {'name': 'Chiya'}
        }),
        'Chiya',
      );
    });

    test('returns null when there is genuinely no name to show', () {
      expect(kotItemNameOf({'quantity': 1}), isNull);
      expect(kotItemNameOf({'name': ''}), isNull);
    });

    test('KotItem.fromJson resolves the name the same way', () {
      final kotItem = KotItem.fromJson(const {
        'id': 'a1',
        'kot_id': 'k1',
        'menu_item_id': 'm1',
        'name': 'Chicken Momo',
        'quantity': 2,
        'unit_price': 250,
        'status': 'pending',
      });
      expect(kotItem.menuItemName, 'Chicken Momo');
    });
  });
}
