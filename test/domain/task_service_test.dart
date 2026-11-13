import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/config/app_config.dart';
import 'package:greenplan/data/db/app_database.dart';
import 'package:greenplan/data/db/dao/reward_item_dao.dart';
import 'package:greenplan/data/db/dao/task_session_dao.dart';
import 'package:greenplan/data/models/task_session.dart';
import 'package:greenplan/domain/services/task_service.dart';

import '../support/test_fixtures.dart';

void main() {
  late AppDatabase db;
  late AppConfig config;
  late TestClock clock;
  late TaskService service;

  setUp(() async {
    db = await openTestDatabase();
    config = loadRealConfig();
    clock = TestClock(DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000));
    service = TaskService(db: db, config: config, clock: clock.call);
  });

  tearDown(() async {
    await db.close();
  });

  group('开始任务', () {
    test('写入 running 会话，奖励按配置映射', () async {
      final session = await service.startTask(durationMinutes: 60);

      expect(session.status, TaskStatus.running);
      expect(session.rewardDefinitionId, 'shanghaiqing');
      expect(session.startedAt, clock.now);
      expect(session.expectedEndAt, clock.now.add(const Duration(minutes: 60)));
      expect((await service.findRunning())?.id, session.id);
    });

    test('已有进行中任务时拒绝再开', () async {
      await service.startTask(durationMinutes: 15);

      await expectLater(
        service.startTask(durationMinutes: 30),
        throwsA(isA<TaskException>()),
      );
    });

    test('仓库已满时拒绝开始', () async {
      await fillWarehouse(db, config, clock);

      await expectLater(
        service.startTask(durationMinutes: 15),
        throwsA(isA<TaskException>()),
      );
      expect(await service.findRunning(), isNull);
    });

    test('未配置的时长被拒绝', () async {
      await expectLater(
        service.startTask(durationMinutes: 45),
        throwsA(isA<TaskException>()),
      );
    });
  });

  group('完成任务', () {
    test('到点完成任务，发葱并设置 72 小时过期', () async {
      final session = await service.startTask(durationMinutes: 15);
      clock.advance(const Duration(minutes: 15));

      final done = await service.completeTask(session.id);

      expect(done.status, TaskStatus.success);
      expect(done.endedAt, clock.now);
      expect(await service.findRunning(), isNull);

      final items = await RewardItemDao(db.db).getAll();
      expect(items, hasLength(1));
      expect(items.single.definitionId, 'cong');
      expect(items.single.slotIndex, 0);
      expect(items.single.sourceTaskId, session.id);
      expect(
        items.single.expireAt,
        clock.now.add(const Duration(hours: 72)),
      );
    });

    test('没到点不能完成', () async {
      final session = await service.startTask(durationMinutes: 15);
      clock.advance(const Duration(minutes: 14));

      await expectLater(
        service.completeTask(session.id),
        throwsA(isA<TaskException>()),
      );
      expect(await service.findRunning(), isNotNull);
    });

    test('完成时仓库满：不丢奖励，转为待领取并在清理后可领取', () async {
      final session = await service.startTask(durationMinutes: 15);
      await fillWarehouse(db, config, clock);
      clock.advance(const Duration(minutes: 15));

      final pending = await service.completeTask(session.id);

      expect(pending.status, TaskStatus.successPendingReward);
      expect(pending.pendingRewardDefinitionId, 'cong');
      expect(await RewardItemDao(db.db).getAll(), hasLength(24));

      final itemDao = RewardItemDao(db.db);
      await itemDao.deleteById((await itemDao.getBySlot(0))!.id);

      final claimed = await service.claimPendingReward(session.id);

      expect(claimed.status, TaskStatus.success);
      final items = await itemDao.getAll();
      expect(items, hasLength(24));
      expect(
        items.where((item) => item.sourceTaskId == session.id),
        hasLength(1),
        reason: '领取后应有一个来源为本次任务的奖励',
      );
    });

    test('待领取状态下仓库仍满时领取失败', () async {
      final session = await service.startTask(durationMinutes: 15);
      await fillWarehouse(db, config, clock);
      clock.advance(const Duration(minutes: 15));
      await service.completeTask(session.id);

      await expectLater(
        service.claimPendingReward(session.id),
        throwsA(isA<TaskException>()),
      );
    });
  });

  group('失败与放弃', () {
    test('失败不发奖励，且可立即重开', () async {
      final session = await service.startTask(durationMinutes: 60);

      final failed = await service.failTask(
        session.id,
        reason: 'background_timeout',
      );

      expect(failed.status, TaskStatus.failed);
      expect(failed.failureReason, 'background_timeout');
      expect(await RewardItemDao(db.db).getAll(), isEmpty);
      expect(await service.findRunning(), isNull);

      final retry = await service.startTask(durationMinutes: 15);
      expect(retry.status, TaskStatus.running);
    });

    test('放弃任务无奖励', () async {
      final session = await service.startTask(durationMinutes: 15);

      final abandoned = await service.abandonTask(session.id);

      expect(abandoned.status, TaskStatus.abandoned);
      expect(await RewardItemDao(db.db).getAll(), isEmpty);
    });

    test('已完成的任务不能再判失败', () async {
      final session = await service.startTask(durationMinutes: 15);
      clock.advance(const Duration(minutes: 15));
      await service.completeTask(session.id);

      await expectLater(
        service.failTask(session.id, reason: 'late'),
        throwsA(isA<TaskException>()),
      );
    });
  });

  group('冷启动恢复', () {
    test('running 任务全部判为进程被杀', () async {
      final session = await service.startTask(durationMinutes: 240);
      clock.advance(const Duration(minutes: 5));

      final affected = await service.recoverRunningAfterColdStart();

      expect(affected, 1);
      expect(await service.findRunning(), isNull);
      expect(await RewardItemDao(db.db).getAll(), isEmpty);

      final sessions =
          await TaskSessionDao(db.db).findByStatus(TaskStatus.failed);
      expect(sessions.single.id, session.id);
      expect(sessions.single.failureReason, TaskService.reasonProcessDeath);
    });
  });
}
