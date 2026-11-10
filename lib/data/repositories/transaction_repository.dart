import 'package:drift/drift.dart';

import '../../domain/services/amount_input.dart';
import '../../domain/services/daily_limit_calculator.dart';
import '../../domain/services/merchant_categorizer.dart';
import '../../domain/services/sms_parser.dart';
import '../db/app_database.dart';

extension TxnRowX on TxnRow {
  bool get isRefund => kind == 'refund';
  double get signedAmount => isRefund ? -amount : amount;
  SpendEntry get spendEntry => SpendEntry(occurredAt, signedAmount);
}

class TransactionRepository {
  TransactionRepository(this._db);
  final AppDatabase _db;

  Stream<List<TxnRow>> watchBetween(DateTime start, DateTime end) =>
      (_db.select(_db.transactions)
            ..where((t) =>
                t.occurredAt.isBiggerOrEqualValue(start) &
                t.occurredAt.isSmallerThanValue(end))
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch();

  Future<List<TxnRow>> all() => (_db.select(_db.transactions)
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
      .get();

  Future<int> addManual({
    required double amount,
    required int? categoryId,
    String? note,
    DateTime? at,
  }) =>
      _db.into(_db.transactions).insert(TransactionsCompanion.insert(
            amount: AmountInput.require(amount),
            kind: 'expense',
            categoryId: Value(categoryId),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
            occurredAt: at ?? DateTime.now(),
            source: 'manual',
          ));

  Future<void> update(TxnRow row) => _db.update(_db.transactions).replace(row);

  Future<void> delete(int id) =>
      (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();

  /// Changes a transaction's category and learns the merchant → category rule.
  Future<void> recategorize(TxnRow row, int categoryId) =>
      _db.transaction(() async {
        await update(row.copyWith(categoryId: Value(categoryId)));
        final merchant = row.merchant;
        if (merchant == null || merchant.trim().isEmpty) return;
        await _db.into(_db.merchantRules).insert(
              MerchantRulesCompanion.insert(
                keyword: MerchantCategorizer.normalize(merchant),
                categoryId: categoryId,
                learned: const Value(true),
              ),
              onConflict: DoUpdate(
                (_) => MerchantRulesCompanion(
                    categoryId: Value(categoryId), learned: const Value(true)),
                target: [_db.merchantRules.keyword],
              ),
            );
      });

  Future<int?> categorize(String? merchant) async {
    if (merchant == null) return null;
    final rules = await _db.select(_db.merchantRules).get();
    return MerchantCategorizer.match(merchant, rules.map(
        (r) => MerchantRuleData(r.keyword, r.categoryId, learned: r.learned)));
  }

  /// Inserts an auto-detected transaction unless it duplicates an existing
  /// one (same UPI ref, or same amount within 2 minutes). Returns the new id,
  /// or null when skipped.
  Future<int?> ingest(ParsedTxn txn) => _db.transaction(() async {
        final from = txn.occurredAt.subtract(Deduplicator.window);
        final to = txn.occurredAt.add(Deduplicator.window);
        final kind = txn.direction == TxnDirection.refund ? 'refund' : 'expense';
        final nearby = await (_db.select(_db.transactions)
              ..where((t) =>
                  t.kind.equals(kind) &
                  t.source.isNotValue('manual') &
                  (t.occurredAt.isBetweenValues(from, to) |
                      (txn.upiRef == null
                          ? const Constant(false)
                          : t.upiRef.equals(txn.upiRef!)))))
            .get();
        final dup = Deduplicator.isDuplicate(
          amount: txn.amount,
          at: txn.occurredAt,
          upiRef: txn.upiRef,
          existing: nearby.map((r) => (amount: r.amount, at: r.occurredAt, upiRef: r.upiRef)),
        );
        if (dup) return null;

        return _db.into(_db.transactions).insert(TransactionsCompanion.insert(
              amount: txn.amount,
              kind: kind,
              categoryId: Value(await categorize(txn.merchant)),
              merchant: Value(txn.merchant),
              occurredAt: txn.occurredAt,
              source: txn.raw.source.name,
              upiRef: Value(txn.upiRef),
              rawText: Value(txn.raw.body),
            ));
      });
}
