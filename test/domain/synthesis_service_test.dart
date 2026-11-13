import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/config/app_config.dart';
import 'package:greenplan/data/db/app_database.dart';
import 'package:greenplan/data/db/dao/reward_item_dao.dart';
import 'package:greenplan/data/db/dao/title_progress_dao.dart';
import 'package:greenplan/domain/services/synthesis_service.dart';

import '../support/test_fixtures.dart';

void main() {
  late AppDatabase db;
  late AppConfig config;
  late TestClock clock;
  late SynthesisService service;

  setUp(() async {
    db = await openTestDatabase();
    config = loadRealConfig();
    clock = TestClock(DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000));
    service = SynthesisService(db: db, config: config, clock: clock.call);
  });

  tearDown(() async {
    await db.close();
  });

  group('普通合成', () {
    test('两个葱合成香菜，并刷新为 72 小时保质期', () async {
      final a = await placeItem(db, config, clock, definitionId: 'cong', slot: 0);
      final b = await placeItem(db, config, clock, definitionId: 'cong', slot: 1);

      clock.advance(const Duration(hours: 10));
      final result = await service.synthesize(
        idA: a.id,
        idB: b.id,
        targetSlot: 1,
      );

      expect(result.product.definitionId, 'xiangcai');
      expect(result.product.level, 1);
      expect(result.product.slotIndex, 1);
      expect(result.titleLevel, isNull);
      expect(
        result.product.expireAt,
        clock.now.add(const Duration(hours: 72)),
        reason: '合成产物必须从合成时刻重新计时，不是继承原物品',
      );

      final items = await RewardItemDao(db.db).getAll();
      expect(items, hasLength(1));
      expect(items.single.id, result.product.id);
    });

    test('两个大白菜合成芹菜，产物永久', () async {
      final a = await placeItem(db, config, clock, definitionId: 'dabaicai', slot: 3);
      final b = await placeItem(db, config, clock, definitionId: 'dabaicai', slot: 4);

      final result = await service.synthesize(
        idA: a.id,
        idB: b.id,
        targetSlot: 3,
      );

      expect(result.product.definitionId, 'qincai');
      expect(result.product.expireAt, isNull);
    });

    test('升级链可以一路合成到丝瓜', () async {
      var current = await placeItem(db, config, clock, definitionId: 'cong', slot: 0);
      var partner = await placeItem(db, config, clock, definitionId: 'cong', slot: 1);

      for (final expected in <String>[
        'xiangcai',
        'shanghaiqing',
        'xiaobaicai',
        'dabaicai',
        'qincai',
        'xilanhua',
        'wosun',
        'huanggua',
        'sigua',
      ]) {
        final result = await service.synthesize(
          idA: current.id,
          idB: partner.id,
          targetSlot: 0,
        );
        expect(result.product.definitionId, expected);
        current = result.product;
        partner = await placeItem(
          db,
          config,
          clock,
          definitionId: expected,
          slot: 1,
        );
      }

      expect(current.definitionId, 'sigua');
      expect(await RewardItemDao(db.db).getAll(), hasLength(2));
    });
  });

  group('苦瓜合成', () {
    test('两个丝瓜合成 1 级苦瓜并刷新称号', () async {
      final a = await placeItem(db, config, clock, definitionId: 'sigua', slot: 0);
      final b = await placeItem(db, config, clock, definitionId: 'sigua', slot: 1);

      final result = await service.synthesize(
        idA: a.id,
        idB: b.id,
        targetSlot: 0,
      );

      expect(result.product.definitionId, 'kugua');
      expect(result.product.level, 1);
      expect(result.product.expireAt, isNull);
      expect(result.titleLevel, 1);
      expect(await TitleProgressDao(db.db).getMaxLevel(), 1);
    });

    test('1 级苦瓜 + 2 级苦瓜 = 3 级苦瓜', () async {
      final one = await placeItem(
        db,
        config,
        clock,
        definitionId: 'kugua',
        slot: 0,
        level: 1,
      );
      final two = await placeItem(
        db,
        config,
        clock,
        definitionId: 'kugua',
        slot: 1,
        level: 2,
      );

      final result = await service.synthesize(
        idA: one.id,
        idB: two.id,
        targetSlot: 1,
      );

      expect(result.product.level, 3);
      expect(result.titleLevel, 3);
      expect(await TitleProgressDao(db.db).getMaxLevel(), 3);
    });

    test('称号只记历史最高，合成低级苦瓜不会降级', () async {
      await TitleProgressDao(db.db).bumpMaxLevel(5);
      final a = await placeItem(
        db, config, clock,
        definitionId: 'kugua',
        slot: 0,
        level: 1,
      );
      final b = await placeItem(
        db, config, clock,
        definitionId: 'kugua',
        slot: 1,
        level: 1,
      );

      final result = await service.synthesize(
        idA: a.id,
        idB: b.id,
        targetSlot: 0,
      );

      expect(result.product.level, 2);
      expect(result.titleLevel, 5);
      expect(await TitleProgressDao(db.db).getMaxLevel(), 5);
    });
  });

  group('不可合成的情况', () {
    test('过期物品不能合成', () async {
      final expired = await placeItem(
        db,
        config,
        clock,
        definitionId: 'cong',
        slot: 0,
        expireAt: clock.now,
      );
      final fresh = await placeItem(db, config, clock, definitionId: 'cong', slot: 1);

      await expectLater(
        service.synthesize(idA: expired.id, idB: fresh.id, targetSlot: 0),
        throwsA(isA<SynthesisException>()),
      );
      expect(await RewardItemDao(db.db).getAll(), hasLength(2));
    });

    test('不同奖励不能合成', () async {
      final a = await placeItem(db, config, clock, definitionId: 'cong', slot: 0);
      final b = await placeItem(db, config, clock, definitionId: 'xiangcai', slot: 1);

      expect(service.canSynthesize(a, b, clock.now), isFalse);
      await expectLater(
        service.synthesize(idA: a.id, idB: b.id, targetSlot: 0),
        throwsA(isA<SynthesisException>()),
      );
    });

    test('苦瓜不能和普通奖励合成', () async {
      final bitter = await placeItem(db, config, clock, definitionId: 'kugua', slot: 0);
      final cong = await placeItem(db, config, clock, definitionId: 'cong', slot: 1);

      expect(service.canSynthesize(bitter, cong, clock.now), isFalse);
    });

    test('产物格位必须是两个原材料之一', () async {
      final a = await placeItem(db, config, clock, definitionId: 'cong', slot: 0);
      final b = await placeItem(db, config, clock, definitionId: 'cong', slot: 1);

      await expectLater(
        service.synthesize(idA: a.id, idB: b.id, targetSlot: 5),
        throwsA(isA<SynthesisException>()),
      );
      expect(await RewardItemDao(db.db).getAll(), hasLength(2));
    });
  });
}
