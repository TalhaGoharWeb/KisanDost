import 'package:flutter_test/flutter_test.dart';
import 'package:kisan_dost/services/money.dart';

void main() {
  test('25-digit input throws MoneyParseException, not FormatException', () {
    expect(
      () => Money.parse('1234567890123456789012345'),
      throwsA(isA<MoneyParseException>()),
    );
  });
}
