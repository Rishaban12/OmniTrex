import 'package:drift/drift.dart';

import '../db/app_database.dart';

extension NoteRowX on NoteRow {
  /// Title if set, else the first line of the text.
  String get heading {
    if (title.trim().isNotEmpty) return title.trim();
    final first = body.trim().split('\n').first.trim();
    return first;
  }
}

/// MindNotes storage. A note needs a title or some text; blank notes are
/// never stored (an empty editor just discards itself).
class NoteRepository {
  NoteRepository(this._db, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final AppDatabase _db;
  final DateTime Function() _now;

  static bool isBlank(String title, String body) => title.trim().isEmpty && body.trim().isEmpty;

  /// Pinned first, then most recently edited. [query] filters by title or
  /// text (case-insensitive).
  Stream<List<NoteRow>> watchAll({String query = ''}) {
    final q = query.trim().toLowerCase();
    final select = _db.select(_db.notes)
      ..orderBy([
        (n) => OrderingTerm.desc(n.pinned),
        (n) => OrderingTerm.desc(n.updatedAt),
        (n) => OrderingTerm.desc(n.id),
      ]);
    if (q.isNotEmpty) {
      select.where((n) => n.title.lower().contains(q) | n.body.lower().contains(q));
    }
    return select.watch();
  }

  Future<List<NoteRow>> all() => watchAll().first;

  /// New note; returns its id. Throws [ArgumentError] when blank.
  Future<int> add({String title = '', String body = '', int colorIndex = 0, bool pinned = false}) {
    if (isBlank(title, body)) throw ArgumentError('A note needs a title or some text');
    final now = _now();
    return _db.into(_db.notes).insert(NotesCompanion.insert(
          title: Value(title.trim()),
          body: Value(body.trimRight()),
          colorIndex: Value(colorIndex),
          pinned: Value(pinned),
          createdAt: now,
          updatedAt: now,
        ));
  }

  /// Saves changes. Throws [ArgumentError] when it would leave the note blank
  /// (delete it instead).
  Future<void> edit(int id, {required String title, required String body, int? colorIndex, bool? pinned}) {
    if (isBlank(title, body)) throw ArgumentError('A note needs a title or some text');
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(
      title: Value(title.trim()),
      body: Value(body.trimRight()),
      colorIndex: colorIndex == null ? const Value.absent() : Value(colorIndex),
      pinned: pinned == null ? const Value.absent() : Value(pinned),
      updatedAt: Value(_now()),
    ));
  }

  /// Pin / unpin without counting as an edit (order among the rest is kept).
  Future<void> setPinned(int id, bool pinned) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(NotesCompanion(pinned: Value(pinned)));

  Future<void> delete(int id) => (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
}
