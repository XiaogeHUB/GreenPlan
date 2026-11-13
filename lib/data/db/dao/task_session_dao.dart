import 'package:sqflite/sqflite.dart';

import '../../models/task_session.dart';

/// `task_sessions` 表的读写。
class TaskSessionDao {
  TaskSessionDao(this._executor);

  final DatabaseExecutor _executor;

  static const String table = 'task_sessions';

  /// 当前正在计时的任务；正常情况下最多一条。
  Future<TaskSession?> findRunning() async {
    final rows = await _executor.query(
      table,
      where: 'status = ?',
      whereArgs: <Object?>[TaskStatus.running.wireName],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TaskSession.fromRow(rows.first);
  }

  Future<TaskSession?> getById(String id) async {
    final rows = await _executor.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : TaskSession.fromRow(rows.first);
  }

  Future<List<TaskSession>> findByStatus(TaskStatus status) async {
    final rows = await _executor.query(
      table,
      where: 'status = ?',
      whereArgs: <Object?>[status.wireName],
      orderBy: 'created_at DESC',
    );
    return rows.map(TaskSession.fromRow).toList(growable: false);
  }

  Future<List<TaskSession>> recent({int limit = 20}) async {
    final rows = await _executor.query(
      table,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(TaskSession.fromRow).toList(growable: false);
  }

  Future<void> insert(TaskSession session) async {
    await _executor.insert(
      table,
      session.toRow(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(TaskSession session) async {
    final affected = await _executor.update(
      table,
      session.toRow(),
      where: 'id = ?',
      whereArgs: <Object?>[session.id],
    );
    if (affected == 0) {
      throw StateError('任务不存在，无法更新: ${session.id}');
    }
  }

  /// 冷启动时把所有 `running` 任务判为失败（规格 4.6）。
  ///
  /// 返回被改写的行数。
  Future<int> failAllRunning({
    required String reason,
    required DateTime endedAt,
  }) {
    return _executor.update(
      table,
      <String, Object?>{
        'status': TaskStatus.failed.wireName,
        'failure_reason': reason,
        'ended_at': endedAt.millisecondsSinceEpoch,
      },
      where: 'status = ?',
      whereArgs: <Object?>[TaskStatus.running.wireName],
    );
  }
}
