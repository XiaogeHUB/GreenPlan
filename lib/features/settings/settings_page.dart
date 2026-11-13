import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/dao/settings_dao.dart';
import '../../data/models/reward_item.dart';
import '../warehouse/warehouse_controller.dart';

/// 过期提醒开关的持久化状态。
final expiryNotificationProvider = FutureProvider<bool>((ref) async {
  final dao = SettingsDao(ref.watch(databaseProvider).db);
  return dao.getBool(SettingsDao.expiryNotificationKey, fallback: true);
});

/// 电话状态权限是否已授予（决定来电是否豁免）。
final phonePermissionProvider = FutureProvider<bool>((ref) {
  return ref.watch(nativeMonitorProvider).isPhonePermissionGranted();
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notification = ref.watch(expiryNotificationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: <Widget>[
          SwitchListTile(
            title: const Text('过期提醒'),
            subtitle: const Text('普通奖励过期前 12 小时提醒一次'),
            value: notification.asData?.value ?? true,
            onChanged: (value) async {
              final dao = SettingsDao(ref.read(databaseProvider).db);
              await dao.putBool(SettingsDao.expiryNotificationKey, value);
              ref.invalidate(expiryNotificationProvider);

              final items =
                  ref.read(warehouseProvider).asData?.value ??
                      const <RewardItem>[];
              await ref.read(notificationServiceProvider).sync(
                    items: items,
                    config: ref.read(configProvider),
                    enabled: value,
                  );
            },
          ),
          const Divider(height: 1),
          _PhonePermissionTile(permission: ref.watch(phonePermissionProvider)),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清空仓库'),
            subtitle: const Text('删除所有奖励，用于测试或重新开始'),
            onTap: () => _clearWarehouse(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('GreenPlan 1.0.0'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'GreenPlan',
              applicationVersion: '1.0.0',
              applicationLegalese: '自律养成 · 本地单机 · 数据不上云',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearWarehouse(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空仓库？'),
        content: const Text('所有奖励都会被删除，且无法恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(warehouseProvider.notifier).clearAll();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('仓库已清空')));
  }
}

/// 来电豁免（电话状态权限）状态与开启入口。
///
/// 未授权时任务仍然可用，只是来电会被当成普通失焦（60 秒宽限），
/// 所以这里必须显式提示，而不是静默降级。
class _PhonePermissionTile extends ConsumerWidget {
  const _PhonePermissionTile({required this.permission});

  final AsyncValue<bool> permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = permission.asData?.value;
    final subtitle = switch (granted) {
      true => '已开启，通话中不会判定任务失败',
      false => '未开启，来电可能被判定为离开应用',
      null => '正在检查权限…',
    };

    return ListTile(
      leading: Icon(
        granted == true ? Icons.phone_enabled : Icons.phone_disabled,
        color: granted == true ? Colors.green : Colors.orange,
      ),
      title: const Text('来电豁免'),
      subtitle: Text(subtitle),
      trailing: granted == false
          ? TextButton(
              onPressed: () async {
                final monitor = ref.read(nativeMonitorProvider);
                await monitor.requestPhonePermission();
                if (!await monitor.isPhonePermissionGranted()) {
                  // 二次拒绝后系统不再弹窗，引导去应用设置
                  await monitor.openAppSettings();
                }
                ref.invalidate(phonePermissionProvider);
              },
              child: const Text('去开启'),
            )
          : null,
      onTap: granted == false
          ? () => ref.invalidate(phonePermissionProvider)
          : null,
    );
  }
}
