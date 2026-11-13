/// 把剩余时间格式化成紧凑的中文文案。
///
/// 例如 `2天3时` / `3时12分` / `12分` / `已过期`。
String formatRemaining(Duration? remaining) {
  if (remaining == null) {
    return '永久';
  }
  if (remaining.isNegative || remaining == Duration.zero) {
    return '已过期';
  }
  final days = remaining.inDays;
  final hours = remaining.inHours % 24;
  final minutes = remaining.inMinutes % 60;

  if (days > 0) {
    return '$days天$hours时';
  }
  if (hours > 0) {
    return '$hours时$minutes分';
  }
  if (minutes > 0) {
    return '$minutes分';
  }
  return '${remaining.inSeconds}秒';
}

/// 把一段时长格式化成中文文案，用于「共 X」这类展示。
String formatDurationLabel(Duration duration) {
  if (duration.inSeconds < 60) {
    return '${duration.inSeconds} 秒';
  }
  if (duration.inMinutes < 60) {
    return '${duration.inMinutes} 分钟';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分';
}

/// 倒计时文案：`HH:MM:SS`，不足一小时时省略小时段。
String formatCountdown(Duration remaining) {
  final safe = remaining.isNegative ? Duration.zero : remaining;
  final hours = safe.inHours;
  final minutes = safe.inMinutes % 60;
  final seconds = safe.inSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
  }
  return '$mm:$ss';
}
