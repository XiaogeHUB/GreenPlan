import '../../config/reward_definition.dart';
import '../../data/models/reward_item.dart';

/// 一条待发的过期提醒。
class ExpiryNotification {
  const ExpiryNotification({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
  });

  /// 通知 ID，由物品 ID 稳定推导，重启后仍能对应同一件物品。
  final int id;
  final DateTime scheduledAt;
  final String title;
  final String body;
}

/// 过期提醒的调度计划（纯计算，方便单元测试）。
///
/// 规则（规格第 10 节 + 决策记录）：
/// - 只给普通奖励（有 `expireAt`）排提醒；
/// - 提前 [leadTime]（默认 12 小时）提醒一次；
/// - 如果提前量已经过去但仍未过期，就 30 秒后立刻提醒；
/// - 已经过期的物品不提醒（由仓库页的「已过期」展示负责）。
List<ExpiryNotification> buildExpiryPlan({
  required List<RewardItem> items,
  required RewardDefinition? Function(String definitionId) definitionOf,
  required DateTime now,
  Duration leadTime = const Duration(hours: 12),
  Duration fallbackDelay = const Duration(seconds: 30),
}) {
  final plan = <ExpiryNotification>[];
  for (final item in items) {
    final expireAt = item.expireAt;
    if (expireAt == null || !expireAt.isAfter(now)) {
      continue;
    }
    final definition = definitionOf(item.definitionId);
    if (definition == null) {
      continue;
    }

    var scheduledAt = expireAt.subtract(leadTime);
    if (!scheduledAt.isAfter(now)) {
      scheduledAt = now.add(fallbackDelay);
    }

    final name = item.level > 1
        ? '${item.level} 级${definition.name}'
        : definition.name;
    final remaining = expireAt.difference(now);
    plan.add(
      ExpiryNotification(
        id: notificationIdFor(item.id),
        scheduledAt: scheduledAt,
        title: '奖励即将过期',
        body: '你的「$name」还有 ${_describe(remaining)} 过期，记得合成。',
      ),
    );
  }
  plan.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return plan;
}

/// 由物品 ID 推导稳定的通知 ID（FNV-1a 32 位，取正）。
///
/// 不用 `String.hashCode`：它不保证跨进程/跨版本稳定，重启后就没法精确取消。
int notificationIdFor(String itemId) {
  var hash = 0x811c9dc5;
  for (final unit in itemId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

String _describe(Duration remaining) {
  if (remaining.inDays >= 1) {
    return '${remaining.inDays} 天';
  }
  if (remaining.inHours >= 1) {
    return '${remaining.inHours} 小时';
  }
  return '${remaining.inMinutes} 分钟';
}
