import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/core/providers.dart';
import 'package:greenplan/data/models/reward_item.dart';
import 'package:greenplan/features/home/home_page.dart';
import 'package:greenplan/features/warehouse/warehouse_controller.dart';

import '../support/test_fixtures.dart';

/// 首页测试不碰数据库：直接给一个空仓库的假控制器。
///
/// 真实仓库要靠 sqflite 的 isolate，在 widget 测试的 fake-async 环境里会挂住，
/// 所以 UI 测试用假数据，数据逻辑由 `test/data` 和 `test/domain` 覆盖。
class _StaticWarehouse extends WarehouseController {
  _StaticWarehouse(this.items);

  final List<RewardItem> items;

  @override
  Future<List<RewardItem>> build() async => items;
}

void main() {
  testWidgets('首页展示称号位和五档时长', (tester) async {
    final config = loadRealConfig();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configProvider.overrideWithValue(config),
          warehouseProvider.overrideWith(() => _StaticWarehouse(const <RewardItem>[])),
          currentTitleProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('还没有称号'), findsOneWidget);
    expect(find.text('15 分钟 自律'), findsOneWidget);
    expect(find.text('30 分钟 自律'), findsOneWidget);
    expect(find.text('1 小时 自律'), findsOneWidget);
    expect(find.text('2 小时 自律'), findsOneWidget);
    expect(find.text('4 小时 自律'), findsOneWidget);
    expect(find.text('成功获得 葱'), findsOneWidget);
  });
}
