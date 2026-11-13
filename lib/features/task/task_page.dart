import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../data/models/task_session.dart';
import '../../domain/services/task_service.dart';

/// 任务页：倒计时 + 完成/放弃。
///
/// 说明：中断检测（切屏、来电、息屏）还没有接入，当前版本切后台不会判失败，
/// 下一步由中断管理器接管。
class TaskPage extends ConsumerStatefulWidget {
  const TaskPage({required this.session, super.key});

  final TaskSession session;

  @override
  ConsumerState<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends ConsumerState<TaskPage> {
  Timer? _ticker;
  late Duration _remaining;
  bool _finishing = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _remaining = _remainingNow();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _onTick(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime get _now => ref.read(clockProvider)();

  Duration _remainingNow() => widget.session.remainingAt(_now);

  void _onTick() {
    if (!mounted || _finishing) {
      return;
    }
    final remaining = _remainingNow();
    if (remaining != _remaining) {
      setState(() => _remaining = remaining);
    }
    if (remaining == Duration.zero) {
      unawaited(_complete());
    }
  }

  Future<void> _complete() async {
    if (_finishing) {
      return;
    }
    _finishing = true;
    _ticker?.cancel();

    try {
      final done = await ref
          .read(taskServiceProvider)
          .completeTask(widget.session.id);
      if (!mounted) {
        return;
      }
      await _showResult(done);
    } on TaskException catch (error) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('任务结算失败'),
          content: Text(error.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _leaving = true);
        context.pop();
      }
    }
  }

  Future<void> _showResult(TaskSession done) async {
    final config = ref.read(configProvider);
    final pending = done.status == TaskStatus.successPendingReward;
    final rewardName =
        config.rewardById(done.rewardDefinitionId)?.name ?? '奖励';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(pending ? '仓库已满' : '完成！'),
        content: Text(
          pending
              ? '这次的自律已记录，但仓库满了放不下「$rewardName」。\n清理仓库后会自动领取。'
              : '恭喜完成，获得「$rewardName」，已放入仓库。',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAbandon() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃这次自律？'),
        content: const Text('放弃后本次不会获得奖励，可以立即重新开始。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续坚持'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref.read(taskServiceProvider).abandonTask(widget.session.id);
    } on TaskException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
    if (!mounted) {
      return;
    }
    setState(() => _leaving = true);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.read(configProvider);
    final reward = config.rewardById(widget.session.rewardDefinitionId);
    final progress = widget.session.progressAt(_now);

    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_confirmAbandon());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('自律中'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
                        backgroundColor: Colors.black12,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          formatCountdown(_remaining),
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '共 ${widget.session.durationMinutes} 分钟',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (reward != null) ...<Widget>[
                RewardGlyph(reward, size: 52),
                const SizedBox(height: 10),
                Text(
                  '完成后获得「${reward.name}」',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: _finishing ? null : _confirmAbandon,
                child: const Text('放弃这次自律'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
