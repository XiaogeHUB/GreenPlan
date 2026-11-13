import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../config/reward_definition.dart';
import '../../data/db/app_database.dart';
import '../../data/db/dao/reward_item_dao.dart';
import '../../data/db/dao/title_progress_dao.dart';
import '../../data/models/reward_item.dart';

/// 合成失败的原因。
class SynthesisException implements Exception {
  const SynthesisException(this.message);

  final String message;

  @override
  String toString() => 'SynthesisException: $message';
}

/// 一次合成的结果。
class SynthesisResult {
  const SynthesisResult({
    required this.product,
    required this.consumed,
    required this.titleLevel,
  });

  /// 产物（已在库里）。
  final RewardItem product;

  /// 被消耗的两个物品（合成前状态，供动画使用）。
  final List<RewardItem> consumed;

  /// 如果产物是苦瓜，这里是刷新后的历史最高等级；否则为 null。
  final int? titleLevel;
}

/// 仓库合成：两个同类合成下一级，任意两个苦瓜按 `n + m` 累计。
///
/// 规格 6.3 要求整个过程在一个事务里，因此这里直接持有 [AppDatabase]。
class SynthesisService {
  SynthesisService({
    required this.db,
    required this.config,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final AppConfig config;
  final DateTime Function() _clock;

  /// 两个物品现在能不能合成（UI 用来判断拖拽是否有效）。
  bool canSynthesize(RewardItem a, RewardItem b, DateTime now) {
    if (a.id == b.id) {
      return false;
    }
    if (a.isExpiredAt(now) || b.isExpiredAt(now)) {
      return false;
    }
    final defA = config.rewardById(a.definitionId);
    final defB = config.rewardById(b.definitionId);
    if (defA == null || defB == null) {
      return false;
    }
    if (defA.isBitter || defB.isBitter) {
      return defA.isBitter && defB.isBitter && defA.bitterCombine;
    }
    return defA.id == defB.id && defA.canUpgrade;
  }

  /// 执行合成，返回产物。
  ///
  /// [targetSlot] 必须是两个原材料之一所在的格位；产物落在该格，另一格清空。
  /// 任何一步失败都会抛异常并回滚，不会出现「两个物品被删但产物没写入」。
  Future<SynthesisResult> synthesize({
    required String idA,
    required String idB,
    required int targetSlot,
  }) {
    final now = _clock();
    return db.transaction((txn) async {
      final dao = RewardItemDao(txn);
      final a = await dao.getById(idA);
      final b = await dao.getById(idB);
      if (a == null || b == null) {
        throw const SynthesisException('物品不存在或已被合成');
      }
      if (targetSlot != a.slotIndex && targetSlot != b.slotIndex) {
        throw const SynthesisException('产物格位必须是两个原材料之一所在的格位');
      }
      if (!canSynthesize(a, b, now)) {
        throw SynthesisException(_explain(a, b, now));
      }

      final product = _buildProduct(a, b, targetSlot, now);

      await dao.deleteById(a.id);
      await dao.deleteById(b.id);
      await dao.insert(product);

      int? titleLevel;
      if (_definitionOf(product).isBitter) {
        titleLevel = await TitleProgressDao(txn).bumpMaxLevel(product.level);
      }

      return SynthesisResult(
        product: product,
        consumed: <RewardItem>[a, b],
        titleLevel: titleLevel,
      );
    });
  }

  RewardItem _buildProduct(
    RewardItem a,
    RewardItem b,
    int slotIndex,
    DateTime now,
  ) {
    final defA = _definitionOf(a);

    if (defA.isBitter) {
      // 苦瓜：等级相加，永久。
      final bitter = config.finalReward;
      return RewardItem(
        id: const Uuid().v4(),
        definitionId: bitter.id,
        level: a.level + b.level,
        slotIndex: slotIndex,
        createdAt: now,
      );
    }

    final next = _definitionOf(a, id: defA.nextId!);
    return RewardItem(
      id: const Uuid().v4(),
      definitionId: next.id,
      level: 1,
      slotIndex: slotIndex,
      createdAt: now,
      expireAt: next.permanent
          ? null
          : now.add(Duration(hours: next.shelfLifeHours!)),
    );
  }

  String _explain(RewardItem a, RewardItem b, DateTime now) {
    if (a.isExpiredAt(now) || b.isExpiredAt(now)) {
      return '过期物品不能合成';
    }
    final defA = _definitionOf(a);
    final defB = _definitionOf(b);
    if (defA.isBitter != defB.isBitter) {
      return '苦瓜只能和苦瓜合成';
    }
    if (defA.id != defB.id) {
      return '只有相同的奖励才能合成：${defA.name} + ${defB.name}';
    }
    if (!defA.canUpgrade) {
      return '${defA.name} 已经是最高级，无法继续合成';
    }
    return '这两个物品无法合成';
  }

  RewardDefinition _definitionOf(RewardItem item, {String? id}) {
    final definition = config.rewardById(id ?? item.definitionId);
    if (definition == null) {
      throw SynthesisException('奖励定义不存在: ${id ?? item.definitionId}');
    }
    return definition;
  }
}
