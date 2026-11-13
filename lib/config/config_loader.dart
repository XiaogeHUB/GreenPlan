import 'dart:convert';

import 'package:flutter/services.dart';

import 'app_config.dart';
import 'config_exception.dart';
import 'duration_reward.dart';
import 'reward_definition.dart';
import 'title_rule.dart';

/// 从 `assets/config/` 读取三份 JSON 并合并成校验过的 [AppConfig]。
///
/// 默认用 [rootBundle]；测试里可以注入自定义 [AssetBundle]。
class ConfigLoader {
  const ConfigLoader({this.bundle});

  /// 配置来源；默认使用 [rootBundle]，测试可注入内存实现。
  final AssetBundle? bundle;

  static const String rewardsAsset = 'assets/config/rewards.json';
  static const String durationRewardsAsset = 'assets/config/duration_rewards.json';
  static const String titlesAsset = 'assets/config/titles.json';

  /// 加载并校验；任何失败都以 [ConfigException] 抛出。
  Future<AppConfig> load() async {
    final assets = bundle ?? rootBundle;

    final rewards = (await _readObjectList(assets, rewardsAsset))
        .map(RewardDefinition.fromJson)
        .toList(growable: false);
    final durations = (await _readObjectList(assets, durationRewardsAsset))
        .map(DurationReward.fromJson)
        .toList(growable: false);
    final titles = TitleRule.fromJson(
      await _readObject(assets, titlesAsset),
    );

    return AppConfig.build(
      rewards: rewards,
      durationRewards: durations,
      titleRule: titles,
    );
  }

  Future<List<Map<String, Object?>>> _readObjectList(
    AssetBundle bundle,
    String path,
  ) async {
    final decoded = _decode(await _readString(bundle, path), path);
    if (decoded is! List) {
      throw ConfigException('$path 顶层必须是 JSON 数组');
    }
    final result = <Map<String, Object?>>[];
    for (var index = 0; index < decoded.length; index++) {
      final item = decoded[index];
      if (item is! Map) {
        throw ConfigException('$path 的第 $index 项必须是 JSON 对象');
      }
      result.add(item.cast<String, Object?>());
    }
    return result;
  }

  Future<Map<String, Object?>> _readObject(
    AssetBundle bundle,
    String path,
  ) async {
    final decoded = _decode(await _readString(bundle, path), path);
    if (decoded is! Map) {
      throw ConfigException('$path 顶层必须是 JSON 对象');
    }
    return decoded.cast<String, Object?>();
  }

  Future<String> _readString(AssetBundle bundle, String path) async {
    try {
      return await bundle.loadString(path);
    } catch (error) {
      throw ConfigException('无法读取配置文件 $path', issues: <String>['$error']);
    }
  }

  Object? _decode(String raw, String path) {
    try {
      return jsonDecode(raw);
    } on FormatException catch (error) {
      throw ConfigException('$path 不是合法 JSON', issues: <String>[error.message]);
    }
  }
}
