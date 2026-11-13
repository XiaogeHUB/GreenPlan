import 'config_exception.dart';
import 'duration_reward.dart';
import 'reward_definition.dart';
import 'title_rule.dart';

/// 三份配置合并、校验后的只读聚合根。
///
/// 通过 [AppConfig.build] 构造：要么得到一份内部一致的配置，要么抛
/// [ConfigException] 并附带全部问题。业务代码只依赖这个对象，不再自己读 JSON。
class AppConfig {
  AppConfig._({
    required this.rewards,
    required this.rewardsById,
    required this.durationRewards,
    required this.durationToRewardId,
    required this.titleRule,
  });

  /// 全部奖励定义，按 [RewardDefinition.order] 升序（即升级链顺序）。
  final List<RewardDefinition> rewards;

  /// 按 ID 索引的定义表。
  final Map<String, RewardDefinition> rewardsById;

  /// 时长映射，按分钟升序。
  final List<DurationReward> durationRewards;

  /// 分钟 → 奖励 ID。
  final Map<int, String> durationToRewardId;

  /// 称号规则。
  final TitleRule titleRule;

  /// 升级链终点的奖励（规格里是苦瓜）。
  RewardDefinition get finalReward => rewards.last;

  /// 升级链的起点奖励（规格里是葱）。
  RewardDefinition get firstReward => rewards.first;

  RewardDefinition? rewardById(String id) => rewardsById[id];

  /// 某个时长对应的可领取奖励；未配置的时长返回 null。
  RewardDefinition? rewardForMinutes(int minutes) {
    final id = durationToRewardId[minutes];
    return id == null ? null : rewardsById[id];
  }

  /// 按历史最高等级取称号。
  String titleFor(int level) => titleRule.titleFor(level);

  /// 构建并校验配置，把所有问题一次性收集后抛出。
  factory AppConfig.build({
    required List<RewardDefinition> rewards,
    required List<DurationReward> durationRewards,
    required TitleRule titleRule,
  }) {
    final issues = <String>[];

    _validateRewards(rewards, issues);
    _validateDurationRewards(durationRewards, rewards, issues);
    _validateTitles(titleRule, issues);

    if (issues.isNotEmpty) {
      throw ConfigException('配置校验失败（${issues.length} 项）', issues: issues);
    }

    final sortedRewards = List<RewardDefinition>.unmodifiable(
      <RewardDefinition>[...rewards]..sort((a, b) => a.order.compareTo(b.order)),
    );
    final sortedDurations = List<DurationReward>.unmodifiable(
      <DurationReward>[...durationRewards]
        ..sort((a, b) => a.minutes.compareTo(b.minutes)),
    );

    return AppConfig._(
      rewards: sortedRewards,
      rewardsById: Map<String, RewardDefinition>.unmodifiable(
        <String, RewardDefinition>{
          for (final reward in sortedRewards) reward.id: reward,
        },
      ),
      durationRewards: sortedDurations,
      durationToRewardId: Map<int, String>.unmodifiable(<int, String>{
        for (final duration in sortedDurations)
          duration.minutes: duration.rewardId,
      }),
      titleRule: titleRule,
    );
  }

