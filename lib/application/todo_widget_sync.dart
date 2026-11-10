import 'dart:async';
import 'dart:convert';

import 'package:intl/intl.dart';

import '../data/db/app_database.dart';
import '../data/repositories/todo_repository.dart';
import '../platform/home_widget_service.dart';

/// Keeps the DoList home-screen widget in step with the app. Sends every
/// to-do that hasn't ended yet, with its start/end; the widget itself shows
/// only the ones active today, so it rolls over to a new day on its own.
class TodoWidgetSync {
  TodoWidgetSync(this._todos, this._service, {this.delay = const Duration(milliseconds: 600)});

  final TodoRepository _todos;
  final HomeWidgetService _service;
  final Duration delay;
  Timer? _timer;

  bool get isSupported => _service.isSupported;

  void schedule(DateTime now) {
    if (!_service.isSupported) return;
    _timer?.cancel();
    _timer = Timer(delay, () => push(now));
  }

  /// Sends the list now; returns the JSON (for tests).
  Future<String> push(DateTime now) async {
    final json = encode(await _todos.listNotEnded(now));
    await _service.update(json);
    return json;
  }

  /// Saves strike-outs made on the home-screen widget into the app's list.
  /// Returns how many were applied.
  Future<int> applyWidgetToggles() async {
    if (!_service.isSupported) return 0;
    final toggles = await _service.takeToggles();
    for (final e in toggles.entries) {
      await _todos.setDone(e.key, e.value);
    }
    return toggles.length;
  }

  static final _full = DateFormat('d MMM, h:mm a');
  static final _day = DateFormat('d MMM');

  /// Widget items: title, done, colour index, start/end (ms, for the
  /// widget's own "is it today?" check) and the "Start … · End …" line.
  static String encode(List<TodoRow> todos) => jsonEncode([
        for (final t in todos)
          {
            'id': t.id,
            'title': t.title,
            'done': t.done,
            'color': t.colorIndex,
            'startMs': t.start.millisecondsSinceEpoch,
            'endMs': t.end.millisecondsSinceEpoch,
            'when': whenLine(t),
          }
      ]);

  /// "9 Nov, 9:30 AM - 9 Nov, 10:30 AM" (dates only for all-day items).
  static String whenLine(TodoRow t) {
    final f = t.hasTime ? _full : _day;
    return '${f.format(t.start)} - ${f.format(t.end)}';
  }

  void dispose() => _timer?.cancel();
}
