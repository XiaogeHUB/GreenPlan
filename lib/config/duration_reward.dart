import 'config_exception.dart';

/// 时长 → 奖励 的映射，来自 `assets/config/duration_rewards.json`。
///
/// 规格 1.2：15/30/60/120/240 分钟分别对应葱/香菜/上海青/小白菜/大白菜。
class DurationReward {
  const DurationReward({required this.minutes, required this.rewardId});

  /// 自律时长（分钟），必须为正整数。
  final int minutes;

  /// 完成时发放的奖励定义 ID。
  final String rewardId;

  factory DurationReward.fromJson(Map<String, Object?> json) {
    final minutes = json['minutes'];
    final rewardId = json['rewardId'];
    if (minutes is! int || minutes <= 0) {
      throw ConfigException('时长映射 "minutes" 必须是正整数: $json');
    }
    if (rewardId is! String || rewardId.isEmpty) {
      throw ConfigException('时长映射 "rewardId" 必须是非空字符串: $json');
    }
    return DurationReward(minutes: minutes, rewardId: rewardId);
  }

  @override
  String toString() => 'DurationReward(${minutes}min -> $rewardId)';
}