  static void _validateRewards(
    List<RewardDefinition> rewards,
    List<String> issues,
  ) {
    if (rewards.isEmpty) {
      issues.add('rewards 为空，至少需要一个奖励定义');
      return;
    }

    final byId = <String, RewardDefinition>{};
    for (final reward in rewards) {
      if (byId.containsKey(reward.id)) {
        issues.add('奖励 id 重复: ${reward.id}');
      }
      byId[reward.id] = reward;
    }

    final orders = <int>{};
    for (final reward in rewards) {
      if (!orders.add(reward.order)) {
        issues.add('reward.order 重复: ${reward.order}（${reward.id}）');
      }
    }

    final sorted = <RewardDefinition>[...rewards]
      ..sort((a, b) => a.order.compareTo(b.order));
    for (var index = 0; index < sorted.length; index++) {
      final reward = sorted[index];
      if (reward.order != index + 1) {
        issues.add(
          'reward.order 必须从 1 连续递增，期望 ${index + 1}，'
          '实际 ${reward.order}（${reward.id}）',
        );
      }
    }

    for (final reward in sorted) {
      final nextId = reward.nextId;
      if (nextId == null) {
        continue;
      }
      if (nextId == reward.id) {
        issues.add('${reward.id}.nextId 不能指向自己');
        continue;
      }
      final next = byId[nextId];
      if (next == null) {
        issues.add('${reward.id}.nextId 指向不存在的奖励: $nextId');
        continue;
      }
      if (next.order != reward.order + 1) {
        issues.add(
          '${reward.id}.nextId 必须指向链上的下一级'
          '（order ${reward.order + 1}），实际是 ${next.id}（order ${next.order}）',
        );
      }
    }

    final terminals = sorted.where((reward) => !reward.canUpgrade).toList();
    if (terminals.length != 1) {
      issues.add(
        '升级链必须恰好有一个终点（nextId 为 null），'
        '实际有 ${terminals.length} 个: ${terminals.map((r) => r.id).join(', ')}',
      );
    } else if (!terminals.single.isBitter) {
      issues.add('升级链终点必须是苦瓜类型，实际是 ${terminals.single.id}');
    }

    for (final reward in sorted) {
      switch (reward.type) {
        case RewardType.ordinary:
          if (reward.permanent) {
            issues.add('普通奖励 ${reward.id} 不能标记为 permanent');
          }
          final shelfLife = reward.shelfLifeHours;
          if (shelfLife == null || shelfLife <= 0) {
            issues.add('普通奖励 ${reward.id} 必须有正的 shelfLifeHours');
          }
        case RewardType.special:
        case RewardType.bitter:
          if (!reward.permanent) {
            issues.add('${reward.id}（${reward.type.name}）必须标记为 permanent');
          }
          if (reward.shelfLifeHours != null) {
            issues.add('${reward.id}（${reward.type.name}）不应设置 shelfLifeHours');
          }
      }

      if (reward.isBitter) {
        if (reward.level != 1) {
          issues.add('苦瓜的基础等级必须是 1，实际是 ${reward.level}（${reward.id}）');
        }
        if (!reward.bitterCombine) {
          issues.add('苦瓜 ${reward.id} 必须开启 bitterCombine');
        }
      }
    }
  }

  static void _validateDurationRewards(
    List<DurationReward> durationRewards,
    List<RewardDefinition> rewards,
    List<String> issues,
  ) {
    if (durationRewards.isEmpty) {
      issues.add('duration_rewards 为空，至少需要一档时长');
      return;
    }

    final byId = <String, RewardDefinition>{
      for (final reward in rewards) reward.id: reward,
    };
    final minutes = <int>{};

    for (final duration in durationRewards) {
      if (!minutes.add(duration.minutes)) {
        issues.add('时长重复: ${duration.minutes} 分钟');
      }
      final reward = byId[duration.rewardId];
      if (reward == null) {
        issues.add(
          '时长 ${duration.minutes} 分钟映射到不存在的奖励: ${duration.rewardId}',
        );
        continue;
      }
      // 规格 1.1 / 4.4：任务奖励只发放普通奖励，芹菜及以上只能靠合成。
      if (!reward.isOrdinary) {
        issues.add(
          '时长 ${duration.minutes} 分钟映射到非普通奖励 ${reward.id}，'
          '任务奖励只能是普通奖励',
        );
      }
    }
  }

  static void _validateTitles(TitleRule titleRule, List<String> issues) {
    final levels = titleRule.titles.keys.toList()..sort();
    if (levels.isEmpty) {
      issues.add('称号表为空');
    }
    for (var index = 0; index < levels.length; index++) {
      if (levels[index] != index + 1) {
        issues.add(
          '称号等级必须从 1 连续递增，期望 ${index + 1}，实际 ${levels[index]}',
        );
      }
    }
    if (!titleRule.fallback.contains('{n}')) {
      issues.add('称号 fallback 必须包含 {n} 占位符: "${titleRule.fallback}"');
    }
  }

  @override
  String toString() =>
      'AppConfig(${rewards.length} 个奖励, ${durationRewards.length} 档时长, '
      '${titleRule.titles.length} 级称号)';
}
