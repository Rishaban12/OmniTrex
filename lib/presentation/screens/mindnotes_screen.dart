import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/note_repository.dart';
import '../dolist_style.dart';
import '../providers.dart';
import '../theme.dart';
import 'note_editor_screen.dart';

/// MindNotes: write and keep free-form notes. Search on top, pinned notes
/// first, then the rest by last edit. Tap a note to open it, + for a new one.
class MindNotesScreen extends ConsumerWidget {
  const MindNotesScreen({super.key});

  static void open(BuildContext context, [NoteRow? note]) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    final query = ref.watch(noteQueryProvider);
    final list = notes.value ?? const <NoteRow>[];
    final pinned = [for (final n in list) if (n.pinned) n];
    final others = [for (final n in list) if (!n.pinned) n];

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'New note',
        backgroundColor: Palette.orange,
        foregroundColor: Colors.white,
        onPressed: () => open(context),
        child: const Icon(Icons.add, size: 28),
      ),
      body: BlobBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
              // Same header as DoList / PocketPlan: logo = back to the hub.
              SizedBox(
                height: 48,
                child: Row(children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.maybePop(context),
                      child: Image.asset('lib/data/static/logo.png', width: 36, height: 36, cacheWidth: 144),
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Wordmark('Mind', 'Notes', fontSize: 18, gradient: Wordmark.purpleGradient),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              _SearchBox(initial: query),
              const SizedBox(height: 16),
              if (notes.isLoading && list.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (list.isEmpty)
                _Empty(searching: query.trim().isNotEmpty)
              else ...[
                if (pinned.isNotEmpty) ...[
                  const _Label('Pinned'),
                  _NoteGrid(pinned),
                  if (others.isNotEmpty) const _Label('Others'),
                ],
                _NoteGrid(others),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends ConsumerStatefulWidget {
  const _SearchBox({required this.initial});
  final String initial;

  @override
  ConsumerState<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends ConsumerState<_SearchBox> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _set(String v) => ref.read(noteQueryProvider.notifier).state = v;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _text,
      onChanged: (v) => setState(() => _set(v)),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search notes',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _text.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _text.clear();
                  _set('');
                }),
              ),
        filled: true,
        fillColor: theme.cardTheme.color,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                )),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(children: [
          Icon(searching ? Icons.search_off_rounded : Icons.lightbulb_outline_rounded,
              size: 48, color: Palette.purple),
          const SizedBox(height: 12),
          Text(
            searching ? 'No notes match your search' : 'No notes yet — tap + to write your first one',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ]),
      );
}

/// Two columns on phones, more on wide screens.
class _NoteGrid extends StatelessWidget {
  const _NoteGrid(this.notes);
  final List<NoteRow> notes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth < 520 ? 2 : (box.maxWidth < 900 ? 3 : 4);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
          padding: const EdgeInsets.only(bottom: 12),
          children: [for (final n in notes) _NoteCard(n, key: ValueKey(n.id))],
        );
      });
}

class _NoteCard extends StatelessWidget {
  const _NoteCard(this.note, {super.key});
  final NoteRow note;

  @override
  Widget build(BuildContext context) {
    final style = NoteStyle.of(note.colorIndex);
    final text = Theme.of(context).textTheme;
    final heading = note.heading;
    // Body preview without repeating the first line when it is the heading.
    final preview = note.title.trim().isEmpty
        ? note.body.trim().split('\n').skip(1).join('\n').trim()
        : note.body.trim();
    return Material(
      color: style.paper,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => MindNotesScreen.open(context, note),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(heading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: Palette.ink)),
              ),
              if (note.pinned) Icon(Icons.push_pin_rounded, size: 16, color: style.tape),
            ]),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 6),
              Expanded(
                child: Text(preview,
                    overflow: TextOverflow.fade,
                    style: text.bodySmall?.copyWith(color: Palette.ink.withValues(alpha: 0.75), height: 1.35)),
              ),
            ] else
              const Spacer(),
            const SizedBox(height: 6),
            Text(DateFormat('d MMM').format(note.updatedAt),
                style: text.labelSmall?.copyWith(color: Palette.ink.withValues(alpha: 0.5))),
          ]),
        ),
      ),
    );
  }
}
