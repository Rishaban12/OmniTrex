/// One rule for every money amount the user types (Add expense, Parser,
/// Setup, fixed expenses): a positive, finite number, at most 2 decimals'
/// worth of sense, Indian or western grouping allowed ("1,00,000" / "100,000").
class AmountInput {
  const AmountInput._();

  /// Largest amount accepted (₹10 crore): guards against typos like
  /// "50000000000" and against doubles losing paise precision.
  static const max = 100000000.0;

  /// The amount, or null when it is empty, not a number, zero, negative,
  /// infinite or above [max]. Rounded to paise.
  static double? parse(String? text) {
    if (text == null) return null;
    final cleaned = text.trim().replaceAll(',', '').replaceAll(RegExp(r'^(₹|rs\.?|inr)\s*', caseSensitive: false), '');
    if (cleaned.isEmpty || !RegExp(r'^\d*\.?\d+$').hasMatch(cleaned)) return null;
    final v = double.tryParse(cleaned);
    if (v == null || !v.isFinite || v <= 0 || v > max) return null;
    return (v * 100).roundToDouble() / 100;
  }

  /// Throws [ArgumentError] unless [amount] is a valid stored amount.
  /// Used by repositories as a last line of defence.
  static double require(double amount, [String name = 'amount']) {
    if (!amount.isFinite || amount <= 0 || amount > max) {
      throw ArgumentError.value(amount, name, 'must be > 0 and ≤ $max');
    }
    return amount;
  }
}
