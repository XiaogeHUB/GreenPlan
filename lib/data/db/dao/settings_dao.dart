import 'package:sqflite/sqflite.dart';

/// `settings` 表的读写（key-value）。
class SettingsDao {
  SettingsDao(this._executor);

  final DatabaseExecutor _executor;

  static const String table = 'settings';

  static const String expiryNotificationKey = 'expiry_notification';
  static const String onboardingShownKey = 'onboarding_shown';

  Future<String?> get(String key) async {
    final rows = await _executor.query(
      table,
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<bool> getBool(String key, {bool fallback = false}) async {
    final raw = await get(key);
    if (raw == null) {
      return fallback;
    }
    return raw == 'true';
  }

  Future<void> put(String key, String value) async {
    await _executor.insert(
      table,
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> putBool(String key, bool value) => put(key, value ? 'true' : 'false');

  Future<void> putAll(Map<String, String> values) async {
    final batch = _executor.batch();
    values.forEach((key, value) {
      batch.insert(
        table,
        <String, Object?>{'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  Future<Map<String, String>> getAll() async {
    final rows = await _executor.query(table);
    return <String, String>{
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
  }

  Future<void> delete(String key) async {
    await _executor.delete(table, where: 'key = ?', whereArgs: <Object?>[key]);
  }
}
