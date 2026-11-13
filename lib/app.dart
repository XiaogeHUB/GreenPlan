import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'data/models/task_session.dart';
import 'features/shell/app_shell.dart';
import 'features/task/task_page.dart';

/// 应用根组件。配置与数据库已在 `main()` 中注入。
class GreenPlanApp extends StatelessWidget {
  const GreenPlanApp({super.key});

  static final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const AppShell(),
      ),
      GoRoute(
        path: '/task',
        builder: (context, state) {
          final session = state.extra;
          if (session is! TaskSession) {
            return const _MissingSessionPage();
          }
          return TaskPage(session: session);
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GreenPlan',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}

/// 直接访问 `/task` 却没有会话时的兜底页。
class _MissingSessionPage extends StatelessWidget {
  const _MissingSessionPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任务')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('没有正在进行中的任务'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('回到首页'),
            ),
          ],
        ),
      ),
    );
  }
}
