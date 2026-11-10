import 'package:daily_budget/domain/services/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = SmsParser(bankAlertsOnly: false);
  final received = DateTime(2026, 10, 22, 14, 30);
  ParseResult parse(String body, [MessageSource s = MessageSource.sms]) =>
      parser.parse(RawMessage(body: body, source: s, receivedAt: received));
  ParsedTxn parsed(String body, [MessageSource s = MessageSource.sms]) {
    final r = parse(body, s);
    expect(r, isA<ParsedTxn>(), reason: 'expected a transaction from: $body → $r');
    return r as ParsedTxn;
  }

  IgnoreReason ignored(String body, [MessageSource s = MessageSource.sms]) {
    final r = parse(body, s);
    expect(r, isA<IgnoredMessage>(), reason: 'expected ignore for: $body → $r');
    return (r as IgnoredMessage).reason;
  }

  group('positive — logged as transactions', () {
    test('Indian lakh-style amount with paise', () {
      expect(parsed('INR 1,23,456.78 debited from A/c XX1234 to VPA rent@okaxis').amount, 123456.78);
    });

    test('Rs without dot and ₹ symbol variants', () {
      expect(parsed('Rs 75 debited from a/c xx9999 to swiggy@icici').amount, 75);
      expect(parsed('₹1,050 spent on card ending 4321 at DMART').amount, 1050);
    });

    test('amount written after the number ("500/-")', () {
      expect(parsed('500/- debited from A/c XX1234 towards electricity bill').amount, 500);
    });

    test('balance figure is never taken as the amount', () {
      final t = parsed('Avl Bal Rs 9,000. Rs 120 debited from A/c XX1234 at Cafe Coffee Day');
      expect(t.amount, 120);
    });

    test('merchant from VPA prefix; phone-number VPAs give no merchant', () {
      expect(parsed('Rs 99 sent to zomato.payu@hdfcbank UPI Ref 629512340001').merchant, 'Zomato');
      expect(parsed('Rs 50 sent to 9876543210@ybl UPI Ref 629511112222').merchant, isNull);
    });

    test('"never share OTP" footer does not hide a real debit', () {
      final t = parsed('Never share your OTP with anyone. Rs 200 debited from A/c XX1234 at Zomato');
      expect(t.amount, 200);
      expect(t.merchant, 'Zomato');
    });

    test('date/time in the body within 3 days is used', () {
      final t = parsed('Rs 300 debited from A/c XX1234 on 21-10-26 14:05 to VPA uber@axis');
      expect(t.occurredAt, DateTime(2026, 10, 21, 14, 5));
    });

    test('12-hour times with pm', () {
      final t = parsed('Rs 80 debited from A/c XX1234 on 22-10-26 at 2:15 pm to rapido@ybl');
      expect(t.occurredAt, DateTime(2026, 10, 22, 14, 15));
    });

    test('Paytm notification', () {
      final t = parsed('Paid Rs.45 to Chai Point', MessageSource.notification);
      expect((t.amount, t.merchant), (45, 'Chai Point'));
    });

    test('reversal of a failed payment is a refund, not ignored', () {
      final t = parsed('Rs 300 for failed txn reversed to your A/c XX1234. UPI Ref 629500009999');
      expect(t.direction, TxnDirection.refund);
    });
  });

  group('negative — ignored or sent to review', () {
    test('empty / whitespace / small talk', () {
      expect(ignored(''), IgnoreReason.notFinancial);
      expect(ignored('   \n '), IgnoreReason.notFinancial);
      expect(ignored('Hi! Are we meeting today?'), IgnoreReason.notFinancial);
    });

    test('balance-only alert has no spend', () {
      expect(ignored('Your A/c XX1234 balance is Rs 5,000 as on 22-10-26'), IgnoreReason.notFinancial);
    });

    test('future / scheduled debits and payment requests', () {
      expect(ignored('Rs 499 will be debited on 25-10-26 for Netflix autopay'), IgnoreReason.request);
      expect(ignored('Electricity bill of Rs 1,200 is due on 30-10-26. Pay now'), IgnoreReason.request);
      expect(ignored('Ravi has requested ₹200 from you', MessageSource.notification), IgnoreReason.request);
    });

    test('Paytm/Airtel "top-up with code, grab ₹5 cashback" ad is ignored', () {
      expect(
        ignored(
          'Data Limit Alert!\nTop-up your Airtel data pack with code DATADEAL and grab ₹5 cashback instantly.',
          MessageSource.notification,
        ),
        IgnoreReason.promotional,
      );
    });

    test('a real debit that mentions cashback is still logged', () {
      final t = parsed('Rs 499 debited from A/c XX1234 to VPA airtel@paytm. You will get Rs 5 cashback. UPI Ref 629511118888');
      expect(t.amount, 499);
    });

    test('promotions, even with amounts', () {
      expect(ignored('Get cashback up to Rs 100 on your next order. T&C apply'), IgnoreReason.promotional);
      expect(ignored('Flat 50% off! Shop now at www.example.com'), IgnoreReason.promotional);
    });

    test('OTPs in either order', () {
      expect(ignored('Your OTP is 551234 for payment of Rs 999'), IgnoreReason.otp);
      expect(ignored('551234 is your one-time password'), IgnoreReason.otp);
    });

    test('declined / insufficient funds', () {
      expect(ignored('Txn of Rs 2,000 declined due to insufficient funds. A/c XX1234'), IgnoreReason.failed);
    });

    test('incoming money is not spending', () {
      expect(ignored('Rs 10,000 deposited in A/c XX1234 via NEFT'), IgnoreReason.credit);
      expect(ignored('You received ₹250 from Priya', MessageSource.notification), IgnoreReason.credit);
    });

    test('debit without an amount goes to Review', () {
      expect(parse('Your A/c XX1234 has been debited. Call us if not you'), isA<UnparsedMessage>());
    });

    test('date far from receipt time is ignored (uses receive time)', () {
      final t = parsed('Rs 60 debited from A/c XX1234 on 01-01-25 to VPA metro@upi');
      expect(t.occurredAt, received);
    });

    test('impossible dates are ignored safely', () {
      final t = parsed('Rs 60 debited from A/c XX1234 on 31-02-26 to VPA metro@upi');
      expect(t.occurredAt, received);
    });
  });

  group('extractors', () {
    test('UPI ref formats', () {
      expect(parser.extractUpiRef('UPI Ref No: 629512345678'), '629512345678');
      expect(parser.extractUpiRef('RRN 412345678901 done'), '412345678901');
      expect(parser.extractUpiRef('Info: UPI/P2M/629500001111/Swiggy'), '629500001111');
      expect(parser.extractUpiRef('Ref 123'), isNull, reason: 'too short to be a UPI ref');
    });

    test('amount extractor rejects zero / missing', () {
      expect(parser.extractAmount('Rs 0 debited'), isNull);
      expect(parser.extractAmount('no money here'), isNull);
    });
  });

  group('bank alerts only (app default)', () {
    const app = SmsParser();
    final at = DateTime(2026, 11, 2, 21, 15);
    ParseResult run(String body, [MessageSource s = MessageSource.sms]) =>
        app.parse(RawMessage(body: body, source: s, receivedAt: at));

    test('positive: Indian Bank "Sent" alert is logged', () {
      final r = run('Sent Rs.855.35 from A/c *7062 on 02-11-26 to mpokket.RRN 617345529735.'
          'Avl Bal Rs.1671.31.Not you?SMS BLOCK to 9289592895-Indian Bank');
      expect(r, isA<ParsedTxn>());
      r as ParsedTxn;
      expect(r.amount, 855.35);
      expect(r.direction, TxnDirection.debit);
      expect(r.merchant, 'Mpokket');
      expect(r.upiRef, '617345529735');
    });

    test('positive: long merchant name and debited wording', () {
      final r = run('Sent Rs.427.83 from A/c *7062 on 02-11-26 to MPOKKET FINANCIAL SERVICES PRI.'
          'RRN 219575188233.Avl Bal Rs.1243.48.Not you?SMS BLOCK to 9289592895-Indian Bank');
      expect((r as ParsedTxn).amount, 427.83);
      expect(run('Rs.200 debited from A/c XX1234 to VPA zomato@icici. UPI Ref 629500001111 - HDFC Bank'),
          isA<ParsedTxn>());
    });

    test('credited bank alert is read but not counted as spending', () {
      final r = run('Your A/c *7062 is credited with Rs.3500.00 on 04-11-26 by Ms Sudha. '
          'RRN 667451080806. Available balance is Rs. 4323.48 - Indian Bank');
      expect(r, isA<IgnoredMessage>());
      expect((r as IgnoredMessage).reason, IgnoreReason.credit);
    });

    test('any bank works, and "received" is read too', () {
      expect(run('Rs.640 debited from A/c XX5521 to Swiggy. UPI Ref 629500002222 - SBI Bank'), isA<ParsedTxn>());
      expect(run('INR 1,200.00 sent from your Axis Bank A/c XX9012 to Uber. RRN 629500003333'), isA<ParsedTxn>());
      final r = run('You have received Rs.500 in your A/c XX7781 from Ravi. - Canara Bank');
      expect((r as IgnoredMessage).reason, IgnoreReason.credit);
    });

    test('negative: SMS without a bank name is skipped', () {
      final r = run('Rs.250.00 debited from A/c XX1234 to VPA swiggy@icici (UPI Ref No 629512345678)');
      expect((r as IgnoredMessage).reason, IgnoreReason.notFinancial);
    });

    test('negative: bank SMS without credited/sent/debited is skipped', () {
      for (final body in [
        'Your Indian Bank debit card statement is ready. Avl Bal Rs.1000',
        'Indian Bank: update your KYC to continue using net banking',
        'Pay Rs 499 now and get cashback - XYZ Bank offer',
      ]) {
        expect((run(body) as IgnoredMessage).reason, IgnoreReason.notFinancial, reason: body);
      }
    });

    test('UPI app notifications are still read', () {
      expect(run('You paid ₹120 to Rapido', MessageSource.notification), isA<ParsedTxn>());
    });
  });
}
