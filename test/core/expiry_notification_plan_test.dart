import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/config/app_config.dart';
import 'package:greenplan/core/notifications/expiry_notification_plan.dart';
import 'package:greenplan/data/models/reward_item.dart';

import '../support/test_fixtures.dart';

RewardItem _item({
  required String id,
  required String definitionId,
  DateTime? expireAt,
  int level = 1,
}) {
  return RewardItem(
    id: id,
    definitionId: definitionId,
    level: level,
    slotIndex: 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    expireAt: expireAt,
  );
}

void main() {
  late AppConfig config;
  final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  setUp(() {
    config = loadRealConfig();
  });

  group('过期提醒计划', () {
    test('普通奖励在过期前 12 小时提醒一次', () {
      final expireAt = now.add(const Duration(days: 3));
      final plan = buildExpiryPlan(
        items: <RewardItem>[_item(id: 'a', definitionId: 'cong', expireAt: expireAt)],
        definitionOf: config.rewardById,
        now: now,
      );

      expect(plan, hasLength(1));
      expect(plan.single.scheduledAt, expireAt.subtract(const Duration(hours: 12)));
      expect(plan.single.title, '奖励即将过期');
      expect(plan.single.body, contains('葱'));
      expect(plan.single.body, contains('3 天'));
    });

    test('永久奖励不排提醒', () {
      final plan = buildExpiryPlan(
        items: <RewardItem>[
          _item(id: 'permanent', definitionId: 'qincai'),
          _item(id: 'bitter', definitionId: 'kugua', level: 3),
        ],
        definitionOf: config.rewardById,
        now: now,
      );

      expect(plan, isEmpty);
    });

    test('已过期物品不排提醒', () {
      final plan = buildExpiryPlan(
        items: <RewardItem>[
          _item(
            id: 'expired',
            definitionId: 'cong',
            expireAt: now.subtract(const Duration(minutes: 1)),
          ),
        ],
        definitionOf: config.rewardById,
        now: now,
      );

      expect(plan, isEmpty);
    });

    test('离过期不足 12 小时时，立即提醒', () {
      final expireAt = now.add(const Duration(hours: 2));
      final plan = buildExpiryPlan(
        items: <RewardItem>[_item(id: 'soon', definitionId: 'cong', expireAt: expireAt)],
        definitionOf: config.rewardById,
        now: now,
      );

      expect(plan, hasLength(1));
      expect(
        plan.single.scheduledAt,
        now.add(const Duration(seconds: 30)),
      );
    });

    test('苦瓜带等级时文案显示等级', () {
      final plan = buildExpiryPlan(
        items: <RewardItem>[
          _item(
            id: 'k',
            definitionId: 'kugua',
            level: 4,
            expireAt: now.add(const Duration(days: 1)),
          ),
        ],
        definitionOf: config.rewardById,
        now: now,
      );

      // 苦瓜是永久奖励，正常不会走到这里；此用例确保即使带 expireAt 文案也正确。
      expect(plan.single.body, contains('4 级苦瓜'));
    });

    test('按时间升序排列', () {
      final plan = buildExpiryPlan(
        items: <RewardItem>[
          _item(id: 'late', definitionId: 'cong', expireAt: now.add(const Duration(days: 3))),
          _item(id: 'early', definitionId: 'cong', expireAt: now.add(const Duration(days: 1))),
        ],
        definitionOf: config.rewardById,
        now: now,
      );

      expect(plan.first.scheduledAt.isBefore(plan.last.scheduledAt), isTrue);
    });
  });

  group('通知 ID', () {
    test('同一个物品 ID 每次都得到相同通知 ID', () {
      expect(notificationIdFor('abc-123'), notificationIdFor('abc-123'));
    });

    test('不同物品 ID 得到不同通知 ID，且为正数', () {
      final a = notificationIdFor('item-a');
      final b = notificationIdFor('item-b');

      expect(a, isNot(b));
      expect(a, greaterThan(0));
      expect(b, greaterThan(0));
    });
  });
}
