/// 仓库里的一个物品实例。
///
/// 与 [RewardDefinition] 的区别：定义是配置里的「葱」，实例是玩家仓库里的
/// 「第 7 号格子的那把葱，2026-11-16 12:00 过期」。
class RewardItem {
  const RewardItem({
    required this.id,
    required this.definitionId,
    required this.slotIndex,
    required this.createdAt,
    this.level = 1,
    this.expireAt,
    this.sourceTaskId,
    this.effectsJson,
    this.locked = false,
  });

  /// UUID，主键。
  final String id;

  /// 对应 `rewards.json` 里的定义 ID。
  final String definitionId;

  /// 苦瓜用等级做运算；普通/特殊奖励恒为 1。
  final int level;

  /// 仓库格位，0–23。
  final int slotIndex;

  final DateTime createdAt;

  /// 过期时间；永久奖励为 null。
  ///
  /// 规格 6.1：过期状态**不落库**，始终由 `expireAt` 与当前时间比较得出。
  final DateTime? expireAt;

  /// 由哪个任务产出。
  final String? sourceTaskId;

  /// 预留给后续「道具/效果」扩展。
  final String? effectsJson;

  /// 预留给后续锁定功能，首版恒为 false。
  final bool locked;

  /// 规格 1.3：`expire_at == now` 即算过期。
  bool isExpiredAt(DateTime now) {
    final deadline = expireAt;
    return deadline != null && !now.isBefore(deadline);
  }

  /// 距离过期的剩余时间；永久奖励或已过期为 null / 负值由调用方判断。
  Duration? remainingAt(DateTime now) {
    final deadline = expireAt;
    return deadline?.difference(now);
  }

  RewardItem copyWith({
    String? id,
    String? definitionId,
    int? level,
    int? slotIndex,
    DateTime? createdAt,
    DateTime? expireAt,
    bool clearExpireAt = false,
    String? sourceTaskId,
    String? effectsJson,
    bool? locked,
  }) {
    return RewardItem(
      id: id ?? this.id,
      definitionId: definitionId ?? this.definitionId,
      level: level ?? this.level,
      slotIndex: slotIndex ?? this.slotIndex,
      createdAt: createdAt ?? this.createdAt,
      expireAt: clearExpireAt ? null : (expireAt ?? this.expireAt),
      sourceTaskId: sourceTaskId ?? this.sourceTaskId,
      effectsJson: effectsJson ?? this.effectsJson,
      locked: locked ?? this.locked,
    );
  }

  factory RewardItem.fromRow(Map<String, Object?> row) {
    return RewardItem(
      id: row['id']! as String,
      definitionId: row['definition_id']! as String,
      level: row['level']! as int,
      slotIndex: row['slot_index']! as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      expireAt: _dateFromMs(row['expire_at']),
      sourceTaskId: row['source_task_id'] as String?,
      effectsJson: row['effects_json'] as String?,
      locked: (row['locked']! as int) != 0,
    );
  }

  Map<String, Object?> toRow() {
    return <String, Object?>{
      'id': id,
      'definition_id': definitionId,
      'level': level,
      'slot_index': slotIndex,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expire_at': expireAt?.millisecondsSinceEpoch,
      'source_task_id': sourceTaskId,
      'effects_json': effectsJson,
      'locked': locked ? 1 : 0,
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
      'RewardItem($id, ${definitionId}x$level, slot: $slotIndex)';
}
