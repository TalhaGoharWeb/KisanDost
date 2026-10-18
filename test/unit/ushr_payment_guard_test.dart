import 'package:flutter_test/flutter_test.dart';

import 'package:kisan_dost/providers/ushr_provider.dart';

/// D2 regression (2026-10-18): an ushr payment must never exceed the ushr
/// due. The guard lives in [UshrProvider.validatePaymentWithinDue] so both
/// add and edit paths share it; the ushr dialog shows the Urdu message and
/// keeps the form open.
///
/// Hand-computed reference: due Rs 14,000 = 1,400,000 paisa.
/// A mixed payment of Rs 5,000 cash + 2 من @ Rs 3,500/من =
/// 500,000 + 700,000 = 1,200,000 paisa — under the due, accepted.
void main() {
  group('validatePaymentWithinDue', () {
    test('accepts a payment below the due', () {
      expect(
        () => UshrProvider.validatePaymentWithinDue(
          ushrAmountPaisa: 1400000,
          cashPaidPaisa: 500000,
          qtyPaid: 2.0,
          ratePerUnitPaisa: 350000,
        ),
        returnsNormally,
      );
    });

    test('accepts a payment exactly equal to the due', () {
      // 700,000 + 2 × 350,000 = 1,400,000 == due → Paid, not overpaid.
      expect(
        () => UshrProvider.validatePaymentWithinDue(
          ushrAmountPaisa: 1400000,
          cashPaidPaisa: 700000,
          qtyPaid: 2.0,
          ratePerUnitPaisa: 350000,
        ),
        returnsNormally,
      );
    });

    test('accepts a zero payment (nothing paid yet)', () {
      expect(
        () => UshrProvider.validatePaymentWithinDue(
          ushrAmountPaisa: 1400000,
          cashPaidPaisa: 0,
          qtyPaid: 0.0,
          ratePerUnitPaisa: 350000,
        ),
        returnsNormally,
      );
    });

    test('rejects an overpayment with a Urdu error naming both amounts', () {
      // 1,000,000 + 2 × 350,000 = 1,700,000 > 1,400,000 due.
      expect(
        () => UshrProvider.validatePaymentWithinDue(
          ushrAmountPaisa: 1400000,
          cashPaidPaisa: 1000000,
          qtyPaid: 2.0,
          ratePerUnitPaisa: 350000,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('زیادہ ہے'), contains('17,000')),
          ),
        ),
      );
    });

    test('rejects a cash-only overpayment', () {
      expect(
        () => UshrProvider.validatePaymentWithinDue(
          ushrAmountPaisa: 1400000,
          cashPaidPaisa: 1400001,
          qtyPaid: 0.0,
          ratePerUnitPaisa: 350000,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects a negative cash payment', () {
      expect(
        () => UshrProvider.validatePaymentWithinDue(
          ushrAmountPaisa: 1400000,
          cashPaidPaisa: -1000,
          qtyPaid: 0.0,
          ratePerUnitPaisa: 350000,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('منفی'),
          ),
        ),
      );
    });

    test('rejects a negative in-kind quantity', () {
      expect(
        () => UshrProvider.validatePaymentWithinDue(
          ushrAmountPaisa: 1400000,
          cashPaidPaisa: 0,
          qtyPaid: -2.0,
          ratePerUnitPaisa: 350000,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
