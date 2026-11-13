import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../data/db/app_database.dart';
import '../domain/services/synthesis_service.dart';
import '../domain/services/task_service.dart';
import '../domain/services/title_service.dart';
import 'native/native_monitor.dart';

/// 配置与数据库在 `main()` 里异步准备好后，通过 `ProviderScope.overrides` 注入。
///
/// 之所以不在 provider 里异步初始化：规格要求配置校验失败时走启动报错页，
/// 那需要一个「什么都还没准备好」的同步渲染路径。
final configProvider = Provider<AppConfig>(
  (ref) => throw StateError('configProvider 未注入，必须在 main() 中 override'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('databaseProvider 未注入，必须在 main() 中 override'),
);

/// 便于测试手动推进时间。
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 原生能力（息屏 / 焦点 / 分屏 / 电话）；测试可覆盖为空实现。
final nativeMonitorProvider = Provider<NativeMonitor>((ref) {
  return const NativeMonitor();
});

final taskServiceProvider = Provider<TaskService>((ref) {
  return TaskService(
    db: ref.watch(databaseProvider),
    config: ref.watch(configProvider),
    clock: ref.watch(clockProvider),
  );
});

final synthesisServiceProvider = Provider<SynthesisService>((ref) {
  return SynthesisService(
    db: ref.watch(databaseProvider),
    config: ref.watch(configProvider),
    clock: ref.watch(clockProvider),
  );
});

final titleServiceProvider = Provider<TitleService>((ref) {
  return TitleService(
    config: ref.watch(configProvider),
    db: ref.watch(databaseProvider),
  );
});

/// 当前称号；没有苦瓜时为 null。
final currentTitleProvider = FutureProvider<String?>((ref) {
  return ref.watch(titleServiceProvider).currentTitle();
});
