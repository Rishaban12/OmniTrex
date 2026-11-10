/// On-device parser for bank SMS and UPI app notifications.
/// Pure Dart: no network, no platform dependencies.
library;

enum MessageSource { sms, notification, manual }

enum TxnDirection { debit, refund }

enum IgnoreReason { otp, promotional, failed, credit, request, notFinancial }

class RawMessage {
  const RawMessage({
    required this.body,
    required this.source,
    required this.receivedAt,
    this.sender,
  });

  final String body;
  final MessageSource source;
  final DateTime receivedAt;

  /// SMS sender ID (e.g. "VM-HDFCBK") or notification package name.
  final String? sender;
}

sealed class ParseResult {
  const ParseResult(this.raw);
  final RawMessage raw;
}

class ParsedTxn extends ParseResult {
  const ParsedTxn({
    required RawMessage raw,
    required this.amount,
    required this.direction,
    required this.occurredAt,
    this.merchant,
    this.upiRef,
    this.accountHint,
  }) : super(raw);

  final double amount;
  final TxnDirection direction;
  final DateTime occurredAt;
  final String? merchant;
  final String? upiRef;
  final String? accountHint;

  @override
  String toString() =>
      'ParsedTxn($direction $amount, merchant: $merchant, ref: $upiRef, at: $occurredAt)';
}

class IgnoredMessage extends ParseResult {
  const IgnoredMessage(super.raw, this.reason);
  final IgnoreReason reason;

  @override
  String toString() => 'Ignored($reason)';
}

/// Looks financial but couldn't be classified with confidence: goes to Review.
class UnparsedMessage extends ParseResult {
  const UnparsedMessage(super.raw, {this.amountGuess, this.merchantGuess});
  final double? amountGuess;
  final String? merchantGuess;

  @override
  String toString() => 'Unparsed(amount: $amountGuess)';
}

RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

class SmsParser {
  const SmsParser({this.bankAlertsOnly = true});

  /// SMS must name a bank and say credited / sent / debited / refunded.
  final bool bankAlertsOnly;

  static const upiAppPackages = {
    'com.google.android.apps.nbu.paisa.user', // Google Pay
    'com.phonepe.app',
    'net.one97.paytm',
  };

  // --- Classification -----------------------------------------------------

  static final _otpWord =
      _re(r'\b(otp|one[\s-]?time\s*pass(word|code)?|verification\s*code|security\s*code)\b');
  static final _otpCode = [
    _re(r'(otp|password|passcode|code)\D{0,20}\b\d{4,8}\b'),
    _re(r'\b\d{4,8}\b\D{0,25}(otp|one[\s-]?time|verification)'),
  ];

  static final _refund =
      _re(r'\b(refund(ed)?|revers(ed|al)|chargeback|credited back)\b');

  static final _failed = _re(
      r'\b(failed|failure|declined|unsuccessful|not successful|could not be (processed|completed)|rejected|insufficient (funds|balance)|timed out)\b');

  static final _request = _re(
      r'(requested (money|₹|rs|inr)|has requested|is requesting|collect request|payment request|request(ed)? from|reminder|due (on|date|by)|bill (is )?due|pay now|will be (debited|deducted|charged)|to be debited|autopay (is )?(scheduled|set)|mandate (created|registered)|e-?mandate)');

  static final _creditToYou =
      _re(r'(paid to you|sent you|has sent|received (₹|rs|inr|money|payment)|you received|you have received)');
  static final _strongDebit = _re(
      r'\b(debited|spent|withdrawn|withdrawal|deducted|paid|sent|purchase[ds]?)\b');
  static final _credit =
      _re(r'\b(credited|received|deposited|added to (your )?(a/?c|account|wallet))\b');
  static final _weakDebit = _re(
      r'\b(txn of|transaction of|payment of|charged|transferred|trf|dr|debit)\b');

  static final _promo = _re(
      r'(\boffer\b|cashback (up ?to|of up)|grab .{0,20}cashback|\bwin\b|\bwon\b|congratulations|pre-?approved|apply now|\bloan\b|limited (time|period)|discount|voucher|coupon|\d+\s?% off|flat \d+|(use|with|apply) (the )?code|promo ?code|top[- ]?up (your|now)|recharge now|data (limit|pack) alert|\bt&c|\btnc\b|click|https?://|www\.|download|upgrade now|reward points|exclusive|hurry)');

  static final _accountRef = _re(
      r'(a/c|acct|account|card)\s*(no\.?)?\s*(ending\s*(with|in)?\s*)?[x*.\s]*(\d{3,6})');

  static final _financialHint =
      _re(r'(a/c|acct|account|card|upi|bank|txn|transaction|wallet|vpa|imps|neft|rtgs|₹|\brs\b|\binr\b)');

