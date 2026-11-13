import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/config/app_config.dart';
import 'package:greenplan/config/config_exception.dart';
import 'package:greenplan/config/config_loader.dart';
import 'package:greenplan/config/duration_reward.dart';
import 'package:greenplan/config/reward_definition.dart';
import 'package:greenplan/config/title_rule.dart';

const String _rewardsPath = 'assets/config/rewards.json';
const String _durationsPath = 'assets/config/duration_rewards.json';
const String _titlesPath = 'assets/config/titles.json';

List<Map<String, Object?>> _readJsonList(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<Map<String, Object?>>();

Map<String, Object?> _readJsonMap(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map)
        .cast<String, Object?>();

/// 用磁盘上的真实配置文件构建 [AppConfig]，允许局部篡改以测试校验分支。
AppConfig _buildFromDisk({
  List<Map<String, Object?>>? rewardsJson,
  List<Map<String, Object?>>? durationsJson,
  Map<String, Object?>? titlesJson,
}) {
  final rewards = (rewardsJson ?? _readJsonList(_rewardsPath))
      .map(RewardDefinition.fromJson)
      .toList(growable: false);
  final durations = (durationsJson ?? _readJsonList(_durationsPath))
      .map(DurationReward.fromJson)
      .toList(growable: false);
  final titles = TitleRule.fromJson(titlesJson ?? _readJsonMap(_titlesPath));

  return AppConfig.build(
    rewards: rewards,
    durationRewards: durations,
    titleRule: titles,
  );
}

/// 断言 [action] 抛出的 [ConfigException] 里包含 [expectedIssue]。
void _expectConfigError(void Function() action, String expectedIssue) {
  try {
    action();
  } on ConfigException catch (error) {
    expect(error.issues.join('\n'), contains(expectedIssue));
    return;
  }
  fail('期望抛出 ConfigException，但没有抛');
}

/// 最小可用的内存 AssetBundle，用来测 [ConfigLoader] 的读取与错误分支。
class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final content = files[key];
    if (content == null) {
      throw FlutterError('missing asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  }
}

_FakeAssetBundle _realBundle() => _FakeAssetBundle(<String, String>{
      ConfigLoader.rewardsAsset: File(_rewardsPath).readAsStringSync(),
      ConfigLoader.durationRewardsAsset:
          File(_durationsPath).readAsStringSync(),
      ConfigLoader.titlesAsset: File(_titlesPath).readAsStringSync(),
    });

void main() {
  group('真实配置', () {
    test('三份配置能加载并通过校验', () {
      final config = _buildFromDisk();

      expect(config.rewards, hasLength(11));
      expect(config.firstReward.id, 'cong');
      expect(config.finalReward.id, 'kugua');
      expect(config.finalReward.isBitter, isTrue);
      expect(config.finalReward.canUpgrade, isFalse);

      for (var index = 0; index < config.rewards.length; index++) {
        expect(config.rewards[index].order, index + 1);
      }
    });

    test('升级链首尾相接，每级 nextId 指向下一级', () {
      final config = _buildFromDisk();
      for (final reward in config.rewards) {
        final nextId = reward.nextId;
        if (nextId == null) {
          continue;
        }
        final next = config.rewardById(nextId);
        expect(next, isNotNull, reason: '${reward.id}.nextId 指向 $nextId');
        expect(next!.order, reward.order + 1);
      }
    });

    test('时长映射齐全且只发普通奖励', () {
      final config = _buildFromDisk();

      expect(config.durationRewards, hasLength(5));
      expect(config.rewardForSeconds(1)?.id, 'cong');
      expect(config.rewardForMinutes(30)?.id, 'xiangcai');
      expect(config.rewardForMinutes(60)?.id, 'shanghaiqing');
      expect(config.rewardForMinutes(120)?.id, 'xiaobaicai');
      expect(config.rewardForMinutes(240)?.id, 'dabaicai');
      expect(config.rewardForMinutes(90), isNull);

      for (final duration in config.durationRewards) {
        expect(config.rewardById(duration.rewardId)!.isOrdinary, isTrue);
      }
    });

    test('称号按等级取，超范围走 fallback 模板', () {
      final config = _buildFromDisk();

      expect(config.titleFor(1), '1级苦瓜大王');
      expect(config.titleFor(10), '10级苦瓜大王');
      expect(config.titleFor(11), '11级苦瓜大王');
      expect(config.titleFor(999), '999级苦瓜大王');
    });
  });

  group('配置校验', () {
    test('nextId 指向不存在的奖励会被拦下', () {
      final rewards = _readJsonList(_rewardsPath);
      rewards.firstWhere((item) => item['id'] == 'sigua')['nextId'] =
          'not_exists';

      _expectConfigError(
        () => _buildFromDisk(rewardsJson: rewards),
        'nextId 指向不存在的奖励',
      );
    });

    test('奖励 id 重复会被拦下', () {
      final rewards = _readJsonList(_rewardsPath);
      rewards[0]['id'] = 'xiangcai';

      _expectConfigError(
        () => _buildFromDisk(rewardsJson: rewards),
        '奖励 id 重复',
      );
    });

    test('普通奖励不能标记为永久', () {
      final rewards = _readJsonList(_rewardsPath);
      rewards.firstWhere((item) => item['id'] == 'cong')['permanent'] = true;

      _expectConfigError(
        () => _buildFromDisk(rewardsJson: rewards),
        '不能标记为 permanent',
      );
    });

    test('时长映射到永久奖励会被拦下', () {
      final durations = _readJsonList(_durationsPath);
      durations[0]['rewardId'] = 'qincai';

      _expectConfigError(
        () => _buildFromDisk(durationsJson: durations),
        '任务奖励只能是普通奖励',
      );
    });

    test('称号 fallback 缺少 {n} 会被拦下', () {
      final titles = _readJsonMap(_titlesPath);
      titles['fallback'] = '苦瓜大王';

      _expectConfigError(
        () => _buildFromDisk(titlesJson: titles),
        '称号 fallback 必须包含 {n}',
      );
    });
  });

  group('ConfigLoader', () {
    test('通过 AssetBundle 读到与磁盘一致的配置', () async {
      final config = await ConfigLoader(bundle: _realBundle()).load();

      expect(config.rewards, hasLength(11));
      expect(config.rewardForMinutes(60)?.name, '上海青');
    });

    test('资产缺失时抛 ConfigException', () async {
      await expectLater(
        ConfigLoader(bundle: _FakeAssetBundle(<String, String>{})).load(),
        throwsA(isA<ConfigException>()),
      );
    });

    test('非法 JSON 抛 ConfigException', () async {
      final bundle = _FakeAssetBundle(<String, String>{
        ConfigLoader.rewardsAsset: '{ not json',
        ConfigLoader.durationRewardsAsset:
            File(_durationsPath).readAsStringSync(),
        ConfigLoader.titlesAsset: File(_titlesPath).readAsStringSync(),
      });

      await expectLater(
        ConfigLoader(bundle: bundle).load(),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.message,
            'message',
            contains('不是合法 JSON'),
          ),
        ),
      );
    });
  });
}
