import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../data/db/app_database.dart';
import '../../data/db/dao/reward_item_dao.dart';
import '../../data/db/dao/task_session_dao.dart';
import '../../data/models/reward_item.dart';
import '../../data/models/task_session.dart';

/// 任务操作失败的原因。
class TaskException implements Exception {
  const TaskException(this.message);

  final String message;

  @override
  String toString() => 'TaskException: $message';
}

/// 任务状态机（规格第 4 节）。
///
/// 只负责任务本身：开始、完成、失败、放弃、冷启动恢复。
/// 切屏/来电/息屏这些中断事件由后续的中断管理器调用 [failTask]。
class TaskService {
  TaskService({
    required this.db,
    required this.config,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final AppConfig config;
  final DateTime Function() _clock;

  /// 冷启动判定「进程被杀」时写入的失败原因。
  static const String reasonProcessDeath = 'process_death';

  Future<TaskSession?> findRunning() => TaskSessionDao(db.db).findRunning();

  /// 开始一个自律任务。
  ///
  /// 拒绝条件：已有进行中的任务 / 时长未配置 / 仓库已满（规格 4.2）。
  Future<TaskSession> startTask({required int durationMinutes}) {
    final now = _clock();
    return db.transaction((txn) async {
      final taskDao = TaskSessionDao(txn);

      final existing = await taskDao.findRunning();
      if (existing != null) {
        throw const TaskException('已有进行中的任务');
      }

      final reward = config.rewardForMinutes(durationMinutes);
      if (reward == null) {
        throw TaskException('未配置的时长: $durationMinutes 分钟');
      }

      final hasFreeSlot = await RewardItemDao(txn).hasFreeSlot();
      if (!hasFreeSlot) {
        throw const TaskException('仓库已满，请先合成或删除奖励');
      }

      final session = TaskSession(
        id: const Uuid().v4(),
        durationMinutes: durationMinutes,
        rewardDefinitionId: reward.id,
        startedAt: now,
        expectedEndAt: now.add(Duration(minutes: durationMinutes)),
        status: TaskStatus.running,
        createdAt: now,
      );
      await taskDao.insert(session);
      return session;
    });
  }

  /// 到点完成任务并发放奖励。
  ///
  /// 仓库满时（异常情况）不丢弃奖励，而是标记 `success_pending_reward`，
  /// 等用户清理后调用 [claimPendingReward]。
  Future<TaskSession> completeTask(String sessionId) {
    final now = _clock();
    return db.transaction((txn) async {
      final taskDao = TaskSessionDao(txn);
      final session = await taskDao.getById(sessionId);
      if (session == null) {
        throw TaskException('任务不存在: $sessionId');
      }
      if (session.status != TaskStatus.running) {
        throw TaskException('任务不是进行中状态: ${session.status.wireName}');
      }
      if (!session.isDue(now)) {
        throw const TaskException('任务尚未到点，不能完成');
      }

      final reward = config.rewardById(session.rewardDefinitionId);
      if (reward == null) {
        throw TaskException('奖励定义不存在: ${session.rewardDefinitionId}');
      }

      final itemDao = RewardItemDao(txn);
      final slot = await itemDao.firstFreeSlot();
      if (slot == null) {
        final pending = session.copyWith(
          status: TaskStatus.successPendingReward,
          endedAt: now,
          pendingRewardDefinitionId: reward.id,
        );
        await taskDao.update(pending);
        return pending;
      }

      await itemDao.insert(_buildRewardItem(session, reward.id, slot, now));
      final done = session.copyWith(
        status: TaskStatus.success,
        endedAt: now,
      );
      await taskDao.update(done);
      return done;
    });
  }

  /// 领取 `success_pending_reward` 状态的任务奖励。
  Future<TaskSession> claimPendingReward(String sessionId) {
    final now = _clock();
    return db.transaction((txn) async {
      final taskDao = TaskSessionDao(txn);
      final session = await taskDao.getById(sessionId);
      if (session == null) {
        throw TaskException('任务不存在: $sessionId');
      }
      if (session.status != TaskStatus.successPendingReward) {
        throw TaskException('任务没有待领取的奖励: ${session.status.wireName}');
      }

      final definitionId =
          session.pendingRewardDefinitionId ?? session.rewardDefinitionId;
      final reward = config.rewardById(definitionId);
      if (reward == null) {
        throw TaskException('奖励定义不存在: $definitionId');
      }

      final itemDao = RewardItemDao(txn);
      final slot = await itemDao.firstFreeSlot();
      if (slot == null) {
        throw const TaskException('仓库仍然已满，请先清理');
      }

      await itemDao.insert(_buildRewardItem(session, reward.id, slot, now));
      final claimed = session.copyWith(status: TaskStatus.success);
      await taskDao.update(claimed);
      return claimed;
    });
  }

  /// 判定任务失败（切屏超时、分屏、进程被杀等）。
  Future<TaskSession> failTask(String sessionId, {required String reason}) {
    return _finish(
      sessionId,
      status: TaskStatus.failed,
      failureReason: reason,
    );
  }

  /// 用户主动放弃。
  Future<TaskSession> abandonTask(String sessionId) {
    return _finish(sessionId, status: TaskStatus.abandoned);
  }

  /// 冷启动：把仍在 `running` 的任务全部判为「应用被系统关闭」（规格 4.6）。
  ///
  /// 同一进程内从后台返回不适用，那是中断管理器的事。
  Future<int> recoverRunningAfterColdStart() {
    return TaskSessionDao(db.db).failAllRunning(
      reason: reasonProcessDeath,
      endedAt: _clock(),
    );
  }

  Future<TaskSession> _finish(
    String sessionId, {
    required TaskStatus status,
    String? failureReason,
  }) {
    final now = _clock();
    return db.transaction((txn) async {
      final taskDao = TaskSessionDao(txn);
      final session = await taskDao.getById(sessionId);
      if (session == null) {
        throw TaskException('任务不存在: $sessionId');
      }
      if (session.status != TaskStatus.running) {
        throw TaskException('任务不是进行中状态: ${session.status.wireName}');
      }
      final finished = session.copyWith(
        status: status,
        endedAt: now,
        failureReason: failureReason,
      );
      await taskDao.update(finished);
      return finished;
    });
  }

  RewardItem _buildRewardItem(
    TaskSession session,
    String definitionId,
    int slotIndex,
    DateTime now,
  ) {
    final reward = config.rewardById(definitionId);
    if (reward == null) {
      throw TaskException('奖励定义不存在: $definitionId');
    }
    return RewardItem(
      id: const Uuid().v4(),
      definitionId: definitionId,
      slotIndex: slotIndex,
      createdAt: now,
      expireAt: reward.permanent
          ? null
          : now.add(Duration(hours: reward.shelfLifeHours!)),
      sourceTaskId: session.id,
    );
  }
}
