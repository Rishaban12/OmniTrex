import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/services/merchant_categorizer.dart';

part 'app_database.g.dart';

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get icon => text().withDefault(const Constant('other'))();
  IntColumn get color => integer()();
  RealColumn get monthlyCap => real().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DataClassName('TxnRow')
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();

  /// 'expense' or 'refund'.
  TextColumn get kind => text()();
  IntColumn get categoryId => integer().nullable()();
  TextColumn get merchant => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();

  /// 'manual', 'sms' or 'notification'.
  TextColumn get source => text()();
  TextColumn get upiRef => text().nullable()();
  TextColumn get rawText => text().nullable()();
}

@DataClassName('FixedExpenseRow')
class FixedExpenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
}

@DataClassName('MerchantRuleRow')
class MerchantRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get keyword => text().unique()();
  IntColumn get categoryId => integer()();
  BoolColumn get learned => boolean().withDefault(const Constant(false))();
}

@DataClassName('PendingMessageRow')
class PendingMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get body => text()();
  TextColumn get sender => text().nullable()();
  TextColumn get source => text()();
  DateTimeColumn get receivedAt => dateTime()();
  RealColumn get amountGuess => real().nullable()();
  TextColumn get merchantGuess => text().nullable()();
}

/// DoList item, active from [forDate] (start) to [endDate] (end), inclusive.
@DataClassName('TodoRow')
class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();

  /// Legacy ('day' / 'week' / 'month' before v4); new rows use 'range'.
  TextColumn get scope => text()();

  /// Start date (inclusive).
  DateTimeColumn get forDate => dateTime()();

  /// End date (inclusive). Nullable only for rows written before v4.
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  /// Index into the sticky-note palette.
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

/// MindNotes: a free-form note (title and/or text), pinnable and coloured.
@DataClassName('NoteRow')
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// Index into the note palette (same pastels as DoList).
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DriftDatabase(tables: [
  Categories,
  Transactions,
  FixedExpenses,
  MerchantRules,
  PendingMessages,
  Todos,
  Notes,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 5;

  static QueryExecutor _open() => driftDatabase(
        name: 'daily_budget',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await m.createIndex(Index('txn_occurred_at',
              'CREATE INDEX txn_occurred_at ON transactions (occurred_at)'));
          await _seed();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: default categories adopt the illustration palette.
            for (final (name, _, color) in defaultCategories) {
              await (update(categories)..where((c) => c.name.equals(name)))
                  .write(CategoriesCompanion(color: Value(color)));
            }
          }
          if (from < 3) {
            // v3: DoList.
            await m.createTable(todos);
          } else if (from < 4) {
            // v4: start/end dates replace day/week/month lists.
            await m.addColumn(todos, todos.endDate);
          }
          if (from < 4) {
            for (final t in await select(todos).get()) {
              final s = t.forDate;
              final end = switch (t.scope) {
                'week' => DateTime(s.year, s.month, s.day + 6),
                'month' => DateTime(s.year, s.month + 1, 0),
                _ => s,
              };
              await (update(todos)..where((r) => r.id.equals(t.id)))
                  .write(TodosCompanion(endDate: Value(end), scope: const Value('range')));
            }
          }
          if (from < 5) {
            // v5: MindNotes.
            await m.createTable(notes);
          }
        },
      );

  static const defaultCategories = [
    ('Food', 'food', 0xFFF6C343),
    ('Travel', 'travel', 0xFF2F6BDE),
    ('Bills', 'bills', 0xFF5AAE7E),
    ('Shopping', 'shopping', 0xFFF0695B),
    ('Other', 'other', 0xFF8A94A6),
  ];

  /// Wipes all PocketPlan data (expenses, fixed expenses, parser messages,
  /// learned categories) and restores the default categories. DoList stays.
  Future<void> resetPocketPlan() => transaction(() async {
        await delete(transactions).go();
        await delete(fixedExpenses).go();
        await delete(pendingMessages).go();
        await delete(merchantRules).go();
        await delete(categories).go();
        await _seed();
      });

  Future<void> _seed() async {
    final ids = <String, int>{};
    for (final (i, (name, icon, color)) in defaultCategories.indexed) {
      ids[name] = await into(categories).insert(CategoriesCompanion.insert(
          name: name, icon: Value(icon), color: color, sortOrder: Value(i)));
    }
    await batch((b) {
      for (final entry in MerchantCategorizer.defaultKeywords.entries) {
        for (final kw in entry.value) {
          b.insert(merchantRules,
              MerchantRulesCompanion.insert(keyword: kw, categoryId: ids[entry.key]!),
              mode: InsertMode.insertOrIgnore);
        }
      }
    });
  }
}
