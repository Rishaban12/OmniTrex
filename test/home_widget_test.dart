import 'dart:convert';

import 'package:daily_budget/application/todo_widget_sync.dart';
import 'package:daily_budget/data/db/app_database.dart';
import 'package:daily_budget/data/repositories/todo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late TodoRepository repo;
  setUp(() {
    db = memoryDb();
    repo = TodoRepository(db);
  });
  tearDown(() => db.close());

  final now = DateTime(2026, 11, 9, 10);

  test('positive: sends today\'s + upcoming to-dos with start/end lines', () async {
    await repo.add(title: 'Study', start: DateTime(2026, 11, 9, 9, 30), end: DateTime(2026, 11, 9, 10, 30), colorIndex: 4);
    await repo.add(title: 'Trip', start: DateTime(2026, 11, 12), end: DateTime(2026, 11, 14));
    final fake = FakeHomeWidget(supported: true);
    final json = await TodoWidgetSync(repo, fake).push(now);

    final items = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    expect(items.map((i) => i['title']), ['Study', 'Trip']);
    expect(items.first['when'], '9 Nov, 9:30 AM - 9 Nov, 10:30 AM');
    expect(items.last['when'], '12 Nov - 14 Nov', reason: 'all-day items show dates only');
    expect(items.first['color'], 4);
    expect(items.first['startMs'], DateTime(2026, 11, 9, 9, 30).millisecondsSinceEpoch);
    expect(fake.updates.single, json);
  });

  test('done state is sent so the widget can strike it out', () async {
    final id = await repo.add(title: 'Read', start: now);
    await repo.setDone(id, true);
    final json = await TodoWidgetSync(repo, FakeHomeWidget(supported: true)).push(now);
    expect((jsonDecode(json) as List).single['done'], isTrue);
  });

  test('negative: finished to-dos are not sent', () async {
    await repo.add(title: 'Old', start: DateTime(2026, 11, 7), end: DateTime(2026, 11, 8));
    final json = await TodoWidgetSync(repo, FakeHomeWidget(supported: true)).push(now);
    expect(jsonDecode(json), isEmpty);
  });

  test('negative: on web / unsupported, schedule never calls the widget', () async {
    final fake = FakeHomeWidget(supported: false);
    final sync = TodoWidgetSync(repo, fake, delay: Duration.zero);
    sync.schedule(now);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fake.updates, isEmpty);
  });

  test('each widget item carries its to-do id (for tap-to-strike)', () async {
    final id = await repo.add(title: 'Kite', start: now);
    final json = await TodoWidgetSync(repo, FakeHomeWidget(supported: true)).push(now);
    expect((jsonDecode(json) as List).single['id'], id);
  });

  test('positive: strike-outs made on the widget are saved in the app', () async {
    final a = await repo.add(title: 'Study', start: now);
    final b = await repo.add(title: 'Home', start: now);
    await repo.setDone(b, true);
    final fake = FakeHomeWidget(supported: true)..toggles = {a: true, b: false};
    final applied = await TodoWidgetSync(repo, fake).applyWidgetToggles();

    expect(applied, 2);
    final rows = {for (final t in await repo.listNotEnded(now)) t.title: t.done};
    expect(rows, {'Study': true, 'Home': false});
    expect(await TodoWidgetSync(repo, fake).applyWidgetToggles(), 0, reason: 'handed over only once');
  });

  test('negative: unsupported platform never asks the widget', () async {
    final a = await repo.add(title: 'Study', start: now);
    final fake = FakeHomeWidget(supported: false)..toggles = {a: true};
    expect(await TodoWidgetSync(repo, fake).applyWidgetToggles(), 0);
    expect((await repo.listNotEnded(now)).single.done, isFalse);
  });
}
