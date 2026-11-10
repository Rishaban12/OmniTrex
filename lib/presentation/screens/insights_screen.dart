import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/services/daily_limit_calculator.dart';
import '../common.dart';
import '../providers.dart';
import '../theme.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key, this.onBack});

  /// Back arrow action (PocketPlan: return to the Today tab).
  final VoidCallback? onBack;

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final txns = await ref.read(transactionRepoProvider).all();
    final cats = ref.read(categoryMapProvider);
    final rows = [
      ['Date', 'Time', 'Type', 'Amount', 'Category', 'Merchant', 'Note', 'Source', 'UPI Ref'],
      for (final t in txns)
        [
          DateFormat('yyyy-MM-dd').format(t.occurredAt),
          DateFormat('HH:mm').format(t.occurredAt),
          t.kind,
          t.amount.toStringAsFixed(2),
          cats[t.categoryId]?.name ?? 'Uncategorized',
          t.merchant ?? '',
          t.note ?? '',
          t.source,
          t.upiRef ?? '',
        ],
    ];
    String cell(Object v) {
      final s = '$v';
      return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final csv = rows.map((r) => r.map(cell).join(',')).join('\r\n');
    await FileSaver.instance.saveFile(
      name: 'expenses_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      bytes: Uint8List.fromList(utf8.encode(csv)),
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
    if (context.mounted) showSnack(context, 'Exported ${txns.length} transactions');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(dailyBudgetProvider).value;
    final money = ref.watch(moneyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      // Blobs run behind a see-through app bar.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: onBack == null ? null : BackButton(onPressed: onBack),
        title: const Text('Insights'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download),
            onPressed: () => _exportCsv(context, ref),
          ),
        ],
      ),
      body: BlobBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (budget != null)
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Safe to spend today', style: theme.textTheme.titleMedium),
                        Text(
                          money(budget.safeToSpend),
                          style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Spent ${money(budget.spentInCycle)} of ${money(budget.spendable)} this cycle · ${budget.daysRemaining} days left',
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // White card so the bars read cleanly over the blobs.
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Last 7 days', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const SizedBox(height: 220, child: _WeeklyChart()),
                ]),
              ),
              const SizedBox(height: 24),
              Text('By category (today)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              const _CategoryBreakdown(),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyChart extends ConsumerWidget {
  const _WeeklyChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(weekTransactionsProvider).value ?? const [];
    final today = ref.watch(todayProvider);
    final limit = ref.watch(dailyBudgetProvider).value?.baseDailyLimit ?? 0;
    final money = ref.watch(moneyProvider);
    final cats = ref.watch(categoryMapProvider);
    final scheme = Theme.of(context).colorScheme;

    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    // Net spend per category for each day; stacked in the category list order
    // so colors sit in the same position every day.
    final order = [...cats.keys, null];
    final perDay = [
      for (final d in days)
        {
          for (final id in order)
            id: txns
                .where((t) => t.categoryId == id && dateOnly(t.occurredAt) == d)
                .fold(0.0, (s, t) => s + t.signedAmount)
                .clamp(0, double.infinity)
                .toDouble(),
        },
    ];
    final totals = [for (final m in perDay) m.values.fold(0.0, (s, v) => s + v)];
    final maxY = [...totals, limit].reduce((a, b) => a > b ? a : b) * 1.2 + 1;

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) =>
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(DateFormat('E').format(days[v.toInt()]))),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItem: (g, _, rod, _) {
              final day = perDay[g.x];
              final base = TextStyle(color: scheme.onInverseSurface, fontSize: 12);
              return BarTooltipItem(
                '${DateFormat('EEE d MMM').format(days[g.x])} · ${money(rod.toY)}',
                base.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.left,
                children: [
                  for (final id in order)
                    if ((day[id] ?? 0) > 0) ...[
                      const TextSpan(text: '\n'),
                      TextSpan(
                        text: '● ',
                        style: base.copyWith(color: Color(cats[id]?.color ?? 0xFF8A94A6)),
                      ),
                      TextSpan(text: '${cats[id]?.name ?? 'Uncategorized'}  ${money(day[id]!)}', style: base),
                    ],
                ],
              );
            },
          ),
        ),
        barGroups: [
          for (final (i, v) in totals.indexed)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: v,
                  width: 22,
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.transparent,
                  rodStackItems: _stack(perDay[i], order, cats),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static List<BarChartRodStackItem> _stack(Map<int?, double> day, List<int?> order, Map<int, CategoryRow> cats) {
    final items = <BarChartRodStackItem>[];
    var from = 0.0;
    for (final id in order) {
      final v = day[id] ?? 0;
      if (v <= 0) continue;
      items.add(BarChartRodStackItem(from, from + v, Color(cats[id]?.color ?? 0xFF8A94A6)));
      from += v;
    }
    return items;
  }
}

class _CategoryBreakdown extends ConsumerStatefulWidget {
  const _CategoryBreakdown();

  @override
  ConsumerState<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends ConsumerState<_CategoryBreakdown> {
  /// Index of the hovered / touched slice, or -1.
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spend = ref.watch(todayCategorySpendProvider);
    final cats = ref.watch(categoryMapProvider);
    final money = ref.watch(moneyProvider);
    final entries = spend.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (s, e) => s + e.value);

    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No spending today yet')),
      );
    }

    final hovered = _touched >= 0 && _touched < entries.length ? entries[_touched] : null;

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 56,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      final i = event.isInterestedForInteractions
                          ? response?.touchedSection?.touchedSectionIndex ?? -1
                          : -1;
                      if (i != _touched) setState(() => _touched = i);
                    },
                  ),
                  sections: [
                    for (final (i, e) in entries.indexed)
                      PieChartSectionData(
                        value: e.value,
                        color: Color(cats[e.key]?.color ?? 0xFF8A94A6),
                        radius: i == _touched ? 50 : 40,
                        title: '${(e.value / total * 100).round()}%',
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                  ],
                ),
              ),
              // Center label: hovered category, or the cycle total.
              IgnorePointer(
                child: SizedBox(
                  width: 104,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hovered == null ? 'Total' : (cats[hovered.key]?.name ?? 'Uncategorized'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: hovered == null ? null : Color(cats[hovered.key]?.color ?? 0xFF8A94A6),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      FittedBox(
                        child: Text(
                          money(hovered?.value ?? total),
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Every category with a cap shows progress, even with zero spend.
        for (final c in cats.values.where((c) => c.monthlyCap != null && !spend.containsKey(c.id)))
          _CategoryRowTile(category: c, spent: 0, money: money),
        for (final e in entries) _CategoryRowTile(category: cats[e.key], spent: e.value, money: money),
      ],
    );
  }
}

class _CategoryRowTile extends StatelessWidget {
  const _CategoryRowTile({required this.category, required this.spent, required this.money});
  final CategoryRow? category;
  final double spent;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final cap = category?.monthlyCap;
    final scheme = Theme.of(context).colorScheme;
    final over = cap != null && spent > cap;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CategoryAvatar(category),
      title: Text(category?.name ?? 'Uncategorized'),
      subtitle: cap == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: (spent / cap).clamp(0, 1).toDouble(),
                color: over ? scheme.error : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
      trailing: Text(
        cap == null ? money(spent) : '${money(spent)} / ${money(cap)}',
        style: TextStyle(color: over ? scheme.error : null, fontWeight: FontWeight.w600),
      ),
    );
  }
}
