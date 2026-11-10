import 'dart:convert';

import 'package:daily_budget/data/settings_store.dart';
import 'package:daily_budget/domain/entities/app_settings.dart';
import 'package:daily_budget/domain/services/merchant_categorizer.dart';
import 'package:daily_budget/presentation/common.dart';
import 'package:daily_budget/presentation/dolist_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MerchantCategorizer', () {
    const rules = [
      MerchantRuleData('swiggy', 1),
      MerchantRuleData('swiggy instamart', 2),
      MerchantRuleData('swiggy', 3, learned: true),
      MerchantRuleData('uber', 4),
    ];

    test('learned rule beats keyword rule', () {
      expect(MerchantCategorizer.match('SWIGGY', rules), 3);
    });

    test('longest keyword wins among keyword rules', () {
      expect(MerchantCategorizer.match('Swiggy Instamart Order', rules.where((r) => !r.learned)), 2);
    });

    test('learned rules need an exact (normalised) match', () {
      expect(MerchantCategorizer.match('Swiggy!!', rules), 3);
      expect(MerchantCategorizer.match('Swiggy Genie', [const MerchantRuleData('swiggy', 9, learned: true)]), isNull);
    });

    test('no merchant / blank / unknown → null', () {
      expect(MerchantCategorizer.match(null, rules), isNull);
      expect(MerchantCategorizer.match('  ', rules), isNull);
      expect(MerchantCategorizer.match('Local Kirana', rules), isNull);
    });
  });

  group('AppSettings', () {
    test('JSON round trip keeps every field', () {
      final s = AppSettings(
        onboardingSeen: true,
        setupDone: true,
        monthlyBudget: 12345.5,
        cycleStartDay: 18,
        periodStart: DateTime(2026, 10, 18),
        periodEnd: DateTime(2026, 11, 17),
        rollover: false,
        currencyCode: 'USD',
        themeMode: ThemeMode.dark,
        reminderEnabled: true,
        reminderMinutes: 8 * 60 + 15,
        overLimitAlert: false,
        autoTrackingEnabled: true,
        morningLimit: false,
        weeklyInsight: false,
      );
      final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
    });

    test('missing / unknown values fall back to safe defaults', () {
      // Includes a leftover field from the removed wallpaper feature: ignored.
      final s = AppSettings.fromJson({'themeMode': 'purple', 'todoWallpaper': true, 'periodStart': 'nope'});
      expect(s.themeMode, ThemeMode.light);
      expect(s.periodStart, isNull);
      expect(s.currencyCode, 'INR');
      expect(s.morningLimit, isTrue);
      expect(s.weeklyInsight, isTrue);
    });

    test('cycleFor uses the custom period when set, start day otherwise', () {
      final custom = AppSettings(periodStart: DateTime(2026, 11, 1), periodEnd: DateTime(2026, 11, 14));
      expect(custom.cycleFor(DateTime(2026, 11, 20)).start, DateTime(2026, 11, 15));
      expect(const AppSettings(cycleStartDay: 10).cycleFor(DateTime(2026, 11, 20)).start, DateTime(2026, 11, 10));
    });

    test('corrupted stored settings do not crash the app', () async {
      SharedPreferences.setMockInitialValues({'app_settings_v1': '{not json'});
      final store = SettingsStore(await SharedPreferences.getInstance());
      expect(store.load().setupDone, isFalse);
    });

    test('saved settings load back', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore(await SharedPreferences.getInstance());
      await store.save(const AppSettings(monthlyBudget: 999, setupDone: true));
      expect(store.load().monthlyBudget, 999);
    });
  });

  group('Money formatting', () {
    test('INR uses Indian grouping and no decimals', () {
      expect(Money('INR')(123456.4), '₹1,23,456');
    });

    test('negative amounts get a minus sign, tiny negatives do not', () {
      expect(Money('INR')(-2620), '−₹2,620');
      expect(Money('INR')(-0.2), '₹0');
    });

    test('unknown currency code falls back to INR', () {
      expect(Money('XXX')(10), '₹10');
    });
  });

  group('DoList helpers', () {
    test('cheer text covers empty, none, some, most, all', () {
      expect(doListCheer(0, 0), contains('Fresh page'));
      expect(doListCheer(0, 3), contains('first one'));
      expect(doListCheer(1, 4), contains('Nice start'));
      expect(doListCheer(3, 4), contains('1 to go'));
      expect(doListCheer(4, 4), contains('All done'));
    });

    test('note colours wrap around and accept bad indices', () {
      expect(NoteStyle.of(NoteStyle.all.length), NoteStyle.all.first);
      expect(NoteStyle.of(-1), isNotNull);
    });
  });
}
