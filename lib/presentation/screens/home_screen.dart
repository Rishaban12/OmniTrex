import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../domain/services/daily_limit_calculator.dart';
import '../common.dart';
import '../providers.dart';
import '../theme.dart';
import 'add_expense_sheet.dart';
import 'setup_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.onOpenReview});
  final VoidCallback? onOpenReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetAsync = ref.watch(dailyBudgetProvider);
    final todayTxns = ref.watch(todayTransactionsProvider);
    final money = ref.watch(moneyProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Scaffold(
      body: budgetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (b) => BlobBackground(
          child: SafeArea(
            bottom: false,
            child: ListView(
              // Own scroll memory: setup and home share a route, and without
              // this home would open at setup's scroll offset.
              key: const PageStorageKey('pocketplan-home'),
              // Bottom space so the + button never covers the last row.
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              children: [
                // Logo (tap → back to the "What's next?" hub) and date. 48 high
                // like the "What's next?" header, so the top gap matches.
                SizedBox(height: 48, child: Row(children: [
                  // Plain tap target: no hover tint, no tooltip.
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context, rootNavigator: true).maybePop(),
                      child: Image.asset('lib/data/static/logo.png', width: 36, height: 36, cacheWidth: 144),
                    ),
                  ),
                  const SizedBox(width: 3),
                  // Nudged down so the letters (not letters + swoosh) sit at
                  // the logo's vertical centre.
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Wordmark('Pocket', 'Plan', fontSize: 16, gradient: Wordmark.pinkGradient),
                  ),
                  const SizedBox(width: 12),
                  // The date takes all the rest of the row and sits at its right
                  // edge; it only shrinks when it doesn't fit (narrow screen or
                  // a large system font).
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(DateFormat('EEEE, d MMM').format(ref.watch(todayProvider)),
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ])),
                const SizedBox(height: 20),
                // Big stacked headline, SpeakSync style.
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(money(b.remainingToday.abs()),
                            style: theme.textTheme.displayLarge?.copyWith(
                                fontSize: 64,
                                color: b.isOverLimit ? Palette.coral : null)),
                      ),
                      Text(b.isOverLimit ? 'over today' : 'left today',
                          style: theme.textTheme.displaySmall?.copyWith(color: muted)),
                    ]),
                  ),
                  ProgressRing(
                    progress: b.progress,
                    size: 88,
                    child: Text('${(b.progress * 100).clamp(0, 999).round()}%',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 20),
                _TilesRow(budget: b),
                const SizedBox(height: 16),
                _SpendBars(budget: b),
                const SizedBox(height: 28),
                Text('Today', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                ...todayTxns.when(
                  loading: () => [const LinearProgressIndicator()],
                  error: (e, _) => [Text('$e')],
                  data: (list) => list.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text('Nothing spent yet.\nNice start.',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                    color: muted, fontWeight: FontWeight.w700)),
                          )
                        ]
                      : [
                          Card(
                            margin: EdgeInsets.zero,
                            child: Column(children: [for (final t in list) TransactionTile(t)]),
                          ),
                        ],
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add expense',
        backgroundColor: Palette.orange,
        foregroundColor: Colors.white,
        onPressed: () => showAddExpenseSheet(context),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}

/// Waveform-style bars: 5 days before today, today, 5 days after — kept
/// inside the current budget cycle (the window shifts near its edges).
/// The arrow below expands a month calendar.
class _SpendBars extends ConsumerStatefulWidget {
  const _SpendBars({required this.budget});
  final DailyBudget budget;

  @override
  ConsumerState<_SpendBars> createState() => _SpendBarsState();
}

class _SpendBarsState extends ConsumerState<_SpendBars> {
  static const _side = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final budget = widget.budget;
    final txns = ref.watch(cycleTransactionsProvider).value ?? const [];
    final today = ref.watch(todayProvider);
    final cycle = budget.cycle;
    final theme = Theme.of(context);

    DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
    final lastDay = addDays(cycle.end, -1);
    final span = _side * 2; // window length minus one
    var start = addDays(today, -_side);
    if (start.isBefore(cycle.start)) start = cycle.start;
    var end = addDays(start, span);
    if (end.isAfter(lastDay)) {
      end = lastDay;
      start = addDays(end, -span);
      if (start.isBefore(cycle.start)) start = cycle.start;
    }
    final days = [
      for (var d = start; !d.isAfter(end); d = addDays(d, 1)) d,
    ];
    final todayIndex = days.indexOf(today);
    final totals = [
      for (final d in days)
        txns
            .where((t) => dateOnly(t.occurredAt) == d)
            .fold(0.0, (s, t) => s + t.signedAmount)
            .clamp(0, double.infinity)
            .toDouble(),
    ];
    final peak = [...totals, budget.dailyLimit, 1.0].reduce((a, b) => a > b ? a : b);
    const maxH = 64.0;
    final ink = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color?.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        SizedBox(
          height: maxH + 8,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, v) in totals.indexed)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: i == todayIndex ? const EdgeInsets.all(3) : EdgeInsets.zero,
                  decoration: i == todayIndex
                      ? BoxDecoration(
                          color: Palette.soft(Palette.yellow, theme.brightness),
                          borderRadius: BorderRadius.circular(6))
                      : null,
                  child: i > todayIndex
                      // Upcoming day: faint empty slot.
                      ? Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        )
                      : Container(
                          height: (v / peak * maxH).clamp(4, maxH),
                          decoration: BoxDecoration(
                            color: i == todayIndex
                                ? (budget.isOverLimit ? Palette.coral : ink)
                                : ink.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: Text(
                '${d.day}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: i == todayIndex ? FontWeight.w800 : FontWeight.w400,
                  color: i > todayIndex ? ink.withValues(alpha: 0.4) : null,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 2),
        Text(DateFormat('MMMM yyyy').format(today),
            style: theme.textTheme.labelSmall?.copyWith(color: ink.withValues(alpha: 0.55))),
        // Up arrow while closed; flips down when the calendar is open.
        IconButton(
          tooltip: _expanded ? 'Hide calendar' : 'Show month',
          onPressed: () => setState(() => _expanded = !_expanded),
          iconSize: 34,
          icon: AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 250),
            child: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded ? const _MonthCalendar() : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// Month grid for the budget cycle. Lines under a date mark spending
/// (green = within that day's limit, coral = over). Hover or tap a date for
/// a popup with that day's spend and limit.
class _MonthCalendar extends ConsumerWidget {
  const _MonthCalendar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(cycleDaysProvider);
    final today = ref.watch(todayProvider);
    final money = ref.watch(moneyProvider);
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    if (days.isEmpty) return const SizedBox.shrink();

    final byDay = {for (final d in days) d.day: d};

    // Grid runs Monday → Sunday, padded to whole weeks around the cycle.
    final first = days.first.day;
    final last = days.last.day;
    final gridStart = DateTime(first.year, first.month, first.day - (first.weekday - 1));
    final gridEnd = DateTime(last.year, last.month, last.day + (7 - last.weekday));
    final cells = [
      for (var d = gridStart; !d.isAfter(gridEnd); d = DateTime(d.year, d.month, d.day + 1)) d,
    ];
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          '${DateFormat('d MMM').format(first)} – ${DateFormat('d MMM yyyy').format(last)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final (i, w) in weekdays.indexed)
            Expanded(
              child: Text(w,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: i == 6 ? Palette.coral : ink.withValues(alpha: 0.55),
                  )),
            ),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.9,
          children: [
            for (final d in cells)
              _DayCell(info: byDay[d], date: d, isToday: d == today, money: money),
          ],
        ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.info,
    required this.date,
    required this.isToday,
    required this.money,
  });

  final DayLimit? info; // null = outside the budget cycle
  final DateTime date;
  final bool isToday;
  final Money money;

  /// Popup text: spend / limit for past days and today, limit for the future.
  InlineSpan _popup(ThemeData theme) {
    final i = info!;
    final fg = theme.colorScheme.onInverseSurface;
    final base = TextStyle(color: fg, fontSize: 13, height: 1.5);
    final bold = base.copyWith(fontWeight: FontWeight.w800);
    final title = isToday ? 'Today' : DateFormat('EEE, d MMM').format(i.day);
    if (i.isFuture) {
      return TextSpan(style: base, children: [
        TextSpan(text: '$title\n', style: bold),
        const TextSpan(text: 'Limit  '),
        TextSpan(text: money(i.limit), style: bold),
      ]);
    }
    final diff = i.limit - i.spent;
    final diffColor = i.isOver ? Palette.coral : Palette.green;
    return TextSpan(style: base, children: [
      TextSpan(text: '$title\n', style: bold),
      const TextSpan(text: 'Spent  '),
      TextSpan(text: '${money(i.spent)}\n', style: bold.copyWith(color: i.isOver ? Palette.coral : fg)),
      const TextSpan(text: 'Limit  '),
      TextSpan(text: '${money(i.limit)}\n', style: bold),
      TextSpan(text: i.isOver ? 'Over by  ' : (isToday ? 'Left  ' : 'Saved  ')),
      TextSpan(text: money(diff.abs()), style: bold.copyWith(color: diffColor)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final inCycle = info != null;
    final sunday = date.weekday == DateTime.sunday;
    final numberColor = isToday
        ? Colors.white
        : !inCycle
            ? ink.withValues(alpha: 0.25)
            : sunday
                ? Palette.coral
                : info!.isFuture
                    ? ink.withValues(alpha: 0.75)
                    : ink;
    final spent = info != null && !info!.isFuture && info!.spent > 0;

    Widget number = Container(
      width: 30,
      height: 26,
      alignment: Alignment.center,
      decoration: isToday
          ? BoxDecoration(color: Palette.coral, borderRadius: BorderRadius.circular(8))
          : null,
      child: Text('${date.day}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: numberColor,
          )),
    );
    Widget cell = Container(
        margin: const EdgeInsets.all(2),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          number,
          const SizedBox(height: 4),
          Container(
            width: 26,
            height: 4,
            decoration: BoxDecoration(
              color: !spent
                  ? Colors.transparent
                  : info!.isOver
                      ? Palette.coral
                      : Palette.green,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ]),
    );
    // The whole date cell (not just the number) is the touch area, so a
    // date is easy to hit. Scrolling still works: a drag isn't a tap.
    if (info != null) {
      cell = Tooltip(
        richMessage: _popup(theme),
        preferBelow: false,
        verticalOffset: 18,
        triggerMode: TooltipTriggerMode.tap,
        waitDuration: Duration.zero,
        showDuration: const Duration(seconds: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          // Opaque so the empty space around the number also counts.
          child: Listener(behavior: HitTestBehavior.opaque, child: SizedBox.expand(child: cell)),
        ),
      );
    }
    return cell;
  }
}

/// The four summary tiles in one row. The Fixed expenses tile has an arrow
/// that opens its item list underneath.
class _TilesRow extends ConsumerStatefulWidget {
  const _TilesRow({required this.budget});
  final DailyBudget budget;

  @override
  ConsumerState<_TilesRow> createState() => _TilesRowState();
}

class _TilesRowState extends ConsumerState<_TilesRow> {
  bool _showFixed = false;

  /// Where a press outside started; closing only happens if the finger
  /// barely moved (a tap), so scrolling the page leaves the panel open.
  Offset? _outsideDown;

  void _onOutsideDown(PointerDownEvent e) => _outsideDown = e.position;

  void _onOutsideUp(PointerUpEvent e) {
    final down = _outsideDown;
    _outsideDown = null;
    if (!_showFixed || down == null) return;
    if ((e.position - down).distance < kTouchSlop) setState(() => _showFixed = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.budget;
    final money = ref.watch(moneyProvider);
    final theme = Theme.of(context);
    final fixed = ref.watch(fixedExpensesProvider).value ?? const [];
    final fixedTotal = fixed.fold(0.0, (s, f) => s + f.amount);

    return TapRegion(
      onTapOutside: _showFixed ? _onOutsideDown : null,
      onTapUpOutside: _showFixed ? _onOutsideUp : null,
      child: Column(children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Tile(Palette.blue, 'Today\'s limit', money(b.dailyLimit)),
          const SizedBox(width: 8),
          _Tile(Palette.yellow, 'Spent today', money(b.spentToday), warn: b.isOverLimit),
          const SizedBox(width: 8),
          _Tile(Palette.green, 'Month left', money(b.monthRemaining),
              sub: '${b.daysRemaining} days', warn: b.monthRemaining < 0),
          const SizedBox(width: 8),
          _Tile(
            Palette.coral,
            'Fixed expenses',
            money(fixedTotal),
            sub: fixed.isEmpty ? 'None' : '${fixed.length} item${fixed.length == 1 ? '' : 's'}',
            expanded: _showFixed,
            onTap: () => setState(() => _showFixed = !_showFixed),
          ),
        ]),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: !_showFixed
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                decoration: BoxDecoration(
                  color: Palette.soft(Palette.coral, theme.brightness),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (fixed.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('No fixed expenses yet.', style: theme.textTheme.bodyMedium),
                    ),
                  for (final f in fixed)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 6),
                      child: Row(children: [
                        Expanded(child: Text(f.name, style: theme.textTheme.bodyLarge)),
                        Text(money(f.amount),
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  if (fixed.isNotEmpty) ...[
                    const Divider(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(children: [
                        Expanded(
                            child: Text('Total',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                        Text(money(fixedTotal),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SetupScreen(editing: true))),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                ]),
              ),
      ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.accent, this.label, this.value,
      {this.sub, this.warn = false, this.onTap, this.expanded = false});
  final Color accent;
  final String label, value;
  final String? sub;
  final bool warn;

  /// When set, the tile shows a down arrow and is tappable.
  final VoidCallback? onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Material(
        color: Palette.soft(accent, Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: t.labelMedium, maxLines: 2),
              const Spacer(),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, color: warn ? Palette.coral : null)),
              ),
              Row(children: [
                Expanded(
                  child: Text(sub ?? ' ',
                      style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (onTap != null)
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
