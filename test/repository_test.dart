import 'package:daily_budget/data/db/app_database.dart';
import 'package:daily_budget/data/repositories/budget_repositories.dart';
import 'package:daily_budget/data/repositories/todo_repository.dart';
import 'package:daily_budget/data/repositories/transaction_repository.dart';
import 'package:daily_budget/domain/services/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository txns;
  late CategoryRepository cats;
  late PendingMessageRepository pending;
  late FixedExpenseRepository fixed;
  late TodoRepository todos;

  setUp(() {
    db = memoryDb();
    txns = TransactionRepository(db);
    cats = CategoryRepository(db);
    pending = PendingMessageRepository(db);
    fixed = FixedExpenseRepository(db);
    todos = TodoRepository(db);
  });
  tearDown(() => db.close());

  final t0 = DateTime(2026, 11, 8, 12);
  ParsedTxn debit(double amount,
          {String? ref, String? merchant, DateTime? at, MessageSource src = MessageSource.sms, bool refund = false}) =>
      ParsedTxn(
        raw: RawMessage(body: 'test', source: src, receivedAt: at ?? t0),
        amount: amount,
        direction: refund ? TxnDirection.refund : TxnDirection.debit,
        occurredAt: at ?? t0,
        merchant: merchant,
        upiRef: ref,
      );
  Future<int> categoryId(String name) async =>
      (await cats.watchAll().first).firstWhere((c) => c.name == name).id;

  group('seed', () {
    test('default categories and merchant rules exist', () async {
      final names = (await cats.watchAll().first).map((c) => c.name);
      expect(names, containsAll(['Food', 'Travel', 'Bills', 'Shopping', 'Other']));
      expect(await txns.categorize('Swiggy'), await categoryId('Food'));
    });
  });

  group('ingest + dedupe', () {
    test('positive: new debit is stored and auto-categorised', () async {
      final id = await txns.ingest(debit(250, ref: '629512345678', merchant: 'Swiggy'));
      expect(id, isNotNull);
      final row = (await txns.all()).single;
      expect(row.categoryId, await categoryId('Food'));
      expect(row.source, 'sms');
    });

    test('negative: same UPI ref is skipped even much later', () async {
      await txns.ingest(debit(250, ref: '629512345678'));
      expect(await txns.ingest(debit(250, ref: '629512345678', at: t0.add(const Duration(hours: 3)))), isNull);
      expect(await txns.all(), hasLength(1));
    });

    test('negative: SMS + app notification for the same payment within 2 min', () async {
      await txns.ingest(debit(120));
      expect(await txns.ingest(debit(120, src: MessageSource.notification, at: t0.add(const Duration(seconds: 90)))),
          isNull);
    });

    test('positive: same amount 3 min apart is a new payment', () async {
      await txns.ingest(debit(120));
      expect(await txns.ingest(debit(120, at: t0.add(const Duration(minutes: 3)))), isNotNull);
    });

    test('positive: different refs are different payments even at the same time', () async {
      await txns.ingest(debit(120, ref: '111111111111'));
      expect(await txns.ingest(debit(120, ref: '222222222222')), isNotNull);
    });

    test('positive: a manual entry never blocks an auto-detected one', () async {
      await txns.addManual(amount: 120, categoryId: null, at: t0);
      expect(await txns.ingest(debit(120)), isNotNull);
    });

    test('positive: refund is not deduped against the expense', () async {
      await txns.ingest(debit(499));
      expect(await txns.ingest(debit(499, refund: true)), isNotNull);
      final kinds = (await txns.all()).map((t) => t.kind).toSet();
      expect(kinds, {'expense', 'refund'});
    });
  });

  group('manual + learning', () {
    test('note is trimmed; blank note stored as null', () async {
      await txns.addManual(amount: 10, categoryId: null, note: '  tea  ');
      await txns.addManual(amount: 20, categoryId: null, note: '   ');
      final notes = (await txns.all()).map((t) => t.note).toSet();
      expect(notes, {'tea', null});
    });

    test('correction teaches a rule for that merchant', () async {
      await txns.ingest(debit(80, merchant: 'Ramesh Kumar'));
      final row = (await txns.all()).single;
      expect(row.categoryId, isNull);
      await txns.recategorize(row, await categoryId('Travel'));
      expect(await txns.categorize('ramesh kumar'), await categoryId('Travel'));
    });

    test('learned rule overrides the built-in keyword', () async {
      await txns.ingest(debit(300, merchant: 'Swiggy'));
      await txns.recategorize((await txns.all()).single, await categoryId('Shopping'));
      expect(await txns.categorize('Swiggy'), await categoryId('Shopping'));
    });

    test('correcting twice updates the same rule (no duplicate error)', () async {
      await txns.ingest(debit(300, merchant: 'Swiggy'));
      final row = (await txns.all()).single;
      await txns.recategorize(row, await categoryId('Shopping'));
      await txns.recategorize(row, await categoryId('Bills'));
      expect(await txns.categorize('Swiggy'), await categoryId('Bills'));
    });
  });

  group('categories', () {
    test('deleting a category uncategorises its transactions and drops its rules', () async {
      final food = await categoryId('Food');
      await txns.ingest(debit(100, merchant: 'Swiggy'));
      await cats.delete(food);
      expect((await txns.all()).single.categoryId, isNull);
      expect(await txns.categorize('Swiggy'), isNull);
    });

    test('new category gets the next sort position', () async {
      await cats.add(name: 'Health', icon: 'health', color: 0xFF22B07D, cap: 2000);
      final list = await cats.watchAll().first;
      expect(list.last.name, 'Health');
      expect(list.last.monthlyCap, 2000);
    });
  });

  group('review queue', () {
    test('resolving a pending message creates the expense and clears it', () async {
      await pending.add(UnparsedMessage(
        RawMessage(body: 'Txn alert INR 760', source: MessageSource.sms, receivedAt: t0),
        amountGuess: 760,
      ));
      final row = (await pending.watchAll().first).single;
      await pending.resolveAsExpense(row, amount: 760, categoryId: await categoryId('Other'));
      expect(await pending.watchAll().first, isEmpty);
      expect((await txns.all()).single.amount, 760);
    });
  });

  group('fixed expenses', () {
    test('replaceAll swaps the whole list', () async {
      await fixed.replaceAll([('Rent', 15000), ('Netflix', 649)]);
      await fixed.replaceAll([('Rent', 16000)]);
      final list = await fixed.watchAll().first;
      expect(list.map((f) => (f.name, f.amount)), [('Rent', 16000.0)]);
    });
  });


  group('DoList (start → end dates)', () {
    final sun8 = DateTime(2026, 11, 8);
    Future<List<String>> active(DateTime d) async => (await todos.listActive(d)).map((t) => t.title).toList();

    test('positive: single-day to-do shows only on that day', () async {
      await todos.add(title: '  Buy milk ', start: sun8);
      expect(await active(sun8), ['Buy milk']);
      expect(await active(DateTime(2026, 11, 7)), isEmpty);
      expect(await active(DateTime(2026, 11, 9)), isEmpty);
    });

    test('positive: a range shows on every day from start to end (inclusive)', () async {
      await todos.add(title: 'Read a book', start: DateTime(2026, 11, 8), end: DateTime(2026, 11, 14));
      for (var d = 8; d <= 14; d++) {
        expect(await active(DateTime(2026, 11, d, 18)), ['Read a book'], reason: 'day $d');
      }
      expect(await active(DateTime(2026, 11, 15)), isEmpty);
    });

    test('positive: a range across month and year ends works', () async {
      await todos.add(title: 'Holiday prep', start: DateTime(2026, 12, 28), end: DateTime(2027, 1, 3));
      expect(await active(DateTime(2026, 12, 31)), ['Holiday prep']);
      expect(await active(DateTime(2027, 1, 3)), ['Holiday prep']);
    });

    test('negative: blank title or end before start is rejected', () async {
      expect(() => todos.add(title: '   ', start: sun8), throwsArgumentError);
      expect(() => todos.add(title: 'Oops', start: sun8, end: DateTime(2026, 11, 7)), throwsArgumentError);
      final id = await todos.add(title: 'Walk', start: sun8);
      expect(() => todos.edit(id, title: '', start: sun8, end: sun8), throwsArgumentError);
      expect(() => todos.edit(id, title: 'Walk', start: sun8, end: DateTime(2026, 11, 1)), throwsArgumentError);
    });

    test('upcoming lists future starts soonest first, not today\'s items', () async {
      await todos.add(title: 'today', start: sun8);
      await todos.add(title: 'later', start: DateTime(2026, 11, 20));
      await todos.add(title: 'soon', start: DateTime(2026, 11, 10), end: DateTime(2026, 11, 12));
      final up = (await todos.watchUpcoming(sun8).first).map((t) => t.title);
      expect(up, ['soon', 'later']);
    });

    test('purge: deleted the day after the end date, never before', () async {
      await todos.add(title: 'one day', start: sun8);
      await todos.add(title: 'week', start: sun8, end: DateTime(2026, 11, 14));
      await todos.add(title: 'future', start: DateTime(2026, 11, 20));

      expect(await todos.purgeExpired(DateTime(2026, 11, 8, 23, 59)), 0);
      expect(await todos.purgeExpired(DateTime(2026, 11, 9)), 1); // "one day" ended 8 Nov
      expect(await todos.purgeExpired(DateTime(2026, 11, 14, 22)), 0); // last day of "week"
      expect(await todos.purgeExpired(DateTime(2026, 11, 15)), 1); // "week" gone
      expect((await todos.watchUpcoming(DateTime(2026, 11, 15)).first).single.title, 'future');
    });

    test('times: 9:30–10:30 today is active all day today, not tomorrow', () async {
      await todos.add(title: 'Call', start: DateTime(2026, 11, 8, 9, 30), end: DateTime(2026, 11, 8, 10, 30));
      expect(await active(DateTime(2026, 11, 8, 0, 5)), ['Call']); // early morning
      expect(await active(DateTime(2026, 11, 8, 23)), ['Call']); // after it ended, same day
      expect(await active(DateTime(2026, 11, 9)), isEmpty);
      final row = (await todos.listActive(sun8)).single;
      expect((row.start, row.end, row.hasTime), (DateTime(2026, 11, 8, 9, 30), DateTime(2026, 11, 8, 10, 30), true));
    });

    test('times: an overnight range shows on both days, upcoming when it starts tomorrow', () async {
      await todos.add(title: 'Night shift', start: DateTime(2026, 11, 9, 22), end: DateTime(2026, 11, 10, 6));
      expect(await active(sun8), isEmpty);
      expect((await todos.watchUpcoming(sun8).first).single.title, 'Night shift');
      expect(await active(DateTime(2026, 11, 9)), ['Night shift']);
      expect(await active(DateTime(2026, 11, 10)), ['Night shift']);
      expect(await todos.purgeExpired(DateTime(2026, 11, 10, 20)), 0); // ends 10 Nov
      expect(await todos.purgeExpired(DateTime(2026, 11, 11)), 1);
    });

    test('negative: end time before start time on the same day is rejected', () async {
      expect(
        () => todos.add(title: 'Backwards', start: DateTime(2026, 11, 8, 15), end: DateTime(2026, 11, 8, 14)),
        throwsArgumentError,
      );
    });

    test('ticking keeps order; edit changes words and dates but keeps done', () async {
      final a = await todos.add(title: 'A', start: sun8);
      await todos.add(title: 'B', start: sun8);
      await todos.add(title: 'C', start: sun8);
      await todos.setDone(a, true);
      expect(await active(sun8), ['A', 'B', 'C']);

      await todos.edit(a, title: 'A longer', start: sun8, end: DateTime(2026, 11, 10));
      final row = (await todos.listActive(DateTime(2026, 11, 10))).single;
      expect((row.title, row.done, row.end), ('A longer', true, DateTime(2026, 11, 10)));

      await todos.delete(a);
      expect(await active(sun8), ['B', 'C']);
    });
  });
}