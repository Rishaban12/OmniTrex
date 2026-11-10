import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/todo_repository.dart';
import '../../domain/services/daily_limit_calculator.dart' show dateOnly;
import '../common.dart';
import '../dolist_style.dart';
import '../providers.dart';
import '../widgets/compact_date_picker.dart';
import '../theme.dart';

/// DoList: to-dos with a start and end date, as pastel sticky notes.
/// "Today" lists everything whose dates include today; "Upcoming" the rest.
class DoListScreen extends ConsumerStatefulWidget {
  const DoListScreen({super.key});

  @override
  ConsumerState<DoListScreen> createState() => _DoListScreenState();
}

class _DoListScreenState extends ConsumerState<DoListScreen> {
  @override
  Widget build(BuildContext context) {
    final todayTodos = ref.watch(activeTodosProvider);
    final upcoming = ref.watch(upcomingTodosProvider).value ?? const <TodoRow>[];

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add to-do',
        backgroundColor: Palette.orange,
        foregroundColor: Colors.white,
        onPressed: () => _showAddSheet(context),
        child: const Icon(Icons.add, size: 28),
      ),
      body: BlobBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
              // 48 high, like the "What's next?" header (its theme button),
              // so the logo sits the same distance from the top.
              SizedBox(height: 48, child: Row(children: [
                // Logo = back to "What's next?" (same as PocketPlan).
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    // Same size as the "What's next?" header.
                    child: Image.asset('lib/data/static/logo.png', width: 36, height: 36, cacheWidth: 144),
                  ),
                ),
                const SizedBox(width: 3),
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Wordmark('Do', 'List', fontSize: 18, gradient: Wordmark.greenGradient),
                ),
              ])),
              const SizedBox(height: 16),
              const _HomeWidgetCard(),
              // Today's notes sit right under the home-screen widget card.
              ..._section(context, null, todayTodos.value ?? const [],
                  loading: todayTodos.isLoading && !todayTodos.hasValue, emptyText: 'Nothing planned for today yet'),
              if (upcoming.isNotEmpty) ..._section(context, 'Upcoming', upcoming),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _section(BuildContext context, String? title, List<TodoRow> list,
      {bool loading = false, String? emptyText}) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 28),
      if (title != null) ...[
        Row(children: [
          Expanded(
            child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (list.isNotEmpty)
            Text('${list.where((t) => t.done).length} / ${list.length}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
      ],
      if (loading)
        const LinearProgressIndicator()
      else if (list.isEmpty)
        _EmptyNotes(text: emptyText ?? '', onAdd: () => _showAddSheet(context))
      else
        _NotesGrid(todos: list),
    ];
  }

  Future<void> _showAddSheet(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => const _TodoEditor(),
      );
}

/// Places the DoList widget — a movable, resizable box on top of the user's
/// own wallpaper (the wallpaper itself is never changed).
class _HomeWidgetCard extends ConsumerWidget {
  const _HomeWidgetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = ref.watch(homeWidgetServiceProvider);
    return Material(
      color: Palette.soft(Palette.blue, theme.brightness),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        leading: const Icon(Icons.widgets_rounded),
        title: const Text('DoList on your home screen'),
        subtitle: Text(service.isSupported
            ? 'A small box with today\'s to-dos — move or resize it anywhere'
            : 'Available in the Android app'),
        trailing: !service.isSupported
            ? null
            : FilledButton.tonal(
                onPressed: () async {
                  final ok = await service.requestPin();
                  if (!context.mounted || ok) return;
                  showSnack(context, 'Long-press your home screen → Widgets → OmniTrex → DoList',
                      icon: Icons.widgets_rounded);
                },
                child: const Text('Add'),
              ),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.text, required this.onAdd});
  final String text;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Text(text,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add your first to-do')),
    ]);
  }
}

