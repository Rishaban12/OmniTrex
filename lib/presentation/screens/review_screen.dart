import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/services/amount_input.dart';
import '../../data/db/app_database.dart';
import '../../domain/services/sms_parser.dart';
import '../common.dart';
import '../providers.dart';
import '../theme.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key, this.onBack});

  /// Back arrow action (PocketPlan: return to the Today tab).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingMessagesProvider);
    return Scaffold(
      // Blobs run behind a see-through app bar.
      extendBodyBehindAppBar: true,
      appBar: AppBar(leading: onBack == null ? null : BackButton(onPressed: onBack), title: const Text('Parser'), backgroundColor: Colors.transparent),
      body: BlobBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _ParserTester(),
              // Only shown once something lands here.
              ...pending.when(
                loading: () => const <Widget>[],
                error: (e, _) => [Text('$e')],
                data: (list) => list.isEmpty
                    ? const <Widget>[]
                    : [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text('Messages we couldn\'t classify. Tap a category to log, or dismiss.'),
                        ),
                        for (final p in list) _PendingCard(p),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard(this.row);
  final PendingMessageRow row;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  late final _amount = TextEditingController(text: widget.row.amountGuess?.toStringAsFixed(0) ?? '');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final symbol = ref.watch(settingsProvider).currency.symbol;
    final repo = ref.read(pendingRepoProvider);
    final row = widget.row;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${sourceLabel(row.source)} · ${row.sender ?? ''} · ${DateFormat('d MMM, h:mm a').format(row.receivedAt)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
              // Delete this message.
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  tooltip: 'Delete message',
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  onPressed: () => repo.remove(row.id),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(row.body),
            const SizedBox(height: 8),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(prefixText: '$symbol ', isDense: true, labelText: 'Amount'),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in categories)
                  ActionChip(
                    avatar: Icon(iconFor(c.icon), color: Color(c.color), size: 16),
                    label: Text(c.name),
                    onPressed: () async {
                      final amount = AmountInput.parse(_amount.text);
                      if (amount == null) {
                        showSnack(context, 'Enter the amount');
                        return;
                      }
                      await repo.resolveAsExpense(row, amount: amount, categoryId: c.id);
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.close, size: 16),
                  label: const Text('Not an expense'),
                  onPressed: () => repo.remove(row.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paste any bank SMS / UPI notification to run it through the real pipeline.
/// Handy on web, where SMS can't be read.
class _ParserTester extends ConsumerStatefulWidget {
  const _ParserTester();

  @override
  ConsumerState<_ParserTester> createState() => _ParserTesterState();
}

class _ParserTesterState extends ConsumerState<_ParserTester> {
  final _text = TextEditingController();
  MessageSource _source = MessageSource.sms;
  String? _result;

  static const _samples = [
    'Sent Rs.855.35 from A/c *7062 to mpokket.RRN 617345529735.Avl Bal Rs.1671.31.Not you?SMS BLOCK to 9289592895-Indian Bank',
    'You paid ₹120 to Rapido',
    'Your A/c *7062 is credited with Rs.3500.00 by Ms Sudha. RRN 667451080806. Available balance is Rs. 4323.48 - Indian Bank',
    'Rs 499 refunded to your A/c XX1234 for order at Amazon. UPI Ref 629512340000 - HDFC Bank',
    'Congratulations! You are pre-approved for a loan of Rs 5,00,000. Apply now',
    'Txn alert: INR 760 on card ending 4321',
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_text.text.trim().isEmpty) return;
    final (result, duplicate) = await ref
        .read(autoTrackingServiceProvider)
        .process(
          RawMessage(
            body: _text.text.trim(),
            source: _source,
            receivedAt: DateTime.now(),
            sender: _source == MessageSource.sms ? 'TEST-BANK' : 'test.upi.app',
          ),
        );
    if (!mounted) return;
    setState(
      () => _result = switch (result) {
        ParsedTxn t =>
          '${duplicate ? '↺ Already logged, skipped duplicate' : '✓ Logged ${t.direction.name}'}: '
              '${t.amount} · ${t.merchant ?? 'no merchant'}${t.upiRef != null ? ' · ref ${t.upiRef}' : ''}',
        UnparsedMessage u => '→ Sent to Parser list (amount guess: ${u.amountGuess ?? '–'})',
        IgnoredMessage i => '✗ Ignored: ${i.reason.name}',
      },
    );
  }

  /// Any change to the input invalidates the previous result.
  void _clearResult() {
    if (_result != null) setState(() => _result = null);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      // Keep the grey touch highlight inside the rounded box.
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // No top/bottom divider lines when opened or closed.
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        leading: const Icon(Icons.science_outlined),
        title: const Text('Test the message parser'),
        subtitle: const Text('Runs fully on-device'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _text,
            onChanged: (_) => _clearResult(),
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Paste a bank SMS or UPI notification',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, s) in _samples.indexed)
                ActionChip(
                  label: Text('Sample ${i + 1}'),
                  onPressed: () => setState(() {
                    _text.text = s;
                    _source = s.startsWith('You paid') ? MessageSource.notification : MessageSource.sms;
                    _result = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SegmentedButton<MessageSource>(
                segments: const [
                  ButtonSegment(value: MessageSource.sms, label: Text('SMS')),
                  ButtonSegment(value: MessageSource.notification, label: Text('UPI app')),
                ],
                selected: {_source},
                onSelectionChanged: (s) => setState(() {
                  _source = s.first;
                  _result = null;
                }),
              ),
              const Spacer(),
              FilledButton(onPressed: _run, child: const Text('Parse')),
            ],
          ),
          if (_result != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_result!)),
        ],
      ),
    );
  }
}
