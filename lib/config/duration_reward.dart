import 'config_exception.dart';

/// 时长 → 奖励 的映射，来自 `assets/config/duration_rewards.json`。
///
/// 规格 1.2：15/30/60/120/240 分钟分别对应葱/香菜/上海青/小白菜/大白菜。
/// 另外支持 `seconds` 字段，用于调试时开一个几秒钟的档位。
class DurationReward {
  const DurationReward({this.minutes, this.seconds, required this.rewardId})
      : assert(
          (minutes == null) != (seconds == null),
          'minutes 与 seconds 必须且只能提供一个',
        );

  /// 以分钟为单位的时长；与 [seconds] 二选一。
  final int? minutes;

  /// 以秒为单位的时长（调试档位）；与 [minutes] 二选一。
  final int? seconds;

  /// 完成时发放的奖励定义 ID。
  final String rewardId;

  Duration get duration => seconds != null
      ? Duration(seconds: seconds!)
      : Duration(minutes: minutes!);

  int get totalSeconds => duration.inSeconds;

  bool get isSecondsOnly => seconds != null;

  /// 展示文案：`1 秒` / `15 分钟` / `4 小时`。
  String get label {
    if (isSecondsOnly) {
      return '$seconds 秒';
    }
    final value = minutes!;
    if (value < 60) {
      return '$value 分钟';
    }
    final hours = value ~/ 60;
    final rest = value % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
  }

  factory DurationReward.fromJson(Map<String, Object?> json) {
    final minutes = json['minutes'];
    final seconds = json['seconds'];
    final rewardId = json['rewardId'];

    if (rewardId is! String || rewardId.isEmpty) {
      throw ConfigException('时长映射 "rewardId" 必须是非空字符串: $json');
    }
    if (minutes == null && seconds == null) {
      throw ConfigException('时长映射必须提供 "minutes" 或 "seconds": $json');
    }
    if (minutes != null && seconds != null) {
      throw ConfigException('时长映射不能同时提供 "minutes" 与 "seconds": $json');
    }
    if (minutes != null) {
      if (minutes is! int || minutes <= 0) {
        throw ConfigException('时长映射 "minutes" 必须是正整数: $json');
      }
      return DurationReward(minutes: minutes, rewardId: rewardId);
    }
    if (seconds is! int || seconds <= 0) {
      throw ConfigException('时长映射 "seconds" 必须是正整数: $json');
    }
    return DurationReward(seconds: seconds, rewardId: rewardId);
  }

  @override
  String toString() => 'DurationReward($label -> $rewardId)';
}
