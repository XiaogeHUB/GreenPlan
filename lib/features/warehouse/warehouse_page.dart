import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../config/reward_definition.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../data/db/app_database.dart';
import '../../data/models/reward_item.dart';
import 'warehouse_controller.dart';

/// 仓库页：4 列 × 6 行，共 24 格。
///
/// 交互：
/// - 点一件选中，再点另一件尝试合成；
/// - 选中后点空格，移动到该格；
/// - 长按看详情、删除。
class WarehousePage extends ConsumerStatefulWidget {
  const WarehousePage({super.key});

  @override
  ConsumerState<WarehousePage> createState() => _WarehousePageState();
}

class _WarehousePageState extends ConsumerState<WarehousePage> {
  String? _selectedId;
  bool _claimScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimPending());
  }

  Future<void> _claimPending() async {
    if (_claimScheduled || !mounted) {
      return;
    }
    _claimScheduled = true;
    final claimed =
        await ref.read(warehouseProvider.notifier).claimPendingRewards();
    if (claimed > 0 && mounted) {
      _toast('已补发 $claimed 个奖励');
    }
  }

  RewardItem? _findSelected(List<RewardItem> items) {
    for (final item in items) {
      if (item.id == _selectedId) {
        return item;
      }
    }
    return null;
  }

  RewardItem? _itemAtSlot(List<RewardItem> items, int slot) {
    for (final item in items) {
      if (item.slotIndex == slot) {
        return item;
      }
    }
    return null;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onTapSlot(int slot, List<RewardItem> items) async {
    final now = ref.read(clockProvider)();
    final tapped = _itemAtSlot(items, slot);
    final selected = _findSelected(items);

    if (selected == null) {
      if (tapped != null) {
        setState(() => _selectedId = tapped.id);
      }
      return;
    }

    if (tapped == null) {
      final error =
          await ref.read(warehouseProvider.notifier).moveTo(selected, slot);
      if (!mounted) {
        return;
      }
      setState(() => _selectedId = null);
      if (error != null) {
        _toast(error);
      }
      return;
    }

    if (tapped.id == selected.id) {
      setState(() => _selectedId = null);
      return;
    }

    final config = ref.read(configProvider);
    final defA = config.rewardById(selected.definitionId);
    final defB = config.rewardById(tapped.definitionId);

    if (defA != null &&
        defB != null &&
        defA.isBitter &&
        defB.isBitter &&
        !selected.isExpiredAt(now) &&
        !tapped.isExpiredAt(now)) {
      final confirmed = await _confirmBitter(selected, tapped);
      if (confirmed != true || !mounted) {
        return;
      }
    }

    final error = await ref.read(warehouseProvider.notifier).synthesize(
          a: selected,
          b: tapped,
        );
    if (!mounted) {
      return;
    }
    if (error == null) {
      setState(() => _selectedId = null);
      _toast('合成成功');
    } else {
      setState(() => _selectedId = tapped.id);
      _toast(error);
    }
  }

  Future<bool?> _confirmBitter(RewardItem a, RewardItem b) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('合成苦瓜'),
        content: Text('${a.level} 级 + ${b.level} 级 = ${a.level + b.level} 级苦瓜？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('合成'),
          ),
        ],
      ),
    );
  }

  Future<void> _onLongPressSlot(int slot, List<RewardItem> items) async {
    final item = _itemAtSlot(items, slot);
    if (item == null) {
      return;
    }
    final config = ref.read(configProvider);
    final definition = config.rewardById(item.definitionId);
    if (definition == null) {
      return;
    }
    final now = ref.read(clockProvider)();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: RewardGlyph(
                  definition,
                  size: 44,
                  level: definition.isBitter ? item.level : null,
                ),
                title: Text(_titleOf(definition, item)),
                subtitle: Text(
                  item.expireAt == null
                      ? '永久保存'
                      : '剩余 ${formatRemaining(item.remainingAt(now))}',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _confirmDelete(item);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(RewardItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这件奖励？'),
        content: const Text('删除后无法找回。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(warehouseProvider.notifier).delete(item);
    if (!mounted) {
      return;
    }
    setState(() => _selectedId = null);
    await _claimPending();
  }

  Future<void> _clearExpired() async {
    final now = ref.read(clockProvider)();
    final removed = await ref
        .read(warehouseProvider.notifier)
        .clearExpired(now);
    if (!mounted) {
      return;
    }
    _toast(removed == 0 ? '没有过期奖励' : '已清理 $removed 个过期奖励');
    await _claimPending();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final asyncItems = ref.watch(warehouseProvider);
    final now = ref.read(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text('仓库'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _clearExpired,
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('清理过期'),
          ),
        ],
      ),
      body: asyncItems.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('读取仓库失败：$error')),
        data: (items) {
          final bySlot = <int, RewardItem>{
            for (final item in items) item.slotIndex: item,
          };
          final selected = _findSelected(items);

          return Column(
            children: <Widget>[
              if (selected != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    '已选中 ${_describe(config, selected)}，再点一件尝试合成，或点空格移动',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: AppDatabase.warehouseCapacity,
                  itemBuilder: (context, slot) {
                    final item = bySlot[slot];
                    final definition = item == null
                        ? null
                        : config.rewardById(item.definitionId);
                    return _SlotCell(
                      item: item,
                      definition: definition,
                      selected: item != null && item.id == _selectedId,
                      expired: item?.isExpiredAt(now) ?? false,
                      remaining: item?.remainingAt(now),
                      onTap: () => _onTapSlot(slot, items),
                      onLongPress: () => _onLongPressSlot(slot, items),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '两件相同奖励可合成上一级；任意两个苦瓜按等级相加。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _titleOf(RewardDefinition definition, RewardItem item) {
    return definition.isBitter
        ? '${item.level} 级${definition.name}'
        : definition.name;
  }

  String _describe(AppConfig config, RewardItem item) {
    final definition = config.rewardById(item.definitionId);
    if (definition == null) {
      return item.definitionId;
    }
    return _titleOf(definition, item);
  }
}

class _SlotCell extends StatelessWidget {
  const _SlotCell({
    required this.item,
    required this.definition,
    required this.selected,
    required this.expired,
    required this.remaining,
    required this.onTap,
    required this.onLongPress,
  });

  final RewardItem? item;
  final RewardDefinition? definition;
  final bool selected;
  final bool expired;
  final Duration? remaining;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = item == null || definition == null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: empty ? null : onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: empty ? Colors.white.withValues(alpha: 0.5) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? scheme.primary
                : (empty ? Colors.black12 : Colors.black.withValues(alpha: 0.06)),
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: empty
            ? const Center(
                child: Icon(Icons.add, color: Colors.black26, size: 18),
              )
            : Opacity(
                opacity: expired ? 0.45 : 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    RewardGlyph(
                      definition!,
                      size: 34,
                      level: definition!.isBitter ? item!.level : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      definition!.isBitter
                          ? '${item!.level}级${definition!.name}'
                          : definition!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      expired ? '已过期' : formatRemaining(remaining),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: expired ? scheme.error : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
