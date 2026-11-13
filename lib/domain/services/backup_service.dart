import 'dart:convert';

import 'package:flutter/services.dart' show Uint8List;

import '../../config/app_config.dart';
import '../../config/config_exception.dart';
import '../../data/db/app_database.dart';
import '../../data/db/dao/reward_item_dao.dart';
import '../../data/db/dao/settings_dao.dart';
import '../../data/db/dao/task_session_dao.dart';
import '../../data/db/dao/title_progress_dao.dart';
import '../../data/models/reward_item.dart';
import '../../data/models/task_session.dart';

/// 备份/恢复失败。
class BackupException implements Exception {
  const BackupException(this.message, {this.issues = const <String>[]});

  final String message;
  final List<String> issues;

  @override
  String toString() {
    if (issues.isEmpty) {
      return 'BackupException: $message';
    }
    return 'BackupException: $message\n${issues.map((e) => ' - $e').join('\n')}';
  }
}

/// 一份校验过的备份数据。
class BackupPayload {
  const BackupPayload({
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.items,
    required this.sessions,
    required this.settings,
    required this.maxGuadaLevel,
  });

  final int schemaVersion;
  final DateTime exportedAt;
  final String appVersion;
  final List<RewardItem> items;
  final List<TaskSession> sessions;
  final Map<String, String> settings;
  final int maxGuadaLevel;
}

/// 备份导出 / 导入（规格第 11 节）。
///
/// 导入是「替换全部本地数据」，且整体在一个事务里：中途失败不会留下半套数据。
class BackupService {
  const BackupService({required this.db, required this.config});

  final AppDatabase db;
  final AppConfig config;

  /// 当前支持的备份格式版本。
  static const int schemaVersion = 1;

  static const String appVersion = '1.0.0';

