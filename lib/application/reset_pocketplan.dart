import '../data/db/app_database.dart';
import '../domain/entities/app_settings.dart';

/// Use case behind Settings → Reset data: wipes all PocketPlan data and
/// sends the user back to budget setup. DoList notes, theme, currency and
/// the onboarding flag are kept.
class ResetPocketPlan {
  const ResetPocketPlan(this._db, this._updateSettings);

  final AppDatabase _db;
  final Future<void> Function(AppSettings Function(AppSettings)) _updateSettings;

  Future<void> call() async {
    await _db.resetPocketPlan();
    await _updateSettings((s) => AppSettings(
          onboardingSeen: true,
          themeMode: s.themeMode,
          currencyCode: s.currencyCode,
        ));
  }
}
