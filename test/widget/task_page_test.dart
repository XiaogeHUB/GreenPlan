import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/core/providers.dart';
import 'package:greenplan/data/models/task_session.dart';
import 'package:greenplan/features/task/task_page.dart';

import '../support/test_fixtures.dart';

void main() {
  testWidgets('任务页显示倒计时与奖励预览', (tester) async {
    final config = loadRealConfig();
    final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final session = TaskSession(
      id: 'session',
      durationMinutes: 15,
      rewardDefinitionId: 'cong',
      startedAt: now,
      expectedEndAt: now.add(const Duration(minutes: 15)),
      status: TaskStatus.running,
      createdAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configProvider.overrideWithValue(config),
          clockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(home: TaskPage(session: session)),
      ),
    );
    await tester.pump();

    expect(find.text('15:00'), findsOneWidget);
    expect(find.text('共 15 分钟'), findsOneWidget);
    expect(find.text('完成后获得「葱」'), findsOneWidget);

    // 卸载页面，避免 Timer 泄漏到其它测试。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
