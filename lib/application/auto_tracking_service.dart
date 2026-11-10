import '../data/repositories/budget_repositories.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/services/sms_parser.dart';
import '../platform/auto_tracking_bridge.dart';

/// Pipeline: raw message → parser → dedupe/insert, or Review queue.
class AutoTrackingService {
  AutoTrackingService({
    required this.bridge,
    required this.transactions,
    required this.pending,
    this.parser = const SmsParser(),
  });

  final AutoTrackingBridge bridge;
  final TransactionRepository transactions;
  final PendingMessageRepository pending;
  final SmsParser parser;
  bool _draining = false;

  Future<void> drainFromDevice() async {
    if (_draining) return;
    _draining = true;
    try {
      for (final m in await bridge.drainPending()) {
        await process(m);
      }
    } finally {
      _draining = false;
    }
  }

  /// Returns the parse result and whether it was skipped as a duplicate.
  Future<(ParseResult, bool duplicate)> process(RawMessage message) async {
    final result = parser.parse(message);
    var duplicate = false;
    switch (result) {
      case ParsedTxn():
        duplicate = await transactions.ingest(result) == null;
      case UnparsedMessage():
        await pending.add(result);
      case IgnoredMessage():
        break;
    }
    return (result, duplicate);
  }
}
