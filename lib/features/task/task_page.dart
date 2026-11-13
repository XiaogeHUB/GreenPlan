import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/native/native_monitor.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../data/models/task_session.dart';
import '../../domain/services/interruption_tracker.dart';
import '../../domain/services/task_service.dart';

/// 任务页：倒计时 + 中断判定 + 完成/放弃。
///
/// 中断规则由 [InterruptionTracker] 决定，本页只负责：
/// 上报生命周期与原生事件、按判定结果提示或判失败。
class TaskPage extends ConsumerStatefulWidget {
  const TaskPage({required this.session, super.key});

  final TaskSession session;

  @override
  ConsumerState<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends ConsumerState<TaskPage>
    with WidgetsBindingObserver {
  late final InterruptionTracker _tracker = InterruptionTracker();
  late final NativeMonitor _monitor;
  Timer? _ticker;
  StreamSubscription<NativeEvent>? _nativeEvents;
  late Duration _remaining;
  bool _finishing = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _monitor = ref.read(nativeMonitorProvider);
    _remaining = _remainingNow();
    WidgetsBinding.instance.addObserver(this);
    _startNativeMonitoring();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _onTick(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _nativeEvents?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_monitor.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _tracker.onLifecycle(state, _now);
  }

  Future<void> _startNativeMonitoring() async {
    final monitor = _monitor;
    _nativeEvents = monitor.events.listen(
      (event) {
        _tracker.onNative(event, _now);
        if (mounted) {
          setState(() {});
        }
      },
      // 桌面端 / 测试环境没有原生实现，事件流会报 MissingPluginException，忽略即可。
      onError: (Object _) {},
    );
    await monitor.start();

    // 未授权电话状态时，来电会被当作普通失焦（60 秒宽限），必须显式告知用户。
    final granted = await monitor.isPhonePermissionGranted();
    if (!mounted || granted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('未开启来电豁免，来电可能导致任务失败。可在「设置 → 来电豁免」开启。'),
      ),
    );
  }

  DateTime get _now => ref.read(clockProvider)();

  Duration _remainingNow() => widget.session.remainingAt(_now);

  void _onTick() {
    if (!mounted || _finishing) {
      return;
    }
    final remaining = _remainingNow();

    final failure = _tracker.evaluate(_now);
    if (failure != null) {
      unawaited(_fail(failure));
      return;
    }

    if (remaining != _remaining) {
      setState(() => _remaining = remaining);
    }
    if (remaining == Duration.zero) {
      unawaited(_complete());
    }
  }

  Future<void> _fail(InterruptionFailure failure) async {
    if (_finishing) {
      return;
    }
    _finishing = true;
    _ticker?.cancel();

    try {
      await ref
          .read(taskServiceProvider)
          .failTask(widget.session.id, reason: failure.reason);
    } on TaskException {
      // 任务已结束，忽略
    }
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('任务失败'),
        content: Text('${failure.label}，本次自律中断，没有奖励。'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _leaving = true);
    context.pop();
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
    final now = _now;
    final progress = widget.session.progressAt(now);
    final notice = _tracker.notice;
    final grace = _tracker.graceRemaining(now);

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
        body: Stack(
          children: <Widget>[
            Center(
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
                              '共 ${formatDurationLabel(widget.session.plannedDuration)}',
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
            if (notice != null)
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: _InterruptionBanner(message: notice, grace: grace),
              ),
          ],
        ),
      ),
    );
  }
}

class _InterruptionBanner extends StatelessWidget {
  const _InterruptionBanner({required this.message, required this.grace});

  final String message;
  final Duration? grace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = grace;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: scheme.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                remaining == null
                    ? message
                    : '$message（还剩 ${remaining.inSeconds} 秒）',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
