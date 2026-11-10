import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../common.dart';
import '../providers.dart';
import '../theme.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final spend = ref.watch(categorySpendProvider);
    final money = ref.watch(moneyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Palette.orange,
        foregroundColor: Colors.white,
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(children: [
        for (final c in categories)
          ListTile(
            leading: CategoryAvatar(c),
            title: Text(c.name),
            subtitle: c.monthlyCap == null
                ? null
                : Text('${money(spend[c.id] ?? 0)} of ${money(c.monthlyCap!)} cap'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, ref, c),
          ),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, CategoryRow? existing) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _CategoryEditor(existing),
      );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor(this.existing);
  final CategoryRow? existing;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _cap = TextEditingController(
      text: widget.existing?.monthlyCap?.toStringAsFixed(0) ?? '');
  late String _icon = widget.existing?.icon ?? 'other';
  late int _color = widget.existing?.color ?? categoryColors[5];

  @override
  void dispose() {
    _name.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final cap = double.tryParse(_cap.text);
    final repo = ref.read(categoryRepoProvider);
    final existing = widget.existing;
    if (existing == null) {
      await repo.add(name: name, icon: _icon, color: _color, cap: cap);
    } else {
      await repo.update(existing.copyWith(
          name: name, icon: _icon, color: _color, monthlyCap: Value(cap)));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${widget.existing!.name}?'),
        content: const Text('Its transactions will become uncategorized.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(categoryRepoProvider).delete(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(settingsProvider).currency.symbol;
    return SingleChildScrollView( // scrolls when the keyboard covers part of the sheet
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.existing == null ? 'New category' : 'Edit category',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(
          controller: _cap,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(
              labelText: 'Monthly cap (optional)', prefixText: '$symbol '),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in categoryIcons.entries)
            ChoiceChip(
              label: Icon(e.value, size: 20),
              selected: _icon == e.key,
              onSelected: (_) => setState(() => _icon = e.key),
            ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in categoryColors)
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Color(c),
                child: _color == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            ),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          if (widget.existing != null)
            TextButton(onPressed: _delete, child: const Text('Delete')),
          const Spacer(),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ]),
      ]),
    );
  }
}
