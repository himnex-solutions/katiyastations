import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katiya_station_rms/core/constants/app_colors.dart';
import 'package:katiya_station_rms/core/theme/app_theme.dart';
import 'package:katiya_station_rms/core/widgets/app_snackbar.dart';

/// Pumps a screen whose only button raises [show], then taps it.
Future<void> _raise(
  WidgetTester tester,
  void Function(ScaffoldMessengerState) show,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => show(ScaffoldMessenger.of(context)),
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pump();
}

void main() {
  group('app snackbars', () {
    testWidgets('the KOT success message is legible against its background',
        (tester) async {
      await _raise(tester, (m) => m.showSuccess('KOT-001 sent to kitchen!'));

      expect(find.text('KOT-001 sent to kitchen!'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      final text = tester.widget<Text>(find.text('KOT-001 sent to kitchen!'));

      // The regression: a light background was left with the theme's white
      // content colour, so the message rendered white-on-near-white.
      final background = snackBar.backgroundColor;
      final foreground = text.style?.color;
      expect(background, AppColors.textPrimary);
      expect(foreground, AppColors.surface);
      expect(foreground, isNot(background));
      expect(background, isNot(AppColors.surfaceVariant));
    });

    testWidgets('every variant states its own text colour', (tester) async {
      for (final show in <void Function(ScaffoldMessengerState)>[
        (m) => m.showSuccess('done'),
        (m) => m.showError('boom'),
        (m) => m.showWarning('careful'),
        (m) => m.showInfo('fyi'),
      ]) {
        await _raise(tester, show);
        final text = tester.widget<Text>(find.byType(Text).last);
        // Never inherit the content colour — inheriting is what broke.
        expect(text.style?.color, AppColors.surface);
      }
    });

    testWidgets('a new message replaces the one on screen', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                final m = ScaffoldMessenger.of(context);
                m.showSuccess('first');
                m.showSuccess('second');
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();

      // Without hideCurrentSnackBar the second waits out the first.
      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
    });
  });
}
