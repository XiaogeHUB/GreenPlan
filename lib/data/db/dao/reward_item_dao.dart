import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../../models/reward_item.dart';

/// `reward_items` 表的读写。
///
/// 只做数据存取，不含业务判断（能不能合成、怎么合成属于 Service 层）。
class RewardItemDao {
  RewardItemDao(this._executor);

  final DatabaseExecutor _executor;

  static const String table = 'reward_items';

  /// 交换两个物品的格位时用的临时格位，避开 `slot_index` 唯一索引。
  static const int _swapTempSlot = -1;

  Future<List<RewardItem>> getAll() async {
    final rows = await _executor.query(table, orderBy: 'slot_index ASC');
    return rows.map(RewardItem.fromRow).toList(growable: false);
  }

  Future<RewardItem?> getById(String id) async {
    final rows = await _executor.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : RewardItem.fromRow(rows.first);
  }

  Future<RewardItem?> getBySlot(int slotIndex) async {
    final rows = await _executor.query(
      table,
      where: 'slot_index = ?',
      whereArgs: <Object?>[slotIndex],
      limit: 1,
    );
    return rows.isEmpty ? null : RewardItem.fromRow(rows.first);
  }

  Future<Set<int>> occupiedSlots() async {
    final rows = await _executor.query(table, columns: <String>['slot_index']);
    return <int>{for (final row in rows) row['slot_index']! as int};
  }

  /// 第一个空闲格位；仓库满时返回 null。
  Future<int?> firstFreeSlot({int capacity = AppDatabase.warehouseCapacity}) async {
    final occupied = await occupiedSlots();
    for (var slot = 0; slot < capacity; slot++) {
      if (!occupied.contains(slot)) {
        return slot;
      }
    }
    return null;
  }

  Future<bool> hasFreeSlot({int capacity = AppDatabase.warehouseCapacity}) async {
    return await firstFreeSlot(capacity: capacity) != null;
  }

  /// 插入；格位冲突会由唯一索引直接报错，而不是静默覆盖。
  Future<void> insert(RewardItem item) async {
    await _executor.insert(
      table,
      item.toRow(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(RewardItem item) async {
    final affected = await _executor.update(
      table,
      item.toRow(),
      where: 'id = ?',
      whereArgs: <Object?>[item.id],
    );
    if (affected == 0) {
      throw StateError('物品不存在，无法更新: ${item.id}');
    }
  }

  Future<void> updateSlot({required String id, required int slotIndex}) async {
    final affected = await _executor.update(
      table,
      <String, Object?>{'slot_index': slotIndex},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (affected == 0) {
      throw StateError('物品不存在，无法移动: $id');
    }
  }

  /// 交换两个物品的格位。
  ///
  /// 唯一索引不允许两条记录同时指向同一格，因此先把 A 挪到临时格位。
  /// 调用方应放在事务里，避免中途失败留下临时格位。
  Future<void> swapSlots({required String idA, required String idB}) async {
    if (idA == idB) {
      return;
    }
    final a = await getById(idA);
    final b = await getById(idB);
    if (a == null) {
      throw StateError('物品不存在: $idA');
    }
    if (b == null) {
      throw StateError('物品不存在: $idB');
    }
    await updateSlot(id: idA, slotIndex: _swapTempSlot);
    await updateSlot(id: idB, slotIndex: a.slotIndex);
    await updateSlot(id: idA, slotIndex: b.slotIndex);
  }

  Future<void> deleteById(String id) async {
    await _executor.delete(table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 已过期的物品（含 `expire_at == now` 的边界情况）。
  Future<List<RewardItem>> expiredAt(DateTime now) async {
    final rows = await _executor.query(
      table,
      where: 'expire_at IS NOT NULL AND expire_at <= ?',
      whereArgs: <Object?>[now.millisecondsSinceEpoch],
      orderBy: 'slot_index ASC',
    );
    return rows.map(RewardItem.fromRow).toList(growable: false);
  }

  Future<int> deleteExpiredAt(DateTime now) {
    return _executor.delete(
      table,
      where: 'expire_at IS NOT NULL AND expire_at <= ?',
      whereArgs: <Object?>[now.millisecondsSinceEpoch],
    );
  }

  Future<void> deleteAll() async {
    await _executor.delete(table);
  }
}
