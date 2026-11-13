import 'package:flutter/widgets.dart';

import '../../core/native/native_monitor.dart';

/// 导致任务失败的中断类型，`reason` 会写进 `task_sessions.failure_reason`。
enum InterruptionFailure {
  background('background_timeout', '切换到其他应用'),
  focusLost('focus_timeout', '应用失去焦点'),
  multiWindow('multi_window', '进入了分屏'),
  pip('pip', '进入了画中画');

  const InterruptionFailure(this.reason, this.label);

  final String reason;
  final String label;
}

/// 中断判定器（纯逻辑，不碰 UI、不碰数据库）。
///
/// 规则来自规格 1.5：
/// - 切后台 10 秒宽限；
/// - 失焦（通知栏、系统弹窗）60 秒宽限；
/// - 分屏 / 画中画：立即失败；
/// - 来电、息屏：豁免，计时继续。
///
/// 它不改计时，只回答两个问题：「现在该判失败吗」「还剩多少宽限」。
class InterruptionTracker {
  InterruptionTracker({
    this.backgroundGrace = const Duration(seconds: 10),
    this.focusGrace = const Duration(seconds: 60),
  });

  final Duration backgroundGrace;
  final Duration focusGrace;

  DateTime? _backgroundSince;
  DateTime? _focusSince;
  bool _screenOff = false;
  bool _inCall = false;
  InterruptionFailure? _fatal;

  /// 息屏或通话中：不计中断、不判失败。
  bool get isExempted => _screenOff || _inCall;

  bool get inCall => _inCall;

  bool get screenOff => _screenOff;

  /// 当前是否存在进行中的中断（用于 UI 提示）。
  bool get isInterrupted => _backgroundSince != null || _focusSince != null;

  void onLifecycle(AppLifecycleState state, DateTime now) {
    switch (state) {
      case AppLifecycleState.resumed:
        _backgroundSince = null;
        _focusSince = null;
      case AppLifecycleState.inactive:
        if (!isExempted) {
          _focusSince ??= now;
        }
      case AppLifecycleState.paused:
        if (!isExempted) {
          _backgroundSince ??= now;
        }
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void onNative(NativeEvent event, DateTime now) {
    switch (event) {
      case NativeEvent.screenOff:
        _screenOff = true;
        _clearTimers();
      case NativeEvent.screenOn:
        _screenOff = false;
      case NativeEvent.focusLost:
        if (!isExempted) {
          _focusSince ??= now;
        }
      case NativeEvent.focusGained:
        _focusSince = null;
      case NativeEvent.multiWindowEntered:
        _fatal = InterruptionFailure.multiWindow;
      case NativeEvent.pipEntered:
        _fatal = InterruptionFailure.pip;
      case NativeEvent.phoneRinging:
      case NativeEvent.phoneOffhook:
        _inCall = true;
        _clearTimers();
      case NativeEvent.phoneIdle:
        _inCall = false;
      case NativeEvent.multiWindowExited:
      case NativeEvent.pipExited:
      case NativeEvent.phonePermissionDenied:
        break;
    }
  }

  /// 现在应该判失败吗？返回 null 表示继续。
  InterruptionFailure? evaluate(DateTime now) {
    if (_fatal != null) {
      return _fatal;
    }
    if (isExempted) {
      _clearTimers();
      return null;
    }
    final background = _backgroundSince;
    if (background != null && now.difference(background) >= backgroundGrace) {
      return InterruptionFailure.background;
    }
    final focus = _focusSince;
    if (focus != null && now.difference(focus) >= focusGrace) {
      return InterruptionFailure.focusLost;
    }
    return null;
  }

  /// 当前宽限剩余时间；没有中断时返回 null。
  Duration? graceRemaining(DateTime now) {
    if (isExempted) {
      return null;
    }
    Duration? remaining;
    final background = _backgroundSince;
    if (background != null) {
      remaining = backgroundGrace - now.difference(background);
    }
    final focus = _focusSince;
    if (focus != null) {
      final focusRemaining = focusGrace - now.difference(focus);
      if (remaining == null || focusRemaining < remaining) {
        remaining = focusRemaining;
      }
    }
    if (remaining == null) {
      return null;
    }
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// 给用户看的提示文案；没有中断时返回 null。
  String? get notice {
    if (_inCall) {
      return '通话中，计时继续';
    }
    if (_screenOff) {
      return '息屏中，计时继续';
    }
    if (_backgroundSince != null) {
      return '检测到你离开了应用，${backgroundGrace.inSeconds} 秒内返回';
    }
    if (_focusSince != null) {
      return '检测到系统中断，${focusGrace.inSeconds} 秒内返回';
    }
    return null;
  }

  void _clearTimers() {
    _backgroundSince = null;
    _focusSince = null;
  }
}
