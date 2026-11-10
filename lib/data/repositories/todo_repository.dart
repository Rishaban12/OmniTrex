import 'package:drift/drift.dart';

import '../../domain/services/daily_limit_calculator.dart';
import '../db/app_database.dart';

extension TodoRowX on TodoRow {
  /// Start date + time.
  DateTime get start => forDate;

  /// End date + time; rows from before v4 fall back to their start.
  DateTime get end => endDate ?? forDate;
  bool get isSingleDay => dateOnly(start) == dateOnly(end);

  /// False for date-only rows (both at midnight), which show no times.
  bool get hasTime => start != dateOnly(start) || end != dateOnly(end);
}

class TodoRepository {
  TodoRepository(this._db);
  final AppDatabase _db;

  /// To-dos whose start…end range touches [date]'s day, in the order added.
  /// Ticking one off keeps it in place (no jumping notes).
  Stream<List<TodoRow>> watchActive(DateTime date) => _active(date).watch();
  Future<List<TodoRow>> listActive(DateTime date) => _active(date).get();

  /// Everything not yet over (active today or upcoming), soonest first —
  /// what the home-screen widget needs to keep itself current.
  Future<List<TodoRow>> listNotEnded(DateTime date) {
    final day = dateOnly(date);
    return (_db.select(_db.todos)
          ..where((t) => t.endDate.isBiggerOrEqualValue(day) | (t.endDate.isNull() & t.forDate.isBiggerOrEqualValue(day)))
          ..orderBy([(t) => OrderingTerm.asc(t.forDate), (t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// To-dos that start on a later day than [date], soonest first.
  Stream<List<TodoRow>> watchUpcoming(DateTime date) => (_db.select(_db.todos)
        ..where((t) => t.forDate.isBiggerOrEqualValue(_nextDay(date)))
        ..orderBy([(t) => OrderingTerm.asc(t.forDate), (t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)]))
      .watch();

  SimpleSelectStatement<$TodosTable, TodoRow> _active(DateTime date) {
    final day = dateOnly(date);
    // Starts before tomorrow and ends at/after today's midnight.
    return _db.select(_db.todos)
      ..where((t) =>
          t.forDate.isSmallerThanValue(_nextDay(date)) &
          (t.endDate.isBiggerOrEqualValue(day) | (t.endDate.isNull() & t.forDate.isBiggerOrEqualValue(day))))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)]);
  }

  static DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  /// Adds a to-do for [start]…[end] (date + time; [end] defaults to
  /// [start]). Blank titles and end-before-start are rejected.
  Future<int> add({
    required String title,
    required DateTime start,
    DateTime? end,
    int colorIndex = 0,
  }) {
    final clean = _cleanTitle(title);
    final (s, e) = _range(start, end ?? start);
    return _db.into(_db.todos).insert(TodosCompanion.insert(
          title: clean,
          scope: 'range',
          forDate: s,
          endDate: Value(e),
          colorIndex: Value(colorIndex),
          createdAt: DateTime.now(),
        ));
  }

  /// Changes the words and/or dates of a to-do. Done state is kept.
  Future<void> edit(int id, {required String title, required DateTime start, required DateTime end}) {
    final clean = _cleanTitle(title);
    final (s, e) = _range(start, end);
    return (_db.update(_db.todos)..where((t) => t.id.equals(id))).write(TodosCompanion(
      title: Value(clean),
      forDate: Value(s),
      endDate: Value(e),
    ));
  }

  Future<void> setDone(int id, bool done) =>
      (_db.update(_db.todos)..where((t) => t.id.equals(id)))
          .write(TodosCompanion(done: Value(done)));

  Future<void> delete(int id) => (_db.delete(_db.todos)..where((t) => t.id.equals(id))).go();

  /// Deletes to-dos whose end date is before [now]'s day. Returns the count.
  Future<int> purgeExpired(DateTime now) {
    final today = dateOnly(now);
    return (_db.delete(_db.todos)
          ..where((t) =>
              t.endDate.isSmallerThanValue(today) | (t.endDate.isNull() & t.forDate.isSmallerThanValue(today))))
        .go();
  }

  static String _cleanTitle(String title) {
    final clean = title.trim();
    if (clean.isEmpty) throw ArgumentError.value(title, 'title', 'must not be blank');
    return clean;
  }

  /// Keeps minutes, drops seconds; end must not be before start.
  static (DateTime, DateTime) _range(DateTime start, DateTime end) {
    DateTime trim(DateTime d) => DateTime(d.year, d.month, d.day, d.hour, d.minute);
    final s = trim(start), e = trim(end);
    if (e.isBefore(s)) throw ArgumentError.value(end, 'end', 'must not be before start');
    return (s, e);
  }
}