  static final _bankWord = _re(r'\bbank\b');
  static final _bankAction = _re(r'\b(credited|debited|sent|received|refunded)\b');

  // --- Field extraction ---------------------------------------------------

  static const _num = r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)';
  static final _amountPatterns = [
    _re(r'(?:rs\.?|inr|₹)\s*:?\s*' + _num),
    _re(_num + r'\s*(?:rs\.?|inr|₹|/-)'),
    _re(r'(?:debited|credited|refunded|reversed)\s+(?:by|for|with|of)\s+' + _num),
  ];
  static final _balanceContext =
      _re(r'(bal|balance|avl|available|limit|o/s|outstanding|min(imum)? due|total due)[^0-9]{0,15}$');

  static final _upiRefPatterns = [
    _re(r'(?:upi\s*(?:ref(?:erence)?|txn|transaction)?\s*(?:no|id|#|number)?|ref(?:erence)?\s*(?:no|#|id|number)?|refno|rrn|utr|txn\s*(?:id|no))\s*[.:#-]*\s*([0-9]{10,16})'),
    _re(r'upi/(?:p2[ma]/)?([0-9]{10,16})'),
  ];

  static const _stopWords =
      r'on|via|using|ref|refno|upi|txn|for|from|with|avl|bal|thru|through|is|has|was|by|dated|date|at|vpa|and|your|successful|successfully';
  static final _merchantPatterns = [
    _re(r'upi/(?:p2[ma]/)?\d+/([a-z0-9 &.\x27-]{2,40})'),
    _re(r'\b(?:paid to|sent to|payment to|trf to|transfer(?:red)? to|to|at|towards|info:?)\s+(?:vpa\s+|merchant\s+)?([a-z0-9][a-z0-9 &@._\x27*-]{1,40}?)(?=\s*(?:₹|rs\.?\s?\d|inr)|\s+(?:' +
        _stopWords +
        r')\b|[.,;:!|\n(]|$)'),
  ];
  static final _vpa = _re(r'\b([a-z0-9._-]{2,})@([a-z]{2,})\b');
  static final _merchantReject = _re(
      r'^(your|you|a/?c|ac|acct|account|card|bank|self|me|the|beneficiary|mobile|number|xx|x+\d*|\d+)\b');

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static final _dateNumeric =
      _re(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\b');
  static final _dateIso = _re(r'\b(\d{4})-(\d{2})-(\d{2})\b');
  static final _dateMonthName = _re(
      r'\b(\d{1,2})[-\s]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-\s,]*(\d{4}|\d{2})\b');
  static final _time =
      _re(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\s*(am|pm)?\b');

  // --- Entry point --------------------------------------------------------

  ParseResult parse(RawMessage message) {
    final text = message.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return IgnoredMessage(message, IgnoreReason.notFinancial);

    if (_otpWord.hasMatch(text) && _otpCode.any((r) => r.hasMatch(text))) {
      return IgnoredMessage(message, IgnoreReason.otp);
    }

    // SMS: only bank transaction alerts ("… Indian Bank") that say
    // credited / sent / debited are read. Everything else is skipped.
    if (bankAlertsOnly &&
        message.source == MessageSource.sms &&
        !(_bankWord.hasMatch(text) && _bankAction.hasMatch(text))) {
      return IgnoredMessage(message, IgnoreReason.notFinancial);
    }

    final amount = extractAmount(text);
    final hasAccount = _accountRef.hasMatch(text);
    final upiRef = extractUpiRef(text);
    final isUpiApp = message.source == MessageSource.notification;

    if (_refund.hasMatch(text) && amount != null) {
      return _parsed(message, text, amount, TxnDirection.refund, upiRef);
    }
    if (_failed.hasMatch(text)) return IgnoredMessage(message, IgnoreReason.failed);
    if (_request.hasMatch(text)) return IgnoredMessage(message, IgnoreReason.request);
    if (_promo.hasMatch(text) && !hasAccount && upiRef == null) {
      return IgnoredMessage(message, IgnoreReason.promotional);
    }

    final direction = _direction(text);
    if (direction == _Dir.credit) return IgnoredMessage(message, IgnoreReason.credit);

    final looksFinancial = hasAccount || upiRef != null || isUpiApp ||
        _financialHint.hasMatch(text);
    if (amount == null) {
      return looksFinancial && direction == _Dir.debit
          ? UnparsedMessage(message, merchantGuess: extractMerchant(text))
          : IgnoredMessage(message, IgnoreReason.notFinancial);
    }
    if (direction == _Dir.debit) {
      return _parsed(message, text, amount, TxnDirection.debit, upiRef);
    }
    return looksFinancial
        ? UnparsedMessage(message,
            amountGuess: amount, merchantGuess: extractMerchant(text))
        : IgnoredMessage(message, IgnoreReason.notFinancial);
  }

  ParsedTxn _parsed(RawMessage m, String text, double amount, TxnDirection dir,
          String? upiRef) =>
      ParsedTxn(
        raw: m,
        amount: amount,
        direction: dir,
        merchant: extractMerchant(text),
        upiRef: upiRef,
        accountHint: _accountRef.firstMatch(text)?.group(5),
        occurredAt: extractTime(text, m.receivedAt),
      );

  _Dir _direction(String text) {
    if (_creditToYou.hasMatch(text)) return _Dir.credit;
    if (_strongDebit.hasMatch(text)) return _Dir.debit;
    if (_credit.hasMatch(text)) return _Dir.credit;
    if (_weakDebit.hasMatch(text)) return _Dir.debit;
    return _Dir.unknown;
  }

  /// First currency amount that isn't a balance / limit figure.
  double? extractAmount(String text) {
    final candidates = <({int index, double value})>[];
    for (final pattern in _amountPatterns) {
      for (final m in pattern.allMatches(text)) {
        final before = text.substring(0, m.start);
        if (_balanceContext.hasMatch(before)) continue;
        final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (value != null && value > 0) {
          candidates.add((index: m.start, value: value));
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.index.compareTo(b.index));
    return candidates.first.value;
  }

  String? extractUpiRef(String text) {
    for (final p in _upiRefPatterns) {
      final m = p.firstMatch(text);
      if (m != null) return m.group(1);
    }
    return null;
  }

  String? extractMerchant(String text) {
    for (final p in _merchantPatterns) {
      for (final m in p.allMatches(text)) {
        final cleaned = _cleanMerchant(m.group(1)!);
        if (cleaned != null) return cleaned;
      }
    }
    final vpa = _vpa.firstMatch(text);
    return vpa == null ? null : _cleanMerchant(vpa.group(0)!);
  }

  String? _cleanMerchant(String raw) {
    var s = raw.trim();
    final vpa = _vpa.firstMatch(s);
    if (vpa != null) {
      // "swiggy.payu@hdfc" -> "swiggy"; "9876543210@ybl" -> rejected below.
      s = vpa.group(1)!.split(RegExp(r'[._-]')).first;
    }
    s = s
        .replaceAll(RegExp(r'[*_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\s.&-]+$'), '')
        .trim();
    if (s.length < 2 || _merchantReject.hasMatch(s)) return null;
    if (RegExp(r'^[\d\s]+$').hasMatch(s)) return null;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Uses the date/time printed in the message when it's plausible (within
  /// 3 days of receipt), otherwise the receive time.
  DateTime extractTime(String text, DateTime receivedAt) {
    DateTime? date;
    final iso = _dateIso.firstMatch(text);
    final named = _dateMonthName.firstMatch(text);
    final numeric = _dateNumeric.firstMatch(text);
    if (iso != null) {
      date = _safeDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
          int.parse(iso.group(3)!));
    } else if (named != null) {
      date = _safeDate(_year(named.group(3)!),
          _months[named.group(2)!.toLowerCase().substring(0, 3)]!,
          int.parse(named.group(1)!));
    } else if (numeric != null) {
      date = _safeDate(_year(numeric.group(3)!), int.parse(numeric.group(2)!),
          int.parse(numeric.group(1)!));
    }

    final t = _time.firstMatch(text);
    int? hour, minute;
    if (t != null) {
      hour = int.parse(t.group(1)!);
      minute = int.parse(t.group(2)!);
      final ampm = t.group(3)?.toLowerCase();
      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
    }

    if (date == null || date.difference(receivedAt).inDays.abs() > 3) {
      return receivedAt;
    }
    final sameDay = date.year == receivedAt.year &&
        date.month == receivedAt.month &&
        date.day == receivedAt.day;
    if (hour == null) {
      return sameDay
          ? receivedAt
          : DateTime(date.year, date.month, date.day, receivedAt.hour,
              receivedAt.minute);
    }
    return DateTime(date.year, date.month, date.day, hour, minute!);
  }

  static int _year(String y) => y.length == 2 ? 2000 + int.parse(y) : int.parse(y);

  static DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    return dt.month == m ? dt : null;
  }
}

enum _Dir { debit, credit, unknown }

/// Duplicate detection across SMS + notification for the same payment.
class Deduplicator {
  const Deduplicator._();

  static const window = Duration(minutes: 2);

  static bool isDuplicate({
    required double amount,
    required DateTime at,
    String? upiRef,
    required Iterable<({double amount, DateTime at, String? upiRef})> existing,
  }) {
    for (final e in existing) {
      if (upiRef != null && e.upiRef != null) {
        if (e.upiRef == upiRef) return true;
        continue; // Both have refs and they differ: distinct payments.
      }
      if ((e.amount - amount).abs() < 0.005 &&
          e.at.difference(at).abs() <= window) {
        return true;
      }
    }
    return false;
  }
}
