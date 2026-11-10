import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/presentation/widgets/quick_log_bar.dart';
import 'package:hydrochime/presentation/widgets/zen_circular_fluid_gauge.dart';

void main() {
  group('ZenCircularFluidGauge Widget Tests (Stitch Design)', () {
    testWidgets('renders current volume, target volume, percentage, and remaining text',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ZenCircularFluidGauge(
              currentVolumeMl: 2650,
              targetVolumeMl: 3450,
              percentage: 0.77,
              remainingMl: 800,
            ),
          ),
        ),
      );

      expect(find.text('2,650'), findsOneWidget);
      expect(find.text('/ 3,450 ml'), findsOneWidget);
      expect(find.text('77%'), findsOneWidget);
      expect(find.text('800 ml remaining'), findsOneWidget);
    });
  });

  group('QuickLogBar Widget Tests', () {
    testWidgets('renders +250, +500, +750 ml buttons and invokes callback on tap',
        (tester) async {
      int? loggedAmount;
      BeverageType? loggedType;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickLogBar(
              onLog: (amount, type) {
                loggedAmount = amount;
                loggedType = type;
              },
              onCustomAdd: () {},
            ),
          ),
        ),
      );

      expect(find.text('+250'), findsOneWidget);
      expect(find.text('+500'), findsOneWidget);
      expect(find.text('+750'), findsOneWidget);

      await tester.tap(find.text('+250'));
      await tester.pump();

      expect(loggedAmount, 250);
      expect(loggedType, BeverageType.water);

      await tester.tap(find.text('+500'));
      await tester.pump();

      expect(loggedAmount, 500);
      expect(loggedType, BeverageType.water);
    });

    testWidgets('ignores duplicate taps while an async onLog callback is still in flight',
        (tester) async {
      int calls = 0;
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickLogBar(
              onLog: (_, _) async {
                calls++;
                await completer.future;
              },
              onCustomAdd: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('+250'));
      await tester.pump();
      await tester.tap(find.text('+250'));
      await tester.pump();
      expect(calls, 1);

      completer.complete();
      await tester.pump();
      await tester.tap(find.text('+500'));
      await tester.pump();
      expect(calls, 2);
    });
  });
}