/// Responsive grid of notes: 1 column on very small phones, 2 on phones,
/// 3–4 on tablets / desktop.
class _NotesGrid extends StatelessWidget {
  const _NotesGrid({required this.todos});
  final List<TodoRow> todos;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        const gap = 14.0;
        final cols = box.maxWidth < 340
            ? 1
            : box.maxWidth < 620
                ? 2
                : box.maxWidth < 900
                    ? 3
                    : 4;
        final itemW = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap + 6,
          children: [
            // Keyed by to-do id: each box is tied to its own to-do, so ticking
            // one can never show up on another.
            for (final (i, t) in todos.indexed)
              SizedBox(
                key: ValueKey(t.id),
                width: itemW,
                child: StickyNote(todo: t, tilt: i.isEven ? -1 : 1),
              ),
          ],
        );
      });
}

/// A pastel sticky note: washi-tape strip, dashed stitched edge, folded
/// corner and a slight tilt. Tap = done/undone, long-press = edit.
class StickyNote extends ConsumerWidget {
  const StickyNote({super.key, required this.todo, this.tilt = 1});
  final TodoRow todo;
  final int tilt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = NoteStyle.of(todo.colorIndex);
    final theme = Theme.of(context);
    final repo = ref.read(todoRepoProvider);

    return Transform.rotate(
      angle: tilt * 1.2 * math.pi / 180,
      child: Stack(clipBehavior: Clip.none, children: [
        Material(
          color: style.paper,
          elevation: 2,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final nowDone = !todo.done;
              await repo.setDone(todo.id, nowDone);
              if (nowDone && context.mounted) _showCheer(context, style);
            },
            onLongPress: () => _edit(context),
            child: CustomPaint(
              painter: _NoteEdgePainter(style.tape),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 108),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: todo.done ? style.tape : Colors.transparent,
                        border: Border.all(color: style.tape, width: 2.5),
                      ),
                      child: todo.done ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          todo.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: todo.done ? Palette.ink.withValues(alpha: 0.45) : Palette.ink,
                            decoration: todo.done ? TextDecoration.lineThrough : null,
                            decorationThickness: 2,
                          ),
                        ),
                        // When: times and/or dates (nothing for a plain
                        // all-day "today" item).
                        if (_when(todo, ref.watch(todayProvider)) case final whenText?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              whenText,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: style.tape,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ]),
                    ),
                    // Edit words / delete.
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        tooltip: 'Edit',
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        color: style.tape,
                        onPressed: () => _edit(context),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        // Washi tape, slightly crooked, overlapping the top edge.
        Positioned(
          top: -9,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.rotate(
              angle: -tilt * 4 * math.pi / 180,
              child: Container(
                width: 64,
                height: 20,
                decoration: BoxDecoration(
                  color: style.tape.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  static const _cheers = ['Done! 🎉', 'Nice one! ✨', 'Crushed it! 💪', 'One less thing! 🙌', 'Way to go! 🌟'];
  static String _celebrate() => _cheers[DateTime.now().millisecond % _cheers.length];

  /// "9:30 AM – 10:30 AM", "12 Nov · 9:30 AM – 10:30 AM",
  /// "8 Nov, 9:30 AM – 14 Nov, 6:00 PM", "8 Nov – 14 Nov", or null.
  static String? _when(TodoRow t, DateTime today) {
    final day = DateFormat('d MMM'), time = DateFormat('h:mm a');
    if (t.isSingleDay) {
      final isToday = dateOnly(t.start) == today;
      if (!t.hasTime) return isToday ? null : day.format(t.start);
      final times = t.start == t.end ? time.format(t.start) : '${time.format(t.start)} – ${time.format(t.end)}';
      return isToday ? times : '${day.format(t.start)} · $times';
    }
    final full = t.hasTime ? DateFormat('d MMM, h:mm a') : day;
    return '${full.format(t.start)} – ${full.format(t.end)}';
  }

  Future<void> _edit(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => _TodoEditor(existing: todo),
      );

  /// Cheer popup in the ticked note's own colours.
  static void _showCheer(BuildContext context, NoteStyle style) =>
      showSnack(context, _celebrate(), style: style, icon: Icons.check_circle_rounded);
}

/// Dashed "stitched" edge inset from the border + folded corner.
class _NoteEdgePainter extends CustomPainter {
  const _NoteEdgePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius((Offset.zero & size).deflate(7), const Radius.circular(11));
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final metric in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 11) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      }
    }
    const fold = 18.0;
    canvas.drawPath(
      Path()
        ..moveTo(size.width - fold, size.height)
        ..lineTo(size.width, size.height - fold)
        ..lineTo(size.width - fold, size.height - fold)
        ..close(),
      Paint()..color = color.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_NoteEdgePainter old) => old.color != color;
}

