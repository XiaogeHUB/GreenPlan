import 'config_exception.dart';

/// 称号规则，来自 `assets/config/titles.json`。
///
/// 规格 1.6：按历史最高苦瓜等级显示；1–10 级有固定名称，超过则用 fallback 模板。
class TitleRule {
  const TitleRule({required this.titles, required this.fallback});

  /// 等级 → 称号名称，键从 1 开始连续。
  final Map<int, String> titles;

  /// 超出配置范围时的模板，必须包含 `{n}` 占位符。
  final String fallback;

  /// 取某等级的称号；未配置的等级用 fallback 渲染。
  ///
  /// 等级 0 表示还没有任何苦瓜，由调用方决定显示什么（通常不显示称号）。
  String titleFor(int level) {
    final configured = titles[level];
    if (configured != null) {
      return configured;
    }
    return fallback.replaceAll('{n}', '$level');
  }

  factory TitleRule.fromJson(Map<String, Object?> json) {
    final rawTitles = json['titles'];
    if (rawTitles is! Map) {
      throw const ConfigException('titles.json 缺少 "titles" 对象');
    }
    final parsed = <int, String>{};
    for (final entry in rawTitles.entries) {
      final key = entry.key;
      final level = key is int ? key : int.tryParse('$key');
      if (level == null || level <= 0) {
        throw ConfigException('称号等级必须是正整数，实际为 "$key"');
      }
      final name = entry.value;
      if (name is! String || name.isEmpty) {
        throw ConfigException('等级 $level 的称号必须是非空字符串');
      }
      parsed[level] = name;
    }

    final fallback = json['fallback'];
    if (fallback is! String || fallback.isEmpty) {
      throw const ConfigException('titles.json 缺少 "fallback" 字符串');
    }

    return TitleRule(titles: Map.unmodifiable(parsed), fallback: fallback);
  }

  @override
  String toString() => 'TitleRule(${titles.length} 级, fallback: $fallback)';
}
