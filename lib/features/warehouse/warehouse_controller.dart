import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/dao/reward_item_dao.dart';
import '../../data/db/dao/task_session_dao.dart';
import '../../data/models/reward_item.dart';
import '../../data/models/task_session.dart';
import '../../domain/services/synthesis_service.dart';
import '../../domain/services/task_service.dart';

/// 仓库页的数据与操作。
///
/// 状态是「整张仓库快照」，每次操作后重新读库，避免内存和数据库出现两份真相。
class WarehouseController extends AsyncNotifier<List<RewardItem>> {
  @override
  Future<List<RewardItem>> build() {
    return RewardItemDao(ref.watch(databaseProvider).db).getAll();
  }

  RewardItemDao get _dao => RewardItemDao(ref.read(databaseProvider).db);

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _dao.getAll());
  }

  /// 合成；成功返回 null，失败返回可直接展示的原因。
  Future<String?> synthesize({
    required RewardItem a,
    required RewardItem b,
  }) async {
    try {
      await ref.read(synthesisServiceProvider).synthesize(
            idA: a.id,
            idB: b.id,
            targetSlot: b.slotIndex,
          );
      await reload();
      ref.invalidate(currentTitleProvider);
      return null;
    } on SynthesisException catch (error) {
      return error.message;
    }
  }

  /// 把物品移动到空格；目标被占用时返回提示。
  Future<String?> moveTo(RewardItem item, int slotIndex) async {
    if (await _dao.getBySlot(slotIndex) != null) {
      return '目标格位已被占用';
    }
    await _dao.updateSlot(id: item.id, slotIndex: slotIndex);
    await reload();
    return null;
  }

  Future<void> delete(RewardItem item) async {
    await _dao.deleteById(item.id);
    await reload();
  }

  /// 一键清理过期，返回清理数量。
  Future<int> clearExpired(DateTime now) async {
    final removed = await _dao.deleteExpiredAt(now);
    await reload();
    return removed;
  }

  /// 清空整个仓库（设置页的重置用）。
  Future<void> clearAll() async {
    await _dao.deleteAll();
    await reload();
  }

  /// 补发 `success_pending_reward` 的任务奖励，返回补发数量。
  ///
  /// 仓库满时完成的任务会把奖励挂着，这里在用户腾出空间后补上。
  Future<int> claimPendingRewards() async {
    final sessions =
        await TaskSessionDao(ref.read(databaseProvider).db)
            .findByStatus(TaskStatus.successPendingReward);
    var claimed = 0;
    for (final session in sessions) {
      try {
        await ref.read(taskServiceProvider).claimPendingReward(session.id);
        claimed++;
      } on TaskException {
        break; // 仓库仍然满，下次再补
      }
    }
    if (claimed > 0) {
      await reload();
      ref.invalidate(currentTitleProvider);
    }
    return claimed;
  }
}

final warehouseProvider =
    AsyncNotifierProvider<WarehouseController, List<RewardItem>>(
  WarehouseController.new,
);
