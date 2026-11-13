import 'config_exception.dart';

/// 奖励类型，对应 `rewards.json` 的 `type` 字段。
enum RewardType {
  /// 普通奖励：有保质期，会过期（葱 → 大白菜）。
  ordinary,

  /// 特殊奖励：永久，不可过期（芹菜 → 丝瓜）。
  special,

  /// 苦瓜：永久，等级由合成累加，无上限。
  bitter;

  /// 解析配置文件里的字符串，未知值直接报配置错误。
  static RewardType parse(String raw) {
    switch (raw) {
      case 'ordinary':
        return RewardType.ordinary;
      case 'special':
        return RewardType.special;
      case 'bitter':
        return RewardType.bitter;
    }
    throw ConfigException('未知的奖励类型: "$raw"（只允许 ordinary / special / bitter）');
  }
}

/// 单个奖励的静态定义，来自 `assets/config/rewards.json`。
///
/// 注意：这是一份**配置**，不是玩家仓库里的物品实例；实例见后续的 RewardItem。
class RewardDefinition {
  const RewardDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.level,
    required this.order,
    required this.nextId,
    required this.permanent,
    required this.shelfLifeHours,
    required this.bitterCombine,
    required this.icon,
  });

  /// 稳定标识，写进数据库与备份，**不允许随意改名**。
  final String id;

  /// 展示名，例如「上海青」。
  final String name;

  final RewardType type;

  /// 链条序号。普通/特殊奖励的 level 与升级链位置一致；苦瓜的 level 是基础等级（1）。
  final int level;

  /// 升级链上的位置，从 1 开始连续。
  final int order;

  /// 两个同类合成后的产物 ID；链条终点（苦瓜）为 null。
  final String? nextId;

  /// 是否永久（不受保质期影响）。
  final bool permanent;

  /// 保质期小时数；永久奖励为 null。
  final int? shelfLifeHours;

  /// 苦瓜专用：是否允许任意两个苦瓜按 n+m 合成。
  final bool bitterCombine;

  /// 图标资源路径（相对 assets）。
  final String icon;

  bool get isOrdinary => type == RewardType.ordinary;

  bool get isBitter => type == RewardType.bitter;

  /// 是否有下一级可合成。
  bool get canUpgrade => nextId != null;

  /// 从 JSON 解析；字段缺失或类型不对时抛 [ConfigException]。
  factory RewardDefinition.fromJson(Map<String, Object?> json) {
    final id = _requireString(json, 'id');
    return RewardDefinition(
      id: id,
      name: _requireString(json, 'name'),
      type: RewardType.parse(_requireString(json, 'type')),
      level: _requireInt(json, 'level'),
      order: _requireInt(json, 'order'),
      nextId: _optionalString(json, 'nextId'),
      permanent: _requireBool(json, 'permanent'),
      shelfLifeHours: _optionalInt(json, 'shelfLifeHours'),
      bitterCombine: _optionalBool(json, 'bitterCombine'),
      icon: _requireString(json, 'icon'),
    );
  }

  @override
  String toString() => 'RewardDefinition($id, order: $order, type: ${type.name})';

  static String _requireString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ConfigException('奖励定义 "$key" 缺失或不是非空字符串: $json');
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ConfigException('奖励定义 "$key" 必须是字符串或 null: $json');
  }

  static int _requireInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    throw ConfigException('奖励定义 "$key" 缺失或不是整数: $json');
  }

  static int? _optionalInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    throw ConfigException('奖励定义 "$key" 必须是整数或 null: $json');
  }

  static bool _requireBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    throw ConfigException('奖励定义 "$key" 缺失或不是布尔值: $json');
  }

  static bool _optionalBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    throw ConfigException('奖励定义 "$key" 必须是布尔值: $json');
  }
}
