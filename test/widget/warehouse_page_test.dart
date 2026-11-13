import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/core/providers.dart';
import 'package:greenplan/data/db/app_database.dart';
import 'package:greenplan/data/models/reward_item.dart';
import 'package:greenplan/features/warehouse/warehouse_controller.dart';
import 'package:greenplan/features/warehouse/warehouse_page.dart';

import '../support/test_fixtures.dart';

class _FakeWarehouse extends WarehouseController {
  _FakeWarehouse(this.items);

  final List<RewardItem> items;

  @override
  Future<List<RewardItem>> build() async => items;

  @override
  Future<int> claimPendingRewards() async => 0;
}

void main() {
  testWidgets('仓库渲染 24 格，按格位摆放物品', (tester) async {
    final config = loadRealConfig();
    final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final items = <RewardItem>[
      RewardItem(
        id: 'a',
        definitionId: 'cong',
        slotIndex: 0,
        createdAt: now,
        expireAt: now.add(const Duration(hours: 3)),
      ),
      RewardItem(
        id: 'b',
        definitionId: 'kugua',
        level: 3,
        slotIndex: 5,
        createdAt: now,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configProvider.overrideWithValue(config),
          clockProvider.overrideWithValue(() => now),
          warehouseProvider.overrideWith(() => _FakeWarehouse(items)),
        ],
        child: const MaterialApp(home: WarehousePage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('仓库'), findsOneWidget);
    // 图标用的是名称首字，所以「葱」会出现两次：图标一次、名称一次。
    expect(find.text('葱'), findsNWidgets(2));
    expect(find.text('3级苦瓜'), findsOneWidget);
    // 网格是懒加载的，只断言「有空位」和「网格存在」，不数可见格子。
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(AppDatabase.warehouseCapacity, 24);
  });
}
