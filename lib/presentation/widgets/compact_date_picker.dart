import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/services/daily_limit_calculator.dart' show dateOnly;

/// Like [showDatePicker], but the calendar is only as tall as the month needs
/// (4–6 week rows), so Cancel / OK sit right under the last week instead of
/// below a fixed six-row gap.
Future<DateTime?> showCompactDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) =>
    showDialog<DateTime>(
      context: context,
      builder: (_) => CompactDatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: helpText,
      ),
    );

class CompactDatePickerDialog extends StatefulWidget {
  const CompactDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.helpText,
  });

  final DateTime initialDate, firstDate, lastDate;
  final String? helpText;

  /// Week rows needed for [month] with Sunday-first weeks.
  static int weeksIn(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    return ((first.weekday % 7) + days + 6) ~/ 7;
  }

  @override
  State<CompactDatePickerDialog> createState() => _CompactDatePickerDialogState();
}

class _CompactDatePickerDialogState extends State<CompactDatePickerDialog> {
  late final DateTime _first = dateOnly(widget.firstDate);
  late final DateTime _last = dateOnly(widget.lastDate);
  late DateTime _selected = _clamp(dateOnly(widget.initialDate));
  late DateTime _month = DateTime(_selected.year, _selected.month);

  DateTime _clamp(DateTime d) => d.isBefore(_first) ? _first : (d.isAfter(_last) ? _last : d);

  bool get _canPrev => DateTime(_month.year, _month.month).isAfter(DateTime(_first.year, _first.month));
  bool get _canNext => DateTime(_month.year, _month.month).isBefore(DateTime(_last.year, _last.month));

  void _shiftMonth(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dateOnly(DateTime.now());
    final offset = DateTime(_month.year, _month.month, 1).weekday % 7; // Sunday = 0
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = CompactDatePickerDialog.weeksIn(_month);
    final years = [for (var y = _first.year; y <= _last.year; y++) y];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.helpText != null) Text(widget.helpText!, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(DateFormat('EEE, MMM d').format(_selected), style: theme.textTheme.headlineMedium),
            const Divider(height: 24),
            // Month + year, with arrows.
            Row(children: [
              Text(DateFormat('MMMM').format(_month), style: theme.textTheme.titleSmall),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: _month.year,
                underline: const SizedBox(),
                isDense: true,
                items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                onChanged: (y) => setState(() {
                  final m = DateTime(y!, _month.month);
                  final lo = DateTime(_first.year, _first.month), hi = DateTime(_last.year, _last.month);
                  _month = m.isBefore(lo) ? lo : (m.isAfter(hi) ? hi : m);
                }),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Previous month',
                onPressed: _canPrev ? () => _shiftMonth(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: _canNext ? () => _shiftMonth(1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Center(
                    child: Text(d, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            // Only as many week rows as this month needs.
            for (var r = 0; r < rows; r++)
              Row(children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Builder(builder: (_) {
                        final n = r * 7 + c - offset + 1;
                        if (n < 1 || n > days) return const SizedBox();
                        final date = DateTime(_month.year, _month.month, n);
                        final enabled = !date.isBefore(_first) && !date.isAfter(_last);
                        final selected = date == _selected;
                        final isToday = date == today;
                        final size = math.min(40.0, MediaQuery.sizeOf(context).width / 9);
                        return Center(
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: enabled ? () => setState(() => _selected = date) : null,
                            child: Container(
                              width: size,
                              height: size,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected ? scheme.primary : null,
                                border: isToday && !selected ? Border.all(color: scheme.primary) : null,
                              ),
                              child: Text(
                                '$n',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: selected
                                      ? scheme.onPrimary
                                      : !enabled
                                          ? scheme.onSurface.withValues(alpha: 0.38)
                                          : isToday
                                              ? scheme.primary
                                              : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
              ]),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('OK')),
            ]),
          ]),
        ),
      ),
    );
  }
}
