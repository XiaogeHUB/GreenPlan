import 'package:flutter/material.dart';

import '../../config/reward_definition.dart';

/// 全局主题。绿色系，和「菜品养成」的调性一致。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E7D32),
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF6F8F4),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
  );
}

/// 奖励的「图标」。
///
/// 现在还没有美术资源，先用名称首字 + 分级配色顶替；等 `assets/rewards/*.png`
/// 补齐后，这里换成 `Image.asset(definition.icon)` 即可，调用方不用改。
class RewardGlyph extends StatelessWidget {
  const RewardGlyph(this.definition, {super.key, this.size = 40, this.level});

  final RewardDefinition definition;
  final double size;

  /// 苦瓜用它自己的等级覆盖展示。
  final int? level;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(definition);
    final label = level == null
        ? definition.name.substring(0, 1)
        : '$level';

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * (level == null ? 0.42 : 0.38),
        ),
      ),
    );
  }

  static Color _colorFor(RewardDefinition definition) {
    switch (definition.type) {
      case RewardType.ordinary:
        return const Color(0xFF2E7D32);
      case RewardType.special:
        return const Color(0xFF00695C);
      case RewardType.bitter:
        return const Color(0xFF6A1B9A);
    }
  }
}
