import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../config/app_config.dart';
import '../../data/models/reward_item.dart';
import 'expiry_notification_plan.dart';

/// 过期提醒的落地实现。
///
/// 策略：每次仓库变化后 `cancelAll()` 再按当前计划重排，最多 24 条，简单且幂等，
/// 不会出现「删了物品通知还留着」这类状态漂移。
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'expiry_reminder',
    '过期提醒',
    channelDescription: '普通奖励快过期时提醒合成',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const NotificationDetails _details =
      NotificationDetails(android: _androidDetails);

  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }
    tz_data.initializeTimeZones();
    final ok = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = ok ?? false;
    return _initialized;
  }

  /// Android 13+ 需要运行时授权；低版本直接返回 true。
  Future<bool> ensurePermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      return true;
    }
    final granted = await android.requestNotificationsPermission();
    return granted ?? true;
  }

  /// 按当前仓库重排提醒；[enabled] 为 false 时全部取消。
  Future<void> sync({
    required List<RewardItem> items,
    required AppConfig config,
    required bool enabled,
    DateTime? now,
  }) async {
    if (!await initialize()) {
      return;
    }
    await _plugin.cancelAll();
    if (!enabled) {
      return;
    }

    final current = now ?? DateTime.now();
    final plan = buildExpiryPlan(
      items: items,
      definitionOf: config.rewardById,
      now: current,
    );

    final base = tz.TZDateTime.now(tz.UTC);
    for (final entry in plan) {
      final delay = entry.scheduledAt.difference(current);
      final scheduledDate = delay.isNegative ? base : base.add(delay);
      await _plugin.zonedSchedule(
        id: entry.id,
        title: entry.title,
        body: entry.body,
        scheduledDate: scheduledDate,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelAll() async {
    if (!await initialize()) {
      return;
    }
    await _plugin.cancelAll();
  }
}
