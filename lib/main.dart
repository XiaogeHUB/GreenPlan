import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/config_exception.dart';
import 'config/config_loader.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'domain/services/task_service.dart';
import 'features/error/bootstrap_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final config = await const ConfigLoader().load();
    final database = await AppDatabase.open();

    // 冷启动：上次没正常结束的任务一律判为「应用被系统关闭」（规格 4.6）。
    await TaskService(db: database, config: config)
        .recoverRunningAfterColdStart();

    runApp(
      ProviderScope(
        overrides: [
          configProvider.overrideWithValue(config),
          databaseProvider.overrideWithValue(database),
        ],
        child: const GreenPlanApp(),
      ),
    );
  } on ConfigException catch (error) {
    runApp(
      BootstrapErrorApp(
        title: '配置校验失败',
        details: describeConfigException(error),
      ),
    );
  } catch (error, stackTrace) {
    runApp(
      BootstrapErrorApp(
        title: '启动失败',
        details: '$error\n\n$stackTrace',
      ),
    );
  }
}
