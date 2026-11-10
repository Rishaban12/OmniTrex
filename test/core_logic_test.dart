import 'package:daily_budget/domain/services/daily_limit_calculator.dart';
import 'package:daily_budget/domain/services/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = SmsParser(bankAlertsOnly: false);
  final now = DateTime(2026, 10, 22, 14, 30);
  ParseResult p(String body, [MessageSource s = MessageSource.sms]) =>
      parser.parse(RawMessage(body: body, source: s, receivedAt: now));

  group('SmsParser', () {
    test('UPI debit with VPA and ref', () {
      final r = p('Rs.250.00 debited from A/c XX1234 on 22-10-26 to VPA swiggy@icici '
          '(UPI Ref No 629512345678). Avl Bal Rs 10,000') as ParsedTxn;
      expect(r.amount, 250);
      expect(r.direction, TxnDirection.debit);
      expect(r.merchant, 'Swiggy');
      expect(r.upiRef, '629512345678');
      expect(r.accountHint, '1234');
    });

    test('SBI style without currency symbol', () {
      final r = p('Dear UPI user A/C X5678 debited by 120.0 on date 21Oct26 trf to ZOMATO LTD Refno 629500001111') as ParsedTxn;
      expect(r.amount, 120);
      expect(r.merchant, 'Zomato Ltd');
      expect(r.occurredAt.day, 21);
    });

    test('card spend at merchant', () {
      final r = p('INR 1,499.00 spent on HDFC Bank Card xx4321 at AMAZON on 2026-10-22:13:05:11. Avl Lmt: INR 50,000') as ParsedTxn;
      expect(r.amount, 1499);
      expect(r.merchant, 'Amazon');
    });

    test('GPay / PhonePe notifications', () {
      expect((p('You paid ₹120 to Rapido', MessageSource.notification) as ParsedTxn).merchant, 'Rapido');
      final pp = p('Paid to Ramesh Kumar ₹ 80', MessageSource.notification) as ParsedTxn;
      expect(pp.amount, 80);
      expect(pp.merchant, 'Ramesh Kumar');
    });

    test('ignores OTP, promo, credit, failed, requests', () {
      expect((p('482913 is your OTP for txn of Rs 500 at Amazon. Do not share.') as IgnoredMessage).reason, IgnoreReason.otp);
      expect((p('Congratulations! You are pre-approved for a loan of Rs 5,00,000. Apply now') as IgnoredMessage).reason, IgnoreReason.promotional);
      expect((p('Rs 5000 credited to A/c XX1234 by NEFT from ACME CORP') as IgnoredMessage).reason, IgnoreReason.credit);
      expect((p('Your UPI payment of Rs 300 to xyz@ybl failed. A/c XX1234') as IgnoredMessage).reason, IgnoreReason.failed);
      expect((p('Ravi has requested ₹200 from you on Google Pay', MessageSource.notification) as IgnoredMessage).reason, IgnoreReason.request);
      expect((p('₹500 received from Anita', MessageSource.notification) as IgnoredMessage).reason, IgnoreReason.credit);
    });

    test('refund', () {
      final r = p('Rs 499 refunded to your A/c XX1234 for order at Amazon. UPI Ref 629512340000') as ParsedTxn;
      expect(r.direction, TxnDirection.refund);
      expect(r.amount, 499);
    });

    test('ambiguous financial message goes to review', () {
      expect(p('Txn alert: INR 760 on card ending 4321'), isA<UnparsedMessage>());
    });

    test('dedupe by ref and by amount+time window', () {
      final existing = [(amount: 250.0, at: now, upiRef: '629512345678')];
      expect(Deduplicator.isDuplicate(amount: 250, at: now, upiRef: '629512345678', existing: existing), isTrue);
      expect(Deduplicator.isDuplicate(amount: 250, at: now.add(const Duration(seconds: 90)), existing: existing), isTrue);
      expect(Deduplicator.isDuplicate(amount: 250, at: now.add(const Duration(minutes: 3)), existing: existing), isFalse);
      expect(Deduplicator.isDuplicate(amount: 250, at: now, upiRef: '999999999999', existing: existing), isFalse);
    });
  });

  group('DailyLimitCalculator', () {
    test('cycle with custom start day and clamping', () {
      final c = BudgetCycle.containing(DateTime(2026, 10, 3), 5);
      expect(c.start, DateTime(2026, 9, 5));
      expect(c.end, DateTime(2026, 10, 5));
      final feb = BudgetCycle.containing(DateTime(2026, 2, 28), 31);
      expect(feb.start, DateTime(2026, 2, 28));
      expect(BudgetCycle.containing(DateTime(2026, 1, 10), 15).start, DateTime(2025, 12, 15));
    });

    test('rollover on: (budget − fixed − spent) ÷ remaining days', () {
      final b = DailyLimitCalculator.calculate(
        monthlyBudget: 40000, fixedExpenses: 15000,
        cycle: BudgetCycle(DateTime(2026, 10, 1), DateTime(2026, 11, 1)),
        today: DateTime(2026, 10, 22), spentBeforeToday: 15000, spentToday: 300, rollover: true,
      );
      expect(b.daysRemaining, 10);
      expect(b.dailyLimit, 1000);
      expect(b.remainingToday, 700);
      expect(b.monthRemaining, 9700);
      expect(b.isOverLimit, isFalse);
    });

    test('rollover off caps at even split but still absorbs overspend', () {
      final cycle = BudgetCycle(DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      final under = DailyLimitCalculator.calculate(
        monthlyBudget: 31000, fixedExpenses: 0, cycle: cycle, today: DateTime(2026, 10, 22),
        spentBeforeToday: 0, spentToday: 0, rollover: false);
      expect(under.dailyLimit, 1000);
      final over = DailyLimitCalculator.calculate(
        monthlyBudget: 31000, fixedExpenses: 0, cycle: cycle, today: DateTime(2026, 10, 22),
        spentBeforeToday: 26000, spentToday: 600, rollover: false);
      expect(over.dailyLimit, 500);
      expect(over.isOverLimit, isTrue);
    });

    test('cycleDays: historic limits for past days, even split for future', () {
      final days = DailyLimitCalculator.cycleDays(
        monthlyBudget: 1000, fixedExpenses: 0, rollover: true,
        cycle: BudgetCycle(DateTime(2026, 11, 1), DateTime(2026, 11, 11)), // 10 days
        today: DateTime(2026, 11, 3, 15),
        entries: [SpendEntry(DateTime(2026, 11, 1, 9), 300), SpendEntry(DateTime(2026, 11, 3, 10), 100)],
      );
      expect(days.length, 10);
      expect(days[0].limit, 100); // 1000 / 10
      expect(days[0].isOver, isTrue); // spent 300
      expect(days[1].limit, closeTo(700 / 9, 0.01));
      expect(days[2].limit, 700 / 8);
      expect(days[2].spent, 100);
      // Future: (1000 − 400) / 7 remaining days, same for each.
      expect(days[3].isFuture, isTrue);
      expect(days[3].limit, closeTo(600 / 7, 0.01));
      expect(days[9].limit, days[3].limit);
    });

    test('custom start/end period: monthly spans repeat monthly, others by length', () {
      // 18 Oct – 17 Nov is a whole month → next is 18 Nov – 17 Dec.
      final m = BudgetCycle.repeating(DateTime(2026, 10, 18), DateTime(2026, 11, 17), DateTime(2026, 11, 20));
      expect(m.start, DateTime(2026, 11, 18));
      expect(m.end, DateTime(2026, 12, 18));
      // 1–14 Nov (14 days) → 15–28 Nov, and back to 18–31 Oct before it.
      final f = BudgetCycle.repeating(DateTime(2026, 11, 1), DateTime(2026, 11, 14), DateTime(2026, 11, 20));
      expect(f.start, DateTime(2026, 11, 15));
      expect(f.totalDays, 14);
      final before = BudgetCycle.repeating(DateTime(2026, 11, 1), DateTime(2026, 11, 14), DateTime(2026, 10, 20));
      expect(before.start, DateTime(2026, 10, 18));
      // Inside the chosen period it's exactly that period.
      final inside = BudgetCycle.repeating(DateTime(2026, 11, 1), DateTime(2026, 11, 14), DateTime(2026, 11, 8));
      expect((inside.start, inside.end), (DateTime(2026, 11, 1), DateTime(2026, 11, 15)));
    });

    test('refunds reduce spend', () {
      final b = DailyLimitCalculator.fromEntries(
        monthlyBudget: 3100, fixedExpenses: 0, cycle: BudgetCycle.containing(now, 1), now: now, rollover: true,
        entries: [SpendEntry(now, 500), SpendEntry(now, -200)],
      );
      expect(b.spentToday, 300);
    });
  });
}
