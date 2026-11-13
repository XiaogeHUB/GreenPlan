import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/data/db/app_database.dart';
import 'package:greenplan/data/db/dao/title_progress_dao.dart';
import 'package:greenplan/domain/services/title_service.dart';

import '../support/test_fixtures.dart';

void main() {
  late AppDatabase db;
  late TitleService service;

  setUp(() async {
    db = await openTestDatabase();
    service = TitleService(config: loadRealConfig(), db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('还没合成过苦瓜时没有称号', () async {
    expect(await service.currentLevel(), 0);
    expect(await service.currentTitle(), isNull);
  });

  test('按历史最高等级返回称号文案', () async {
    await TitleProgressDao(db.db).bumpMaxLevel(3);

    expect(await service.currentLevel(), 3);
    expect(await service.currentTitle(), '3级苦瓜大王');
  });

  test('超过配置范围时用 fallback 模板', () async {
    await TitleProgressDao(db.db).bumpMaxLevel(12);

    expect(await service.currentTitle(), '12级苦瓜大王');
  });
}
