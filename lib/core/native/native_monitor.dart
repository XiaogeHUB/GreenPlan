import 'dart:async';

import 'package:flutter/services.dart';

/// 原生事件类型，字符串与 Android 端 `MainActivity` 保持一致。
enum NativeEvent {
  screenOff('screenOff'),
  screenOn('screenOn'),
  focusLost('focusLost'),
  focusGained('focusGained'),
  multiWindowEntered('multiWindowEntered'),
  multiWindowExited('multiWindowExited'),
  pipEntered('pipEntered'),
  pipExited('pipExited'),
  phoneRinging('phoneRinging'),
  phoneOffhook('phoneOffhook'),
  phoneIdle('phoneIdle'),
  phonePermissionDenied('phonePermissionDenied');

  const NativeEvent(this.wireName);

  final String wireName;

  static NativeEvent? parse(String raw) {
    for (final event in NativeEvent.values) {
      if (event.wireName == raw) {
        return event;
      }
    }
    return null;
  }
}

/// 原生能力桥：息屏、窗口焦点、分屏/画中画、电话状态。
///
/// 桌面端或单元测试里没有原生实现，所有方法都会安静失败，不会抛异常。
class NativeMonitor {
  const NativeMonitor();

  static const MethodChannel _methods =
      MethodChannel('greenplan/native_monitor');
  static const EventChannel _events = EventChannel('greenplan/native_events');

  Stream<NativeEvent> get events {
    return _events.receiveBroadcastStream().map((dynamic raw) {
      return NativeEvent.parse(raw as String);
    }).where((event) => event != null).cast<NativeEvent>();
  }

  Future<void> start() => _invoke('startMonitoring');

  Future<void> stop() => _invoke('stopMonitoring');

  Future<bool> isPhonePermissionGranted() async {
    try {
      return await _methods.invokeMethod<bool>('isPhonePermissionGranted') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestPhonePermission() => _invoke('requestPhonePermission');

  Future<void> _invoke(String method) async {
    try {
      await _methods.invokeMethod<void>(method);
    } on MissingPluginException {
      // 桌面 / 测试环境没有原生实现，忽略。
    } on PlatformException {
      // 原生侧拒绝或未实现，忽略。
    }
  }
}
