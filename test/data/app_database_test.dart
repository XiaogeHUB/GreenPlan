import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/data/db/app_database.dart';
import 'package:greenplan/data/db/dao/reward_item_dao.dart';
import 'package:greenplan/data/db/dao/settings_dao.dart';
import 'package:greenplan/data/db/dao/task_session_dao.dart';
import 'package:greenplan/data/db/dao/title_progress_dao.dart';
import 'package:greenplan/data/models/reward_item.dart';
import 'package:greenplan/data/models/task_session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

RewardItem _item({
  required String id,
  required int slot,
  String definitionId = 'cong',
  int level = 1,
  DateTime? expireAt,
}) {
  return RewardItem(
    id: id,
    definitionId: definitionId,
    level: level,
    slotIndex: slot,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    expireAt: expireAt,
  );
}

TaskSession _session({
  required String id,
  required TaskStatus status,
  DateTime? startedAt,
  DateTime? expectedEndAt,
}) {
  final start = startedAt ?? DateTime.fromMillisecondsSinceEpoch(1000);
  return TaskSession(
    id: id,
    durationMinutes: 15,
    rewardDefinitionId: 'cong',
    startedAt: start,
    expectedEndAt:
        expectedEndAt ?? start.add(const Duration(minutes: 15)),
    status: status,
    createdAt: start,
  );
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late AppDatabase database;

  setUp(() async {
    database = await AppDatabase.open(
      factory: factory,
      path: ':memory:',
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('建表', () {
    test('默认设置与称号进度已写入', () async {
      final settings = SettingsDao(database.db);
      expect(await settings.getBool(SettingsDao.expiryNotificationKey, fallback: false), isTrue);
      expect(await settings.getBool(SettingsDao.onboardingShownKey, fallback: true), isFalse);

      expect(await TitleProgressDao(database.db).getMaxLevel(), 0);
    });
  });

  group('RewardItemDao', () {
    test('写入后能按格位读回', () async {
      final dao = RewardItemDao(database.db);
      final item = _item(id: 'a', slot: 3, expireAt: DateTime.fromMillisecondsSinceEpoch(5000));

      await dao.insert(item);
      final loaded = await dao.getBySlot(3);

      expect(loaded, isNotNull);
      expect(loaded!.id, 'a');
      expect(loaded.slotIndex, 3);
      expect(loaded.expireAt!.millisecondsSinceEpoch, 5000);
      expect(loaded.level, 1);
    });

    test('同一格位插入第二个物品会被唯一索引拦下', () async {
      final dao = RewardItemDao(database.db);
      await dao.insert(_item(id: 'a', slot: 0));

      await expectLater(
        dao.insert(_item(id: 'b', slot: 0)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('firstFreeSlot 跳过已占用格位，满仓返回 null', () async {
      final dao = RewardItemDao(database.db);
      await dao.insert(_item(id: 'a', slot: 0));
      await dao.insert(_item(id: 'b', slot: 1));
      await dao.insert(_item(id: 'c', slot: 3));

      expect(await dao.firstFreeSlot(), 2);
      expect(await dao.hasFreeSlot(), isTrue);

      for (var slot = 0; slot < AppDatabase.warehouseCapacity; slot++) {
        if (await dao.getBySlot(slot) != null) {
          continue;
        }
        await dao.insert(_item(id: 'fill$slot', slot: slot));
      }
      expect(await dao.firstFreeSlot(), isNull);
      expect(await dao.hasFreeSlot(), isFalse);
    });

    test('swapSlots 交换格位且不触发唯一索引冲突', () async {
      final dao = RewardItemDao(database.db);
      await dao.insert(_item(id: 'a', slot: 0));
      await dao.insert(_item(id: 'b', slot: 5));

      await dao.swapSlots(idA: 'a', idB: 'b');

      expect((await dao.getById('a'))!.slotIndex, 5);
      expect((await dao.getById('b'))!.slotIndex, 0);
    });

    test('过期边界：expire_at == now 即算过期', () async {
      final dao = RewardItemDao(database.db);
      final now = DateTime.fromMillisecondsSinceEpoch(10_000);
      await dao.insert(_item(id: 'edge', slot: 0, expireAt: now));
      await dao.insert(_item(id: 'future', slot: 1, expireAt: now.add(const Duration(milliseconds: 1))));
      await dao.insert(_item(id: 'forever', slot: 2));

      final expired = await dao.expiredAt(now);

      expect(expired.map((item) => item.id), <String>['edge']);
      expect(await dao.getById('edge').then((item) => item!.isExpiredAt(now)), isTrue);
      expect(await dao.getById('future').then((item) => item!.isExpiredAt(now)), isFalse);
    });

    test('deleteExpiredAt 只删过期物品', () async {
      final dao = RewardItemDao(database.db);
      final now = DateTime.fromMillisecondsSinceEpoch(10_000);
      await dao.insert(_item(id: 'old', slot: 0, expireAt: now.subtract(const Duration(seconds: 1))));
      await dao.insert(_item(id: 'alive', slot: 1, expireAt: now.add(const Duration(days: 1))));
      await dao.insert(_item(id: 'forever', slot: 2));

      expect(await dao.deleteExpiredAt(now), 1);
      expect((await dao.getAll()).map((item) => item.id), <String>['alive', 'forever']);
    });

    test('事务抛异常时整体回滚', () async {
      final dao = RewardItemDao(database.db);
      await dao.insert(_item(id: 'keep', slot: 0));

      await expectLater(
        database.transaction((txn) async {
          final txnDao = RewardItemDao(txn);
          await txnDao.insert(_item(id: 'rollback', slot: 1));
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      expect((await dao.getAll()).map((item) => item.id), <String>['keep']);
    });
  });

  group('TaskSessionDao', () {
    test('running 任务可查，冷启动批量判失败', () async {
      final dao = TaskSessionDao(database.db);
      await dao.insert(_session(id: 's1', status: TaskStatus.running));
      await dao.insert(_session(id: 's2', status: TaskStatus.running));
      await dao.insert(_session(id: 's3', status: TaskStatus.success));

      expect((await dao.findRunning())?.id, isNotNull);

      final affected = await dao.failAllRunning(
        reason: 'process_death',
        endedAt: DateTime.fromMillisecondsSinceEpoch(20_000),
      );

      expect(affected, 2);
      expect(await dao.findRunning(), isNull);

      final failed = await dao.findByStatus(TaskStatus.failed);
      expect(failed, hasLength(2));
      expect(failed.every((session) => session.failureReason == 'process_death'), isTrue);
    });

    test('状态落库后能原样读回（含 snake_case 线格式）', () async {
      final dao = TaskSessionDao(database.db);
      final session = _session(
        id: 'pending',
        status: TaskStatus.successPendingReward,
      );
      await dao.insert(session);

      expect((await dao.getById('pending'))!.status, TaskStatus.successPendingReward);
      expect(
        (await dao.getById('pending'))!.status.wireName,
        'success_pending_reward',
      );
    });
  });

  group('TitleProgressDao', () {
    test('历史最高等级只增不减', () async {
      final dao = TitleProgressDao(database.db);

      expect(await dao.bumpMaxLevel(3), 3);
      expect(await dao.bumpMaxLevel(1), 3);
      expect(await dao.bumpMaxLevel(7), 7);
      expect(await dao.getMaxLevel(), 7);
    });
  });

  group('SettingsDao', () {
    test('布尔值按 true/false 字符串存取', () async {
      final dao = SettingsDao(database.db);

      await dao.putBool(SettingsDao.expiryNotificationKey, false);
      expect(await dao.get(SettingsDao.expiryNotificationKey), 'false');
      expect(await dao.getBool(SettingsDao.expiryNotificationKey, fallback: true), isFalse);

      await dao.putAll(<String, String>{
        SettingsDao.expiryNotificationKey: 'true',
        SettingsDao.onboardingShownKey: 'true',
      });
      expect(await dao.getBool(SettingsDao.expiryNotificationKey), isTrue);
      expect((await dao.getAll()).length, greaterThanOrEqualTo(2));
    });
  });
}
