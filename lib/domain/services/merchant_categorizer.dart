/// Matches merchants to categories. Learned (user-corrected) rules win over
/// built-in keyword rules; among equals the longest keyword wins.
class MerchantRuleData {
  const MerchantRuleData(this.keyword, this.categoryId, {this.learned = false});
  final String keyword;
  final int categoryId;
  final bool learned;
}

class MerchantCategorizer {
  const MerchantCategorizer._();

  static String normalize(String merchant) => merchant
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static int? match(String? merchant, Iterable<MerchantRuleData> rules) {
    if (merchant == null || merchant.trim().isEmpty) return null;
    final key = normalize(merchant);
    MerchantRuleData? best;
    for (final r in rules) {
      final kw = normalize(r.keyword);
      if (kw.isEmpty) continue;
      final hit = r.learned ? key == kw : key.contains(kw);
      if (!hit) continue;
      if (best == null ||
          (r.learned && !best.learned) ||
          (r.learned == best.learned && kw.length > best.keyword.length)) {
        best = r;
      }
    }
    return best?.categoryId;
  }

  /// Built-in keyword rules, keyed by default category name.
  static const defaultKeywords = <String, List<String>>{
    'Food': ['swiggy', 'zomato', 'restaurant', 'cafe', 'dominos', 'pizza', 'kfc',
      'mcdonald', 'starbucks', 'bakery', 'blinkit', 'zepto', 'instamart', 'bigbasket', 'eats'],
    'Travel': ['uber', 'ola', 'rapido', 'irctc', 'metro', 'petrol', 'fuel', 'hpcl',
      'bpcl', 'indian oil', 'redbus', 'makemytrip', 'indigo', 'fastag', 'parking'],
    'Bills': ['electricity', 'airtel', 'jio', 'vodafone', 'bsnl', 'recharge',
      'broadband', 'bescom', 'tneb', 'gas', 'water', 'insurance', 'netflix', 'spotify', 'hotstar'],
    'Shopping': ['amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa',
      'decathlon', 'dmart', 'reliance', 'mall'],
  };
}
