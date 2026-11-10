import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/note_repository.dart';
import '../common.dart';
import '../dolist_style.dart';
import '../providers.dart';
import '../theme.dart';

/// Write / edit one note. Saves by itself when you go back; a note left
/// empty is not kept.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.note});

  /// Null for a new note.
  final NoteRow? note;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final NoteRepository _repo = ref.read(noteRepoProvider);
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');
  late int _color = widget.note?.colorIndex ?? DateTime.now().millisecond % NoteStyle.all.length;
  late bool _pinned = widget.note?.pinned ?? false;
  bool _deleted = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _changed {
    final n = widget.note;
    if (n == null) return true;
    return n.title != _title.text.trim() ||
        n.body != _body.text.trimRight() ||
        n.colorIndex != _color ||
        n.pinned != _pinned;
  }

  /// Called on the way out: create, update, or drop an emptied note.
  Future<void> _save() async {
    if (_deleted) return;
    final n = widget.note;
    final blank = NoteRepository.isBlank(_title.text, _body.text);
    if (n == null) {
      if (!blank) {
        await _repo.add(title: _title.text, body: _body.text, colorIndex: _color, pinned: _pinned);
      }
    } else if (blank) {
      await _repo.delete(n.id);
    } else if (_changed) {
      await _repo.edit(n.id, title: _title.text, body: _body.text, colorIndex: _color, pinned: _pinned);
    }
  }

  Future<void> _delete() async {
    final n = widget.note;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('It can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _deleted = true;
    if (n != null) await _repo.delete(n.id);
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, 'Note deleted', icon: Icons.delete_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final style = NoteStyle.of(_color);
    final text = Theme.of(context).textTheme;
    final edited = widget.note?.updatedAt;
    const ink = Palette.ink;
    InputDecoration plain(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: ink.withValues(alpha: 0.4)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isCollapsed: true,
        );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        backgroundColor: style.paper,
        appBar: AppBar(
          backgroundColor: style.paper,
          foregroundColor: ink,
          title: Text(widget.note == null ? 'New note' : 'Note', style: const TextStyle(color: ink)),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Unpin' : 'Pin to top',
              onPressed: () => setState(() => _pinned = !_pinned),
              icon: Icon(_pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: _pinned ? style.tape : ink),
            ),
            IconButton(
              tooltip: 'Delete note',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  TextField(
                    controller: _title,
                    autofocus: widget.note == null,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLength: 200,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: ink),
                    decoration: plain('Title'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _body,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 8,
                    maxLines: null,
                    style: text.bodyLarge?.copyWith(color: ink, height: 1.45),
                    decoration: plain('Write your thoughts…'),
                  ),
                ],
              ),
            ),
            // Colour dots + last edited.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                for (final (i, s) in NoteStyle.all.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Semantics(
                      button: true,
                      selected: i == _color,
                      label: 'Colour ${i + 1}',
                      child: GestureDetector(
                        onTap: () => setState(() => _color = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: s.paper,
                            shape: BoxShape.circle,
                            border: Border.all(color: i == _color ? s.tape : ink.withValues(alpha: 0.15), width: i == _color ? 3 : 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                if (edited != null)
                  Flexible(
                    child: Text('Edited ${DateFormat('d MMM, h:mm a').format(edited)}',
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(color: ink.withValues(alpha: 0.55))),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
