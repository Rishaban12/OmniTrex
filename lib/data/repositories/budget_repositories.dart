import 'package:drift/drift.dart';

import '../../domain/services/amount_input.dart';
import '../../domain/services/sms_parser.dart';
import '../db/app_database.dart';

class CategoryRepository {
  CategoryRepository(this._db);
  final AppDatabase _db;

  Stream<List<CategoryRow>> watchAll() => (_db.select(_db.categories)
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.id)]))
      .watch();

  Future<int> add({required String name, required String icon, required int color, double? cap}) async {
    final maxOrder = await (_db.selectOnly(_db.categories)
          ..addColumns([_db.categories.sortOrder.max()]))
        .map((r) => r.read(_db.categories.sortOrder.max()))
        .getSingle();
    return _db.into(_db.categories).insert(CategoriesCompanion.insert(
        name: name, icon: Value(icon), color: color, monthlyCap: Value(cap),
        sortOrder: Value((maxOrder ?? 0) + 1)));
  }

  Future<void> update(CategoryRow row) => _db.update(_db.categories).replace(row);

  /// Deletes a category; its transactions become uncategorized and its
  /// merchant rules are dropped.
  Future<void> delete(int id) => _db.transaction(() async {
        await (_db.update(_db.transactions)..where((t) => t.categoryId.equals(id)))
            .write(const TransactionsCompanion(categoryId: Value(null)));
        await (_db.delete(_db.merchantRules)..where((r) => r.categoryId.equals(id))).go();
        await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
      });
}

class FixedExpenseRepository {
  FixedExpenseRepository(this._db);
  final AppDatabase _db;

  Stream<List<FixedExpenseRow>> watchAll() => _db.select(_db.fixedExpenses).watch();

  /// Replaces the whole list. Rejects blank names and invalid amounts
  /// before touching the table, so a bad item never wipes the old list.
  Future<void> replaceAll(List<(String, double)> items) {
    for (final (name, amount) in items) {
      if (name.trim().isEmpty) throw ArgumentError.value(name, 'name', 'must not be blank');
      AmountInput.require(amount);
    }
    return _db.transaction(() async {
      await _db.delete(_db.fixedExpenses).go();
      for (final (name, amount) in items) {
        await _db.into(_db.fixedExpenses)
            .insert(FixedExpensesCompanion.insert(name: name.trim(), amount: amount));
      }
    });
  }
}

class PendingMessageRepository {
  PendingMessageRepository(this._db);
  final AppDatabase _db;

  Stream<List<PendingMessageRow>> watchAll() => (_db.select(_db.pendingMessages)
        ..orderBy([(p) => OrderingTerm.desc(p.receivedAt)]))
      .watch();

  Future<void> add(UnparsedMessage m) => _db.into(_db.pendingMessages).insert(
        PendingMessagesCompanion.insert(
          body: m.raw.body,
          sender: Value(m.raw.sender),
          source: m.raw.source.name,
          receivedAt: m.raw.receivedAt,
          amountGuess: Value(m.amountGuess),
          merchantGuess: Value(m.merchantGuess),
        ),
      );

  Future<void> remove(int id) =>
      (_db.delete(_db.pendingMessages)..where((p) => p.id.equals(id))).go();

  /// Converts a reviewed message into an expense in one step.
  Future<void> resolveAsExpense(PendingMessageRow row,
          {required double amount, required int categoryId}) =>
      _db.transaction(() async {
        await _db.into(_db.transactions).insert(TransactionsCompanion.insert(
              amount: AmountInput.require(amount),
              kind: 'expense',
              categoryId: Value(categoryId),
              merchant: Value(row.merchantGuess),
              occurredAt: row.receivedAt,
              source: row.source,
              rawText: Value(row.body),
            ));
        await remove(row.id);
      });
}