/// Add or edit a to-do.
class _TodoEditor extends ConsumerStatefulWidget {
  const _TodoEditor({this.existing});
  final TodoRow? existing;

  @override
  ConsumerState<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends ConsumerState<_TodoEditor> {
  static final _fmt = DateFormat('d MMM, h:mm a');
  late final _title = TextEditingController(text: widget.existing?.title);

  /// New to-dos: next half hour → one hour later.
  static DateTime _nextHalfHour() {
    final now = DateTime.now();
    final add = now.minute < 30 ? 30 - now.minute : 60 - now.minute;
    return DateTime(now.year, now.month, now.day, now.hour, now.minute + add);
  }

  late DateTime _start = widget.existing?.start ?? _nextHalfHour();
  late DateTime _end = widget.existing?.end ?? _start.add(const Duration(hours: 1));
  late final _startText = TextEditingController(text: _fmt.format(_start));
  late final _endText = TextEditingController(text: _fmt.format(_end));
  late int _color = widget.existing?.colorIndex ?? DateTime.now().second % NoteStyle.all.length;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _startText.dispose();
    _endText.dispose();
    super.dispose();
  }

  /// Date picker, then time picker. Cancelling the time keeps the old time.
  Future<void> _pick({required bool start}) async {
    final today = ref.read(todayProvider);
    final firstDay = start ? DateTime(today.year - 1) : dateOnly(_start);
    final current = start ? _start : _end;
    final day = await showCompactDatePicker(
      context: context,
      initialDate: current.isBefore(firstDay) ? firstDay : current,
      firstDate: firstDay,
      lastDate: DateTime(2100, 12, 31),
      helpText: start ? 'Start date' : 'End date',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: start ? 'Start time' : 'End time',
    );
    final t = time ?? TimeOfDay.fromDateTime(current);
    final picked = DateTime(day.year, day.month, day.day, t.hour, t.minute);
    setState(() {
      if (start) {
        // Keep the length; a start after the end pushes the end along.
        final length = _end.difference(_start);
        _start = picked;
        if (_end.isBefore(_start)) _end = _start.add(length.isNegative ? Duration.zero : length);
      } else {
        _end = picked.isBefore(_start) ? _start : picked;
      }
      _startText.text = _fmt.format(_start);
      _endText.text = _fmt.format(_end);
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Write something to do');
      return;
    }
    final repo = ref.read(todoRepoProvider);
    final existing = widget.existing;
    if (existing == null) {
      await repo.add(title: _title.text, start: _start, end: _end, colorIndex: _color);
    } else {
      await repo.edit(existing.id, title: _title.text, start: _start, end: _end);
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _dateField(String label, TextEditingController c, {required bool start}) => TextField(
        controller: c,
        readOnly: true,
        mouseCursor: SystemMouseCursors.click,
        onTap: () => _pick(start: start),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_month_rounded, size: 20),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.existing != null;
    return SingleChildScrollView( // scrolls when the keyboard covers part of the sheet
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(editing ? 'Edit to-do' : 'New to-do', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          autofocus: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(hintText: 'What do you want to get done?', errorText: _error),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _dateField('Start', _startText, start: true)),
          const SizedBox(width: 12),
          Expanded(child: _dateField('End', _endText, start: false)),
        ]),
        if (!editing) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (i, s) in NoteStyle.all.indexed)
              GestureDetector(
                onTap: () => setState(() => _color = i),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: s.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: s.tape, width: _color == i ? 3 : 1.5),
                  ),
                  child: _color == i ? Icon(Icons.check_rounded, size: 18, color: s.tape) : null,
                ),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        Row(children: [
          if (editing)
            TextButton.icon(
              onPressed: () async {
                await ref.read(todoRepoProvider).delete(widget.existing!.id);
                if (context.mounted) Navigator.pop(context);
              },
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              label: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
            ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(120, 48),
            ),
            onPressed: _save,
            child: Text(editing ? 'Save' : 'Add'),
          ),
        ]),
      ]),
    );
  }
}
