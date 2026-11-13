import 'dart:convert';
import 'dart:io';

import 'package:greenplan/config/app_config.dart';
import 'package:greenplan/config/duration_reward.dart';
import 'package:greenplan/config/reward_definition.dart';
import 'package:greenplan/config/title_rule.dart';
import 'package:greenplan/data/db/app_database.dart';
import 'package:greenplan/data/db/dao/reward_item_dao.dart';
import 'package:greenplan/data/models/reward_item.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 用磁盘上的真实配置文件构建 [AppConfig]。
///
/// 领域层测试不塞假数据，直接跑 `assets/config/` 里那份，配置改了测试会跟着变。
AppConfig loadRealConfig() {
  final rewards = (jsonDecode(
    File('assets/config/rewards.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, Object?>>()
      .map(RewardDefinition.fromJson)
      .toList(growable: false);
  final durations = (jsonDecode(
    File('assets/config/duration_rewards.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, Object?>>()
      .map(DurationReward.fromJson)
      .toList(growable: false);
  final titles = TitleRule.fromJson(
    (jsonDecode(File('assets/config/titles.json').readAsStringSync()) as Map)
        .cast<String, Object?>(),
  );

  return AppConfig.build(
    rewards: rewards,
    durationRewards: durations,
    titleRule: titles,
  );
}

/// 内存数据库，每个测试互不干扰。
Future<AppDatabase> openTestDatabase() async {
  sqfliteFfiInit();
  return AppDatabase.open(factory: databaseFactoryFfi, path: ':memory:');
}

/// 可推进的测试时钟，避免测试真的等 15 分钟。
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

int _sequence = 0;

/// 往仓库放一个物品；普通奖励默认按配置的保质期设置过期时间。
Future<RewardItem> placeItem(
  AppDatabase db,
  AppConfig config,
  TestClock clock, {
  required String definitionId,
  required int slot,
  int level = 1,
  DateTime? expireAt,
}) async {
  final definition = config.rewardById(definitionId);
  if (definition == null) {
    throw ArgumentError('未知奖励: $definitionId');
  }
  final item = RewardItem(
    id: '${definitionId}_${slot}_${_sequence++}',
    definitionId: definitionId,
    level: level,
    slotIndex: slot,
    createdAt: clock.now,
    expireAt: expireAt ??
        (definition.permanent
            ? null
            : clock.now.add(Duration(hours: definition.shelfLifeHours!))),
  );
  await RewardItemDao(db.db).insert(item);
  return item;
}

/// 把仓库填满，跳过 [keepFree] 里的格位。
Future<void> fillWarehouse(
  AppDatabase db,
  AppConfig config,
  TestClock clock, {
  Set<int> keepFree = const <int>{},
}) async {
  final dao = RewardItemDao(db.db);
  for (var slot = 0; slot < AppDatabase.warehouseCapacity; slot++) {
    if (keepFree.contains(slot)) {
      continue;
    }
    if (await dao.getBySlot(slot) != null) {
      continue;
    }
    await placeItem(db, config, clock, definitionId: 'cong', slot: slot);
  }
}
