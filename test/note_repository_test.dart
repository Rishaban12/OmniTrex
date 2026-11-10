import 'package:daily_budget/data/db/app_database.dart';
import 'package:daily_budget/data/repositories/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repo;
  var clock = DateTime(2026, 11, 10, 9);
  setUp(() {
    db = memoryDb();
    clock = DateTime(2026, 11, 10, 9);
    repo = NoteRepository(db, clock: () => clock);
  });
  tearDown(() => db.close());

  void tick() => clock = clock.add(const Duration(minutes: 1));

  group('add', () {
    test('positive: title + text are stored (title trimmed)', () async {
      final id = await repo.add(title: '  Idea  ', body: 'Build a kite\nwith Ravi', colorIndex: 2);
      final n = (await repo.all()).single;
      expect(n.id, id);
      expect(n.title, 'Idea');
      expect(n.body, 'Build a kite\nwith Ravi');
      expect(n.colorIndex, 2);
      expect(n.pinned, isFalse);
      expect(n.createdAt, clock);
      expect(n.updatedAt, clock);
    });

    test('positive: text only or title only is fine', () async {
      await repo.add(body: 'just a thought');
      await repo.add(title: 'Only a title');
      expect(await repo.all(), hasLength(2));
    });

    test('negative: blank or whitespace-only notes are refused', () async {
      expect(() => repo.add(), throwsArgumentError);
      expect(() => repo.add(title: '   ', body: '\n\n  '), throwsArgumentError);
      expect(await repo.all(), isEmpty);
    });
  });

  group('edit / pin / delete', () {
    test('edit changes words and colour and bumps "edited" time', () async {
      final id = await repo.add(title: 'Shop', body: 'milk');
      tick();
      await repo.edit(id, title: 'Shopping', body: 'milk, bread', colorIndex: 3);
      final n = (await repo.all()).single;
      expect((n.title, n.body, n.colorIndex), ('Shopping', 'milk, bread', 3));
      expect(n.updatedAt, clock);
      expect(n.createdAt, isNot(clock));
    });

    test('negative: editing a note to blank is refused (it is deleted instead)', () async {
      final id = await repo.add(title: 'Keep');
      expect(() => repo.edit(id, title: ' ', body: ''), throwsArgumentError);
      expect((await repo.all()).single.title, 'Keep');
    });

    test('pinned notes come first, then newest edit first', () async {
      final a = await repo.add(title: 'A');
      tick();
      await repo.add(title: 'B');
      tick();
      await repo.add(title: 'C');
      expect((await repo.all()).map((n) => n.title), ['C', 'B', 'A']);

      await repo.setPinned(a, true);
      expect((await repo.all()).map((n) => n.title), ['A', 'C', 'B']);

      tick();
      final b = (await repo.all()).firstWhere((n) => n.title == 'B').id;
      await repo.edit(b, title: 'B', body: 'edited');
      expect((await repo.all()).map((n) => n.title), ['A', 'B', 'C']);
    });

    test('pinning does not count as an edit', () async {
      final id = await repo.add(title: 'X');
      final before = (await repo.all()).single.updatedAt;
      tick();
      await repo.setPinned(id, true);
      expect((await repo.all()).single.updatedAt, before);
    });

    test('delete removes only that note', () async {
      final a = await repo.add(title: 'A');
      await repo.add(title: 'B');
      await repo.delete(a);
      expect((await repo.all()).map((n) => n.title), ['B']);
    });
  });

  group('search', () {
    setUp(() async {
      await repo.add(title: 'Kite plan', body: 'Buy string');
      await repo.add(title: 'Groceries', body: 'MILK and bread');
      await repo.add(body: 'Call amma on Sunday');
    });

    Future<List<String>> find(String q) async => [for (final n in await repo.watchAll(query: q).first) n.heading];

    test('matches title or text, ignoring case and spaces around', () async {
      expect(await find('kite'), ['Kite plan']);
      expect(await find('  milk '), ['Groceries']);
      expect(await find('AMMA'), ['Call amma on Sunday']);
      expect(await find(''), hasLength(3));
    });

    test('negative: no match gives an empty list', () async {
      expect(await find('zebra'), isEmpty);
    });
  });

  test('heading falls back to the first line of text', () async {
    await repo.add(body: '\n  First line \nsecond');
    expect((await repo.all()).single.heading, 'First line');
  });

  test('Reset data (PocketPlan) keeps MindNotes', () async {
    await repo.add(title: 'Stay');
    await db.resetPocketPlan();
    expect((await repo.all()).single.title, 'Stay');
  });
}