  /// 导出为 JSON 字符串。
  Future<String> export({DateTime? now}) async {
    final itemDao = RewardItemDao(db.db);
    final taskDao = TaskSessionDao(db.db);
    final settingsDao = SettingsDao(db.db);
    final titleDao = TitleProgressDao(db.db);

    final items = await itemDao.getAll();
    final sessions = await taskDao.recent(limit: 500);
    final settings = await settingsDao.getAll();
    final maxLevel = await titleDao.getMaxLevel();

    final data = <String, Object?>{
      'schemaVersion': schemaVersion,
      'exportedAt': (now ?? DateTime.now()).millisecondsSinceEpoch,
      'appVersion': appVersion,
      'data': <String, Object?>{
        'settings': settings,
        'titleProgress': <String, Object?>{'maxGuadaLevel': maxLevel},
        'rewardItems': items.map(_itemToJson).toList(growable: false),
        'taskSessions': sessions.map(_sessionToJson).toList(growable: false),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 解析并校验备份文件；任何问题都会抛 [BackupException]。
  BackupPayload parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw BackupException('不是合法的 JSON 文件', issues: <String>[error.message]);
    }
    if (decoded is! Map) {
      throw const BackupException('备份文件顶层必须是 JSON 对象');
    }
    final root = decoded.cast<String, Object?>();

    final version = root['schemaVersion'];
    if (version is! int) {
      throw const BackupException('缺少 schemaVersion');
    }
    if (version > schemaVersion) {
      throw BackupException('备份版本 $version 高于当前支持的 $schemaVersion，请升级 App');
    }

    final data = root['data'];
    if (data is! Map) {
      throw const BackupException('备份缺少 data 字段');
    }
    final dataMap = data.cast<String, Object?>();

    final issues = <String>[];
    final items = _parseItems(dataMap['rewardItems'], issues);
    final sessions = _parseSessions(dataMap['taskSessions'], issues);

    final settingsRaw = dataMap['settings'];
    final settings = <String, String>{};
    if (settingsRaw is Map) {
      settingsRaw.forEach((key, value) {
        if (key is String && value is String) {
          settings[key] = value;
        } else {
          issues.add('settings 里存在非字符串键值: $key');
        }
      });
    } else if (settingsRaw != null) {
      issues.add('settings 必须是对象');
    }

    var maxLevel = 0;
    final titleRaw = dataMap['titleProgress'];
    if (titleRaw is Map) {
      final value = titleRaw['maxGuadaLevel'];
      if (value is int && value >= 0) {
        maxLevel = value;
      } else if (value != null) {
        issues.add('maxGuadaLevel 必须是非负整数');
      }
    }

    _checkSlots(items, issues);

    if (issues.isNotEmpty) {
      throw BackupException('备份校验失败（${issues.length} 项）', issues: issues);
    }

    return BackupPayload(
      schemaVersion: version,
      exportedAt: DateTime.fromMillisecondsSinceEpoch(
        (root['exportedAt'] as int?) ?? 0,
      ),
      appVersion: (root['appVersion'] as String?) ?? '',
      items: items,
      sessions: sessions,
      settings: settings,
      maxGuadaLevel: maxLevel,
    );
  }

  /// 用备份替换全部本地数据（事务）。
  Future<void> restore(BackupPayload payload) async {
    await db.transaction((txn) async {
      final itemDao = RewardItemDao(txn);
      final taskDao = TaskSessionDao(txn);
      final settingsDao = SettingsDao(txn);
      final titleDao = TitleProgressDao(txn);

      await itemDao.deleteAll();
      await txn.delete(TaskSessionDao.table);
      await txn.delete(SettingsDao.table);

      for (final item in payload.items) {
        await itemDao.insert(item);
      }
      for (final session in payload.sessions) {
        await taskDao.insert(session);
      }
      if (payload.settings.isNotEmpty) {
        await settingsDao.putAll(payload.settings);
      }
      await titleDao.setMaxLevel(payload.maxGuadaLevel);
    });
  }

  List<RewardItem> _parseItems(Object? raw, List<String> issues) {
    if (raw is! List) {
      issues.add('rewardItems 必须是数组');
      return const <RewardItem>[];
    }
    final result = <RewardItem>[];
    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is! Map) {
        issues.add('rewardItems[$index] 不是对象');
        continue;
      }
      final map = entry.cast<String, Object?>();
      final id = map['id'];
      final definitionId = map['definitionId'];
      final slotIndex = map['slotIndex'];
      final createdAt = map['createdAt'];

      if (id is! String || id.isEmpty) {
        issues.add('rewardItems[$index].id 缺失');
        continue;
      }
      if (definitionId is! String || config.rewardById(definitionId) == null) {
        issues.add('rewardItems[$index] 引用了未知奖励: $definitionId');
        continue;
      }
      if (slotIndex is! int || slotIndex < 0 || slotIndex >= AppDatabase.warehouseCapacity) {
        issues.add('rewardItems[$index].slotIndex 越界: $slotIndex');
        continue;
      }
      if (createdAt is! int) {
        issues.add('rewardItems[$index].createdAt 缺失');
        continue;
      }

      result.add(
        RewardItem(
          id: id,
          definitionId: definitionId,
          level: (map['level'] as int?) ?? 1,
          slotIndex: slotIndex,
          createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
          expireAt: switch (map['expireAt']) {
            final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
            _ => null,
          },
          sourceTaskId: map['sourceTaskId'] as String?,
          effectsJson: map['effectsJson'] as String?,
          locked: (map['locked'] as bool?) ?? false,
        ),
      );
    }
    return result;
  }

  List<TaskSession> _parseSessions(Object? raw, List<String> issues) {
    if (raw == null) {
      return const <TaskSession>[];
    }
    if (raw is! List) {
      issues.add('taskSessions 必须是数组');
      return const <TaskSession>[];
    }
    final result = <TaskSession>[];
    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is! Map) {
        issues.add('taskSessions[$index] 不是对象');
        continue;
      }
      final map = entry.cast<String, Object?>();
      try {
        result.add(TaskSession.fromRow(<String, Object?>{
          'id': map['id'],
          'duration_minutes': map['durationMinutes'],
          'reward_definition_id': map['rewardDefinitionId'],
          'started_at': map['startedAt'],
          'expected_end_at': map['expectedEndAt'],
          'ended_at': map['endedAt'],
          'status': map['status'],
          'failure_reason': map['failureReason'],
          'pending_reward_definition_id': map['pendingRewardDefinitionId'],
          'created_at': map['createdAt'],
        }));
      } catch (error) {
        issues.add('taskSessions[$index] 格式错误: $error');
      }
    }
    return result;
  }

  void _checkSlots(List<RewardItem> items, List<String> issues) {
    final slots = <int>{};
    for (final item in items) {
      if (!slots.add(item.slotIndex)) {
        issues.add('格位重复: ${item.slotIndex}');
      }
    }
  }

  Map<String, Object?> _itemToJson(RewardItem item) => <String, Object?>{
        'id': item.id,
        'definitionId': item.definitionId,
        'level': item.level,
        'slotIndex': item.slotIndex,
        'createdAt': item.createdAt.millisecondsSinceEpoch,
        'expireAt': item.expireAt?.millisecondsSinceEpoch,
        'sourceTaskId': item.sourceTaskId,
        'effectsJson': item.effectsJson,
        'locked': item.locked,
      };

  Map<String, Object?> _sessionToJson(TaskSession session) => <String, Object?>{
        'id': session.id,
        'durationMinutes': session.durationMinutes,
        'rewardDefinitionId': session.rewardDefinitionId,
        'startedAt': session.startedAt.millisecondsSinceEpoch,
        'expectedEndAt': session.expectedEndAt.millisecondsSinceEpoch,
        'endedAt': session.endedAt?.millisecondsSinceEpoch,
        'status': session.status.wireName,
        'failureReason': session.failureReason,
        'pendingRewardDefinitionId': session.pendingRewardDefinitionId,
        'createdAt': session.createdAt.millisecondsSinceEpoch,
      };
}

/// 备份文件名：`greenplan-backup-20261114-0130.json`。
String backupFileName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'greenplan-backup-${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}.json';
}

/// 把字符串转成可写入文件的字节。
Uint8List backupBytes(String content) => Uint8List.fromList(utf8.encode(content));

/// 导出时遇到配置问题的统一兜底（理论上不会触发）。
ConfigException backupConfigError(Object error) =>
    ConfigException('备份导出失败', issues: <String>['$error']);
