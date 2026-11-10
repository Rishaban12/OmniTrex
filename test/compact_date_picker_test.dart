import 'package:daily_budget/presentation/widgets/compact_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadRoboto);

  test('rows = weeks the month actually spans (Sunday-first)', () {
    expect(CompactDatePickerDialog.weeksIn(DateTime(2026, 2)), 4); // Feb 2026: Sun 1st, 28 days
    expect(CompactDatePickerDialog.weeksIn(DateTime(2026, 11)), 5); // Nov 2026: Sun 1st, 30 days
    expect(CompactDatePickerDialog.weeksIn(DateTime(2026, 8)), 6); // Aug 2026: Sat 1st, 31 days
  });

  Future<DateTime?> open(WidgetTester tester, DateTime initial, {DateTime? first, DateTime? last}) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    DateTime? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showCompactDatePicker(
            context: context,
            initialDate: initial,
            firstDate: first ?? DateTime(2026),
            lastDate: last ?? DateTime(2027, 12, 31),
            helpText: 'End date',
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('OK sits right under the last week (no six-row gap)', (tester) async {
    await open(tester, DateTime(2026, 11, 10));
    final lastDay = tester.getRect(find.text('30'));
    final ok = tester.getRect(find.text('OK'));
    expect(ok.top - lastDay.bottom, lessThan(60), reason: 'gap between 30 and OK');
    expect(find.text('Tue, Nov 10'), findsOneWidget);
  });

  testWidgets('pick a day + OK returns it; Cancel returns null', (tester) async {
    DateTime? picked;
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked = await showCompactDatePicker(
            context: context,
            initialDate: DateTime(2026, 11, 10),
            firstDate: DateTime(2026),
            lastDate: DateTime(2027),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();
    expect(find.text('Wed, Nov 18'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 11, 18));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('negative: days before firstDate cannot be picked; arrows stop at the bounds', (tester) async {
    await open(tester, DateTime(2026, 11, 10), first: DateTime(2026, 11, 9), last: DateTime(2026, 11, 30));
    await tester.tap(find.text('5')); // before firstDate
    await tester.pumpAndSettle();
    expect(find.text('Tue, Nov 10'), findsOneWidget, reason: 'selection unchanged');
    final prev = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left));
    final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(prev.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets('month arrows move and change the row count', (tester) async {
    await open(tester, DateTime(2026, 2, 10)); // February: 4 rows
    expect(find.text('29'), findsNothing);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('March'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
  });
}
