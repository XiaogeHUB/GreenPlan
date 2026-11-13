import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/config/app_config.dart';
import 'package:greenplan/data/db/app_database.dart';
import 'package:greenplan/data/db/dao/reward_item_dao.dart';
import 'package:greenplan/data/db/dao/settings_dao.dart';
import 'package:greenplan/data/db/dao/task_session_dao.dart';
import 'package:greenplan/data/db/dao/title_progress_dao.dart';
import 'package:greenplan/data/models/task_session.dart';
import 'package:greenplan/domain/services/backup_service.dart';

import '../support/test_fixtures.dart';

void main() {
  late AppDatabase db;
  late AppConfig config;
  late BackupService service;
  late TestClock clock;

  setUp(() async {
    db = await openTestDatabase();
    config = loadRealConfig();
    clock = TestClock(DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000));
    service = BackupService(db: db, config: config);
  });

  tearDown(() async {
    await db.close();
  });

  group('导出 → 导入 往返', () {
    test('奖励、任务记录、设置、称号都能原样恢复', () async {
      await placeItem(db, config, clock, definitionId: 'cong', slot: 0);
      await placeItem(db, config, clock, definitionId: 'dabaicai', slot: 5);
      await placeItem(db, config, clock, definitionId: 'kugua', slot: 7, level: 4);

      await TaskSessionDao(db.db).insert(
        TaskSession(
          id: 'session-1',
          durationMinutes: 30,
          rewardDefinitionId: 'xiangcai',
          startedAt: clock.now,
          expectedEndAt: clock.now.add(const Duration(minutes: 30)),
          endedAt: clock.now.add(const Duration(minutes: 30)),
          status: TaskStatus.success,
          createdAt: clock.now,
        ),
      );
      await SettingsDao(db.db).putBool(SettingsDao.expiryNotificationKey, false);
      await TitleProgressDao(db.db).setMaxLevel(4);

      final json = await service.export(now: clock.now);
      expect(json, contains('"schemaVersion": 1'));

      // 清空后恢复
      await RewardItemDao(db.db).deleteAll();
      await db.db.delete(TaskSessionDao.table);
      await TitleProgressDao(db.db).setMaxLevel(0);

      await service.restore(service.parse(json));

      final items = await RewardItemDao(db.db).getAll();
      expect(items, hasLength(3));
      expect(items.map((item) => item.definitionId), containsAll(<String>['cong', 'dabaicai', 'kugua']));
      expect(items.firstWhere((item) => item.definitionId == 'kugua').level, 4);

      final sessions = await TaskSessionDao(db.db).recent();
      expect(sessions, hasLength(1));
      expect(sessions.single.status, TaskStatus.success);

      expect(
        await SettingsDao(db.db).getBool(SettingsDao.expiryNotificationKey, fallback: true),
        isFalse,
      );
      expect(await TitleProgressDao(db.db).getMaxLevel(), 4);
    });
  });

  group('导入校验', () {
    test('非 JSON 文件被拒绝', () {
      expect(
        () => service.parse('not json at all'),
        throwsA(isA<BackupException>()),
      );
    });

    test('schemaVersion 高于当前版本被拒绝', () {
      expect(
        () => service.parse('{"schemaVersion": 99, "data": {}}'),
        throwsA(
          isA<BackupException>().having(
            (error) => error.message,
            'message',
            contains('高于当前支持'),
          ),
        ),
      );
    });

    test('未知奖励定义被拒绝', () {
      final payload = '''
{
  "schemaVersion": 1,
  "data": {
    "rewardItems": [
      {"id": "a", "definitionId": "unknown_veg", "slotIndex": 0, "createdAt": 1000}
    ]
  }
}
''';
      expect(
        () => service.parse(payload),
        throwsA(
          isA<BackupException>().having(
            (error) => error.issues.join(),
            'issues',
            contains('未知奖励'),
          ),
        ),
      );
    });

    test('格位重复被拒绝', () {
      final payload = '''
{
  "schemaVersion": 1,
  "data": {
    "rewardItems": [
      {"id": "a", "definitionId": "cong", "slotIndex": 0, "createdAt": 1000},
      {"id": "b", "definitionId": "cong", "slotIndex": 0, "createdAt": 1000}
    ]
  }
}
''';
      expect(
        () => service.parse(payload),
        throwsA(
          isA<BackupException>().having(
            (error) => error.issues.join(),
            'issues',
            contains('格位重复'),
          ),
        ),
      );
    });

    test('格位越界被拒绝', () {
      final payload = '''
{
  "schemaVersion": 1,
  "data": {
    "rewardItems": [
      {"id": "a", "definitionId": "cong", "slotIndex": 99, "createdAt": 1000}
    ]
  }
}
''';
      expect(() => service.parse(payload), throwsA(isA<BackupException>()));
    });
  });
}
