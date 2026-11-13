import '../../config/app_config.dart';
import '../../data/db/app_database.dart';
import '../../data/db/dao/title_progress_dao.dart';

/// 称号读取。
///
/// 称号是**派生值**：由 `title_progress.max_guada_level` + `titles.json` 算出，
/// 不单独存文案。写入发生在合成出苦瓜时（[SynthesisService] 事务内）。
class TitleService {
  TitleService({required this.config, required this.db});

  final AppConfig config;
  final AppDatabase db;

  /// 历史最高苦瓜等级；从未合成过苦瓜时为 0。
  Future<int> currentLevel() => TitleProgressDao(db.db).getMaxLevel();

  /// 当前称号文案；还没有苦瓜时返回 null（界面不显示称号）。
  Future<String?> currentTitle() async {
    final level = await currentLevel();
    if (level <= 0) {
      return null;
    }
    return config.titleFor(level);
  }
}
