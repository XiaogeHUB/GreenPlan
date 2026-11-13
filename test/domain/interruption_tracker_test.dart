import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenplan/core/native/native_monitor.dart';
import 'package:greenplan/domain/services/interruption_tracker.dart';

void main() {
  final start = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

  InterruptionTracker newTracker() => InterruptionTracker();

  group('切后台 10 秒宽限', () {
    test('9 秒返回：不判失败', () {
      final tracker = newTracker();
      tracker.onLifecycle(AppLifecycleState.paused, start);

      expect(
        tracker.evaluate(start.add(const Duration(seconds: 9))),
        isNull,
      );
      expect(tracker.graceRemaining(start.add(const Duration(seconds: 9)))?.inSeconds, 1);

      tracker.onLifecycle(AppLifecycleState.resumed, start.add(const Duration(seconds: 9)));
      expect(tracker.evaluate(start.add(const Duration(minutes: 5))), isNull);
    });

    test('11 秒未返回：判失败', () {
      final tracker = newTracker();
      tracker.onLifecycle(AppLifecycleState.paused, start);

      expect(
        tracker.evaluate(start.add(const Duration(seconds: 11))),
        InterruptionFailure.background,
      );
    });
  });

  group('失去焦点 60 秒宽限', () {
    test('59 秒返回：不判失败', () {
      final tracker = newTracker();
      tracker.onLifecycle(AppLifecycleState.inactive, start);

      expect(tracker.evaluate(start.add(const Duration(seconds: 59))), isNull);

      tracker.onLifecycle(AppLifecycleState.resumed, start.add(const Duration(seconds: 59)));
      expect(tracker.evaluate(start.add(const Duration(minutes: 3))), isNull);
    });

    test('61 秒未返回：判失败', () {
      final tracker = newTracker();
      tracker.onLifecycle(AppLifecycleState.inactive, start);

      expect(
        tracker.evaluate(start.add(const Duration(seconds: 61))),
        InterruptionFailure.focusLost,
      );
    });
  });

  group('豁免', () {
    test('息屏期间不计中断，切后台也不判失败', () {
      final tracker = newTracker();
      tracker.onNative(NativeEvent.screenOff, start);
      tracker.onLifecycle(AppLifecycleState.paused, start);

      expect(
        tracker.evaluate(start.add(const Duration(minutes: 10))),
        isNull,
      );
      expect(tracker.isExempted, isTrue);
      expect(tracker.notice, '息屏中，计时继续');

      tracker.onNative(NativeEvent.screenOn, start.add(const Duration(minutes: 10)));
      expect(tracker.isExempted, isFalse);
    });

    test('通话中不计中断', () {
      final tracker = newTracker();
      tracker.onNative(NativeEvent.phoneRinging, start);
      tracker.onLifecycle(AppLifecycleState.paused, start);

      expect(tracker.evaluate(start.add(const Duration(minutes: 5))), isNull);
      expect(tracker.notice, '通话中，计时继续');

      tracker.onNative(NativeEvent.phoneIdle, start.add(const Duration(minutes: 5)));
      expect(tracker.inCall, isFalse);
    });

    test('通话结束后再切后台，仍然走 10 秒宽限', () {
      final tracker = newTracker();
      tracker.onNative(NativeEvent.phoneRinging, start);
      tracker.onNative(NativeEvent.phoneIdle, start.add(const Duration(seconds: 30)));
      tracker.onLifecycle(AppLifecycleState.paused, start.add(const Duration(seconds: 30)));

      expect(
        tracker.evaluate(start.add(const Duration(seconds: 41))),
        InterruptionFailure.background,
      );
    });
  });

  group('立即失败', () {
    test('进入分屏立即失败', () {
      final tracker = newTracker();
      tracker.onNative(NativeEvent.multiWindowEntered, start);

      expect(tracker.evaluate(start), InterruptionFailure.multiWindow);
    });

    test('进入画中画立即失败', () {
      final tracker = newTracker();
      tracker.onNative(NativeEvent.pipEntered, start);

      expect(tracker.evaluate(start), InterruptionFailure.pip);
    });
  });

  group('提示文案', () {
    test('切后台显示 10 秒提示', () {
      final tracker = newTracker();
      tracker.onLifecycle(AppLifecycleState.paused, start);

      expect(tracker.notice, contains('10 秒'));
    });

    test('失焦显示 60 秒提示', () {
      final tracker = newTracker();
      tracker.onLifecycle(AppLifecycleState.inactive, start);

      expect(tracker.notice, contains('60 秒'));
    });
  });
}
