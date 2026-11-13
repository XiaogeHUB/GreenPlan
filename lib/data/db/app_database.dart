import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite 连接与表结构管理。
///
/// 设计约定：
/// - 时间统一存毫秒时间戳（INTEGER）；
/// - 过期状态不落库，只存 `expire_at`；
/// - DAO 接收 [DatabaseExecutor]，因此既能在 [db] 上跑，也能在事务里跑。
class AppDatabase {
  const AppDatabase._(this.db);

  /// 底层连接。业务代码优先用 DAO，不要直接拼 SQL。
  final Database db;

  /// 表结构版本，改动结构时 +1 并在 [_onUpgrade] 补迁移。
  static const int schemaVersion = 1;

  static const String fileName = 'greenplan.db';

  /// 仓库容量，规格 1.4 固定 24 格。
  static const int warehouseCapacity = 24;

  /// 打开（必要时创建）数据库。
  ///
  /// [factory] 与 [path] 仅用于测试注入（例如 `sqflite_common_ffi` 的内存库）。
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), fileName);

    final database = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          await _createSchema(db);
          await _seedDefaults(db);
        },
        onUpgrade: _onUpgrade,
      ),
    );
    return AppDatabase._(database);
  }

  /// 在一个事务里执行 [action]；DAO 传入 [Transaction] 即可共享同一事务。
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) {
    return db.transaction<T>(action);
  }

  Future<void> close() => db.close();

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();
    for (final statement in _schema) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _seedDefaults(Database db) async {
    await db.insert(
      'title_progress',
      <String, Object?>{'id': 1, 'max_guada_level': 0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final batch = db.batch();
    batch.insert(
      'settings',
      <String, Object?>{'key': 'expiry_notification', 'value': 'true'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    batch.insert(
      'settings',
      <String, Object?>{'key': 'onboarding_shown', 'value': 'false'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 是初始版本，暂无迁移。后续版本在此按 oldVersion 逐级升级。
    throw UnsupportedError('未实现的数据库迁移: v$oldVersion -> v$newVersion');
  }

  static const List<String> _schema = <String>[
    '''
    CREATE TABLE reward_items (
      id TEXT PRIMARY KEY,
      definition_id TEXT NOT NULL,
      level INTEGER NOT NULL DEFAULT 1,
      slot_index INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      expire_at INTEGER,
      source_task_id TEXT,
      effects_json TEXT,
      locked INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE UNIQUE INDEX idx_reward_slot ON reward_items(slot_index)',
    '''
    CREATE TABLE task_sessions (
      id TEXT PRIMARY KEY,
      duration_minutes INTEGER NOT NULL,
      reward_definition_id TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      expected_end_at INTEGER NOT NULL,
      ended_at INTEGER,
      status TEXT NOT NULL,
      failure_reason TEXT,
      pending_reward_definition_id TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_task_status ON task_sessions(status)',
    '''
    CREATE TABLE interruption_events (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      type TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      ended_at INTEGER,
      grace_ms INTEGER,
      outcome TEXT
    )
    ''',
    'CREATE INDEX idx_interruption_session ON interruption_events(session_id)',
    '''
    CREATE TABLE title_progress (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      max_guada_level INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  ];
}
