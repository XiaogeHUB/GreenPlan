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
