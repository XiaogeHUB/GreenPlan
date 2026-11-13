import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/duration_reward.dart';
import '../../config/reward_definition.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/db/app_database.dart';
import '../../domain/services/task_service.dart';
import '../warehouse/warehouse_controller.dart';

/// 首页：当前称号 + 五档时长。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final title = ref.watch(currentTitleProvider);
    final warehouse = ref.watch(warehouseProvider);
    final occupied = warehouse.asData?.value.length ?? 0;
    final isFull = occupied >= AppDatabase.warehouseCapacity;

    return Scaffold(
      appBar: AppBar(title: const Text('自律')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          _TitleCard(title: title.asData?.value),
          const SizedBox(height: 20),
          if (isFull) ...<Widget>[
            const _WarehouseFullBanner(),
            const SizedBox(height: 12),
          ],
          Text(
            '选择自律时长',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final duration in config.durationRewards)
            _DurationCard(
              duration: duration,
              reward: config.rewardById(duration.rewardId)!,
              enabled: !isFull,
              onTap: () => _startTask(context, ref, duration),
            ),
          const SizedBox(height: 12),
          const Text(
            '开始后必须停留在任务页；切后台超过 10 秒会失败，来电与息屏不判失败。',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Future<void> _startTask(
    BuildContext context,
    WidgetRef ref,
    DurationReward duration,
  ) async {
    final config = ref.read(configProvider);
    final reward = config.rewardById(duration.rewardId)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('开始 ${duration.minutes} 分钟自律'),
        content: Text(
          '成功可获得「${reward.name}」。\n'
          '期间离开应用会判定失败，来电与息屏不会。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      final session = await ref
          .read(taskServiceProvider)
          .startTask(durationMinutes: duration.minutes);
      if (!context.mounted) {
        return;
      }
      await context.push<void>('/task', extra: session);
      if (!context.mounted) {
        return;
      }
      await ref.read(warehouseProvider.notifier).reload();
      ref.invalidate(currentTitleProvider);
    } on TaskException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _TitleCard extends StatelessWidget {
  const _TitleCard({required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('当前称号', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            title ?? '还没有称号',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            title == null ? '合成出第一颗苦瓜即可解锁' : '按历史最高等级记录，丢弃也不会降级',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _WarehouseFullBanner extends StatelessWidget {
  const _WarehouseFullBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: scheme.error, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '仓库已满，请先合成或删除奖励，再开始新任务。',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationCard extends StatelessWidget {
  const _DurationCard({
    required this.duration,
    required this.reward,
    required this.enabled,
    required this.onTap,
  });

  final DurationReward duration;
  final RewardDefinition reward;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        enabled: enabled,
        onTap: onTap,
        leading: RewardGlyph(reward, size: 42),
        title: Text(
          '${_formatMinutes(duration.minutes)} 自律',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('成功获得 ${reward.name}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  static String _formatMinutes(int minutes) {
    if (minutes < 60) {
      return '$minutes 分钟';
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
  }
}
