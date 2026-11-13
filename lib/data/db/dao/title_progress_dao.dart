import 'package:sqflite/sqflite.dart';

/// `title_progress` 表的读写：只记录历史最高的苦瓜等级。
///
/// 规格 1.6：删掉苦瓜不会让称号降级，所以这里是单调递增的。
class TitleProgressDao {
  TitleProgressDao(this._executor);

  final DatabaseExecutor _executor;

  static const String table = 'title_progress';

  Future<int> getMaxLevel() async {
    final rows = await _executor.query(table, limit: 1);
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first['max_guada_level']! as int;
  }

  Future<void> setMaxLevel(int level) async {
    await _executor.insert(
      table,
      <String, Object?>{'id': 1, 'max_guada_level': level < 0 ? 0 : level},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 用 [candidate] 尝试刷新历史最高等级，返回更新后的值。
  ///
  /// 只在「合成出苦瓜」时调用；比当前低的值不会让记录下降。
  Future<int> bumpMaxLevel(int candidate) async {
    final value = candidate < 0 ? 0 : candidate;
    await _executor.insert(
      table,
      <String, Object?>{'id': 1, 'max_guada_level': value},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _executor.rawUpdate(
      'UPDATE $table SET max_guada_level = MAX(max_guada_level, ?) WHERE id = 1',
      <Object?>[value],
    );
    return getMaxLevel();
  }
}
