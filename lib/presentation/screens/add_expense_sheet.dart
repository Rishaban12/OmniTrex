import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/services/amount_input.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../common.dart';
import '../providers.dart';
import '../widgets/compact_date_picker.dart';

/// Two-tap add: open sheet (tap 1), type amount, tap a category (tap 2) = saved.
Future<void> showAddExpenseSheet(BuildContext context, {double? amount}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => AddExpenseSheet(initialAmount: amount),
    );

class AddExpenseSheet extends ConsumerStatefulWidget {
  const AddExpenseSheet({super.key, this.initialAmount});
  final double? initialAmount;

  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet> {
  late final _amount = TextEditingController(
      text: widget.initialAmount == null ? '' : widget.initialAmount!.toStringAsFixed(0));
  final _note = TextEditingController();
  final _amountFocus = FocusNode();
  bool _saving = false;
  Animation<double>? _routeAnimation;
  bool _focusScheduled = false;

  // Focus the amount only once the sheet has finished sliding in; focusing
  // mid-animation makes the sheet jump (and the keyboard pop) — the "blink".
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusScheduled) return;
    _focusScheduled = true;
    final anim = ModalRoute.of(context)?.animation;
    _routeAnimation = anim;
    if (anim == null || anim.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusAmount());
    } else {
      anim.addStatusListener(_onRouteStatus);
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _focusAmount();
    }
  }

  void _focusAmount() {
    if (mounted) _amountFocus.requestFocus();
  }

  /// Day the expense happened; defaults to today.
  late DateTime _day = ref.read(todayProvider);

  Future<void> _pickDay() async {
    final today = ref.read(todayProvider);
    final picked = await showCompactDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
      helpText: 'When did you spend it?',
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _amount.dispose();
    _note.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save(CategoryRow category) async {
    final amount = AmountInput.parse(_amount.text);
    if (amount == null) {
      showSnack(context, 'Enter an amount first');
      return;
    }
    setState(() => _saving = true);
    final today = ref.read(todayProvider);
    // Today keeps the real time; past days are logged at noon.
    final at = _day == today
        ? DateTime.now()
        : DateTime(_day.year, _day.month, _day.day, 12);
    await ref.read(transactionRepoProvider)
        .addManual(amount: amount, categoryId: category.id, note: _note.text, at: at);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final symbol = ref.watch(settingsProvider).currency.symbol;
    final theme = Theme.of(context);
    return SingleChildScrollView( // scrolls when the keyboard covers part of the sheet
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add expense', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            focusNode: _amountFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: theme.textTheme.displaySmall,
            decoration: InputDecoration(
              prefixText: '$symbol ',
              hintText: '0',
              border: InputBorder.none,
            ),
          ),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                hintText: 'Note (optional)', prefixIcon: Icon(Icons.notes)),
          ),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final today = ref.watch(todayProvider);
            final yesterday = DateTime(today.year, today.month, today.day - 1);
            final custom = _day != today && _day != yesterday;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('Today'),
                selected: _day == today,
                onSelected: (_) => setState(() => _day = today),
              ),
              ChoiceChip(
                label: const Text('Yesterday'),
                selected: _day == yesterday,
                onSelected: (_) => setState(() => _day = yesterday),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(custom ? DateFormat('d MMM').format(_day) : 'Pick date'),
                selected: custom,
                onSelected: (_) => _pickDay(),
              ),
            ]);
          }),
          const SizedBox(height: 16),
          Text('Tap a category to save', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in categories)
                ActionChip(
                  avatar: Icon(iconFor(c.icon), color: Color(c.color), size: 18),
                  label: Text(c.name),
                  onPressed: _saving ? null : () => _save(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edit category (learns merchant rule), note, or delete a transaction.
Future<void> showTransactionSheet(BuildContext context, TxnRow txn) =>
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TransactionSheet(txn),
    );

class _TransactionSheet extends ConsumerWidget {
  const _TransactionSheet(this.txn);
  final TxnRow txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final repo = ref.read(transactionRepoProvider);
    final theme = Theme.of(context);
    return SingleChildScrollView( // scrolls when the keyboard covers part of the sheet
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${txn.isRefund ? 'Refund ' : ''}${money(txn.amount)}',
              style: theme.textTheme.headlineMedium),
          Text([
            txn.merchant ?? txn.note ?? 'Expense',
            DateFormat('d MMM, h:mm a').format(txn.occurredAt),
            sourceLabel(txn.source),
            if (txn.upiRef != null) 'Ref ${txn.upiRef}',
          ].join(' · '), style: theme.textTheme.bodySmall),
          if (txn.rawText != null) ...[
            const SizedBox(height: 8),
            Text(txn.rawText!, style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          Text(txn.merchant == null ? 'Category' : 'Category (remembered for ${txn.merchant})',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in categories)
              ChoiceChip(
                avatar: Icon(iconFor(c.icon), color: Color(c.color), size: 18),
                label: Text(c.name),
                selected: c.id == txn.categoryId,
                onSelected: (_) async {
                  await repo.recategorize(txn, c.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ]),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () async {
              await repo.delete(txn.id);
              if (context.mounted) Navigator.pop(context);
            },
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            label: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class TransactionTile extends ConsumerWidget {
  const TransactionTile(this.txn, {super.key});
  final TxnRow txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    final category = ref.watch(categoryMapProvider)[txn.categoryId];
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CategoryAvatar(category),
      title: Text(txn.merchant ?? txn.note ?? category?.name ?? 'Expense',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${category?.name ?? 'Uncategorized'} · ${DateFormat('h:mm a').format(txn.occurredAt)} · ${sourceLabel(txn.source)}'),
      trailing: Text(
        txn.isRefund ? '+${money(txn.amount)}' : money(txn.amount),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: txn.isRefund ? Colors.green : scheme.onSurface,
            fontWeight: FontWeight.w600),
      ),
      onTap: () => showTransactionSheet(context, txn),
    );
  }
}
