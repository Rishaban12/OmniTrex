import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../domain/services/amount_input.dart';
import '../../domain/services/spend_summary.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/services/daily_limit_calculator.dart';
import '../providers.dart';
import '../widgets/compact_date_picker.dart';
import '../theme.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, this.editing = false});

  /// True when opened from Settings rather than first launch.
  final bool editing;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _budget;
  late DateTime _startDate;
  late DateTime _endDate; // inclusive
  late String _currency;

  /// End stays "one month after start" until the user picks it explicitly.
  bool _endTouched = false;

  static final _fmt = DateFormat('d MMMM yyyy');
  int get _totalDays => calendarDaysBetween(_startDate, _endDate) + 1;

  static DateTime _monthAfter(DateTime start) {
    final end = BudgetCycle.containing(start, start.day).end;
    return DateTime(end.year, end.month, end.day - 1);
  }

  Future<DateTime?> _pick(DateTime initial, DateTime first, String help) {
    final now = DateTime.now();
    return showCompactDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first.isBefore(DateTime(now.year - 5)) ? first : DateTime(now.year - 5),
      lastDate: DateTime(2100, 12, 31),
      helpText: help,
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await _pick(_startDate, DateTime(DateTime.now().year - 5), 'Start date');
    if (picked == null) return;
    setState(() {
      _startDate = dateOnly(picked);
      if (!_endTouched || _endDate.isBefore(_startDate)) {
        _endDate = _monthAfter(_startDate);
      }
      _syncText();
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await _pick(_endDate, _startDate, 'End date');
    if (picked == null) return;
    setState(() {
      _endDate = dateOnly(picked);
      _endTouched = true;
      _syncText();
    });
  }

  void _syncText() {
    _startText.text = _fmt.format(_startDate);
    _endText.text = _fmt.format(_endDate);
  }

  late final _startText = TextEditingController(text: _fmt.format(_startDate));
  late final _endText = TextEditingController(text: _fmt.format(_endDate));
  final _fixed = <(TextEditingController, TextEditingController)>[];

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _budget = TextEditingController(
        text: s.monthlyBudget > 0 ? s.monthlyBudget.toStringAsFixed(0) : '');
    final cycle = s.cycleFor(DateTime.now());
    _startDate = cycle.start;
    _endDate = DateTime(cycle.end.year, cycle.end.month, cycle.end.day - 1);
    _endTouched = _endDate != _monthAfter(_startDate);
    _currency = s.currencyCode;
    final existing = ref.read(fixedExpensesProvider).value ?? const [];
    for (final f in existing) {
      _fixed.add((TextEditingController(text: f.name),
          TextEditingController(text: f.amount.toStringAsFixed(0))));
    }
    if (_fixed.isEmpty && !widget.editing) _addFixed('Rent');
  }

  void _addFixed([String name = '']) => _fixed
      .add((TextEditingController(text: name), TextEditingController()));

  @override
  void dispose() {
    _budget.dispose();
    _startText.dispose();
    _endText.dispose();
    for (final (a, b) in _fixed) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  double get _fixedTotal => SpendSummary.fixedTotal(_fixed.map((f) => AmountInput.parse(f.$2.text) ?? 0));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final budget = AmountInput.parse(_budget.text);
    if (budget == null) return;
    // Rows with no name or no valid amount are skipped (left blank).
    final items = [
      for (final (name, amount) in _fixed)
        if (name.text.trim().isNotEmpty)
          if (AmountInput.parse(amount.text) case final value?) (name.text.trim(), value),
    ];
    await ref.read(fixedExpenseRepoProvider).replaceAll(items);
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          setupDone: true,
          monthlyBudget: budget,
          cycleStartDay: _startDate.day,
          periodStart: _startDate,
          periodEnd: _endDate,
          currencyCode: _currency,
        ));
    if (widget.editing && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = Currency.byCode(_currency).symbol;
    final budget = AmountInput.parse(_budget.text) ?? 0;
    final spendable = budget - _fixedTotal;
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing ? 'Budget & fixed expenses' : 'Set up your budget')),
      body: Form(
        key: _form,
        child: ListView(
          key: const PageStorageKey('pocketplan-setup'),
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Expense amount', style: theme.textTheme.titleMedium),
            ),
            Row(children: [
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String>(
                  initialValue: _currency,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    for (final c in Currency.all)
                      DropdownMenuItem(value: c.code, child: Text('${c.symbol.trim()} ${c.code}')),
                  ],
                  onChanged: (v) => setState(() => _currency = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _budget,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: InputDecoration(labelText: 'Monthly amount', prefixText: '$symbol '),
                  validator: (v) => AmountInput.parse(v) != null ? null : 'Enter your monthly budget',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            // Read-only fields so hover/focus get the same outline as other inputs.
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _startText,
                  readOnly: true,
                  mouseCursor: SystemMouseCursors.click,
                  onTap: _pickStartDate,
                  style: theme.textTheme.titleMedium,
                  decoration: const InputDecoration(
                    labelText: 'Start date',
                    suffixIcon: Icon(Icons.calendar_month_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _endText,
                  readOnly: true,
                  mouseCursor: SystemMouseCursors.click,
                  onTap: _pickEndDate,
                  style: theme.textTheme.titleMedium,
                  decoration: const InputDecoration(
                    labelText: 'End date',
                    suffixIcon: Icon(Icons.event_rounded),
                  ),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text('$_totalDays days', style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: 24),
            Text('Fixed expenses', style: theme.textTheme.titleMedium),
            for (final (i, (name, amount)) in _fixed.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                        controller: name,
                        decoration: const InputDecoration(hintText: 'Name')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: InputDecoration(hintText: 'Amount', prefixText: '$symbol '),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _fixed.removeAt(i)),
                  ),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(_addFixed),
                icon: const Icon(Icons.add),
                label: const Text('Add fixed expense'),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                title: const Text('Spendable this month'),
                subtitle: Text('≈ $symbol${(spendable / _totalDays).clamp(0, double.infinity).toStringAsFixed(0)} per day'),
                trailing: Text('$symbol${spendable.toStringAsFixed(0)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: spendable < 0 ? theme.colorScheme.error : null)),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: Palette.orange,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: Text(widget.editing ? 'Save' : 'Start tracking'),
            ),
          ],
        ),
      ),
    );
  }
}
