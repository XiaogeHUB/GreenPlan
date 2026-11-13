/// 任务状态，对应 `task_sessions.status`。
enum TaskStatus {
  /// 计时中。
  running('running'),

  /// 正常完成并发奖。
  success('success'),

  /// 失败（切屏超时、分屏、进程被杀等），无奖励。
  failed('failed'),

  /// 用户主动放弃，无奖励。
  abandoned('abandoned'),

  /// 异常兜底：完成时仓库满，等用户清理后领取（规格 4.4）。
  successPendingReward('success_pending_reward');

  const TaskStatus(this.wireName);

  /// 落库用的字符串，**不要随意改名**，备份里也是这个值。
  final String wireName;

  static TaskStatus parse(String raw) {
    for (final status in TaskStatus.values) {
      if (status.wireName == raw) {
        return status;
      }
    }
    throw ArgumentError('未知的任务状态: $raw');
  }
}

/// 一次自律任务。
class TaskSession {
  const TaskSession({
    required this.id,
    required this.durationMinutes,
    required this.rewardDefinitionId,
    required this.startedAt,
    required this.expectedEndAt,
    required this.status,
    required this.createdAt,
    this.endedAt,
    this.failureReason,
    this.pendingRewardDefinitionId,
  });

  final String id;

  /// 选择的自律时长（分钟）。
  final int durationMinutes;

  /// 本次任务应发放的奖励定义 ID。
  final String rewardDefinitionId;

  final DateTime startedAt;

  /// 计时的唯一真相：到点即完成，不依赖递减 Timer（规格 4.3）。
  final DateTime expectedEndAt;

  final DateTime? endedAt;

  final TaskStatus status;

  /// 失败原因，例如 `process_death`、`background_timeout`。
  final String? failureReason;

  /// 仅 [TaskStatus.successPendingReward] 时有值。
  final String? pendingRewardDefinitionId;

  final DateTime createdAt;

  /// 是否已经到点。
  bool isDue(DateTime now) => !now.isBefore(expectedEndAt);

  /// 剩余时间；已到点时为 [Duration.zero]。
  Duration remainingAt(DateTime now) {
    final remaining = expectedEndAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// 0–1 的进度，用于进度环。
  double progressAt(DateTime now) {
    final total = expectedEndAt.difference(startedAt).inMilliseconds;
    if (total <= 0) {
      return 1;
    }
    final elapsed = now.difference(startedAt).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  TaskSession copyWith({
    String? id,
    String? rewardDefinitionId,
    DateTime? expectedEndAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
    TaskStatus? status,
    String? failureReason,
    String? pendingRewardDefinitionId,
  }) {
    return TaskSession(
      id: id ?? this.id,
      durationMinutes: durationMinutes,
      rewardDefinitionId: rewardDefinitionId ?? this.rewardDefinitionId,
      startedAt: startedAt,
      expectedEndAt: expectedEndAt ?? this.expectedEndAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
      pendingRewardDefinitionId:
          pendingRewardDefinitionId ?? this.pendingRewardDefinitionId,
      createdAt: createdAt,
    );
  }

  factory TaskSession.fromRow(Map<String, Object?> row) {
    return TaskSession(
      id: row['id']! as String,
      durationMinutes: row['duration_minutes']! as int,
      rewardDefinitionId: row['reward_definition_id']! as String,
      startedAt:
          DateTime.fromMillisecondsSinceEpoch(row['started_at']! as int),
      expectedEndAt:
          DateTime.fromMillisecondsSinceEpoch(row['expected_end_at']! as int),
      endedAt: _dateFromMs(row['ended_at']),
      status: TaskStatus.parse(row['status']! as String),
      failureReason: row['failure_reason'] as String?,
      pendingRewardDefinitionId:
          row['pending_reward_definition_id'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'duration_minutes': durationMinutes,
      'reward_definition_id': rewardDefinitionId,
      'started_at': startedAt.millisecondsSinceEpoch,
      'expected_end_at': expectedEndAt.millisecondsSinceEpoch,
      'ended_at': endedAt?.millisecondsSinceEpoch,
      'status': status.wireName,
      'failure_reason': failureReason,
      'pending_reward_definition_id': pendingRewardDefinitionId,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  static DateTime? _dateFromMs(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value as int);
  }

  @override
  String toString() =>
      'TaskSession($id, ${durationMinutes}min, ${status.wireName})';
}
