# 自律养成 App 开发规格说明书 v1.0（冻结基线）

> **来源**：DeepSeek 分享对话 <https://chat.deepseek.com/share/c0sare22la75ph0jf2>
> **抓取日期**：2026-11-13
> **状态**：v1.0 冻结基线。实现以此为准；若与用户当场确认的规则冲突，以用户为准，并在下方"决策变更"记录。
> **用法**：本文档不含代码，只定义规则、数据、状态机、页面与验收标准。

## 已知待定 / 不自洽项（实现前需先定夺）

1. **过期通知文案与调度不一致**：计划在 `expire_at - 12h` 提醒，文案却写"48 小时内过期"。
2. **息屏豁免 vs 冷启动判失败**：息屏期间进程被系统回收，下次冷启动会按 `process_death` 判失败，与"息屏允许"冲突。需补 `screen_off` 标记持久化规则。
3. **仓库 6 列 × 4 行在竖屏手机上偏挤** → **已定：4 列 × 6 行**，逻辑仍 24 格。
4. **10s / 60s 判定依赖 `onWindowFocusChanged`**：部分机型下拉通知栏直接走 `paused`，需降级策略。
5. **`success_pending_reward` 与"无暂存箱"存在张力**：仅作异常兜底，需明确 UI 呈现。
6. **备份导入遇未知 `definitionId` 直接中止**：以后新增菜品，旧备份会导不进来。
7. **`minSdk` 24 需补 `PhoneStateListener` 兜底**（`TelephonyCallback` 为 API 31+）→ **已定：保持 minSdk 24 + 兜底分支**。

## 决策变更记录

| 日期 | 条款 | 变更 | 原因 |
|---|---|---|---|
| 2026-11-13 | 0 / 8.2 | 包名 `namespace`、`applicationId`、Kotlin package 统一为 `com.greenplan.app`（原 `com.example.greenplan`） | 去掉占位前缀，避免将来装机身份冲突 |
| 2026-11-13 | 1.5 / 待定项 7 | `minSdk` 显式固定为 24，不跟随 Flutter 默认值；电话监听需 `PhoneStateListener` 兜底 | 覆盖面优先，接受多写一套降级分支 |
| 2026-11-13 | 1.4 / 7.3 / 待定项 3 | 仓库改为 **4 列 × 6 行**（逻辑仍 24 格，`slot_index` 0–23） | 竖屏更易点按 |

---
下面这份可以直接作为开发规格交给 DSH。它把你已经拍板的规则、数据模型、状态机、页面、Android 原生能力、通知、备份、测试验收都写全了。DSH 按这个实现即可，不需要再猜规则。

---

# 自律养成 App 开发规格说明书 v1.0

## 0. 项目定位

- 平台：首发 Android，Flutter + Dart + Android Studio。
- 数据：本地单机，不上云，不做账号。
- 用户：小范围朋友使用，不追求绝对防作弊。
- 核心：选择自律时长 → 前台倒计时 → 完成获得菜品奖励 → 仓库拖拽合成 → 苦瓜无限升级 → 称号。
- 失败无惩罚，可立即重试；短刷开放。
- 代码必须配置化、可扩展，首版不实现道具/活动，但预留接口。

---

## 1. 最终定稿规则

### 1.1 奖励与升级链

升级链固定为：

> 葱 → 香菜 → 上海青 → 小白菜 → 大白菜 → 芹菜 → 西兰花 → 莴笋 → 黄瓜 → 丝瓜 → 苦瓜

- 普通奖励：葱、香菜、上海青、小白菜、大白菜。保质期 3 天（72 小时）。
- 特殊奖励：芹菜、西兰花、莴笋、黄瓜、丝瓜。永久。
- 最终奖励：苦瓜。永久，等级无上限。
- 两个相同定义、未过期的奖励可合成下一级。
- 苦瓜合成特殊规则：任意两个苦瓜可合成，`n级苦瓜 + m级苦瓜 = (n+m)级苦瓜`。
- 苦瓜不自动合成，必须用户手动操作。
- 仓库可同时存在多个不同等级苦瓜。

### 1.2 时长与奖励映射

| 时长 | 奖励 |
|---:|---|
| 15 分钟 | 葱 |
| 30 分钟 | 香菜 |
| 60 分钟 | 上海青 |
| 120 分钟 | 小白菜 |
| 240 分钟 | 大白菜 |

### 1.3 保质期

- 普通奖励入仓时写入 `expire_at = created_at + 72小时`。
- 普通 + 普通合成产物仍为普通：`expire_at = 合成时刻 + 72小时`。
- 普通 + 普通合成产物为特殊：`expire_at = null`。
- 特殊 + 特殊：`expire_at = null`。
- 苦瓜合成：`expire_at = null`。
- 过期物品留在原格子，显示“已过期”，不可合成，只能手动删除。
- 提供“一键清理所有过期”按钮，二次确认。
- 过期通知默认开启，可关闭；过期不可找回。

### 1.4 仓库

- 固定 24 格，6 列 × 4 行，`slot_index` 0–23。
- 无暂存箱。
- 仓库满时禁止开始新任务，提示“仓库已满，请先合成或删除奖励”。
- 过期物品也占格。
- 奖励完成时进入第一个空闲格。
- 拖拽规则：
  - 拖到空格：移动。
  - 拖到可合成目标：触发合成。
  - 拖到不可合成且被占用格：交换位置。
  - 过期物品可移动/交换，但不可合成。
  - 苦瓜拖到苦瓜：弹出确认“合成 N 级 + M 级 = N+M 级苦瓜？”
- 建议同时支持“点选两个物品合成”，避免长列表拖拽困难。

### 1.5 任务与中断

- 任务开始后必须停留在任务页。
- 普通切后台/切应用/返回桌面：宽限 10 秒，超时失败。
- 通知栏下拉、系统弹窗、权限弹窗等失去窗口焦点但 Activity 仍在前台：宽限 60 秒，超时失败。
- 分屏、画中画：检测到立即失败。
- 电话响铃/通话：任务计时继续，不判失败；通话结束回 App 继续。需要 `READ_PHONE_STATE` 权限。
- 电话权限被拒绝：降级为系统中断，60 秒宽限。
- 息屏：允许，计时继续，不判失败。
- 后台进程被杀：下次启动检测到运行中任务，判失败，原因“应用被系统关闭”。
- 放弃任务：二次确认，判失败，无奖励。
- 失败无惩罚，可立即重试。

### 1.6 称号

- 按历史曾达到的最高苦瓜等级显示。
- 配置 1–10 级名称，超过显示“N级苦瓜大王”。
- 称号不因丢弃苦瓜而消失。
- 苦瓜等级无上限。

### 1.7 备份

- 手动导出/导入 JSON。
- 带 `schemaVersion`，导入时校验和迁移。
- 导入为“替换全部本地数据”，导入前二次确认。
- 导入后按当前时间重新判断过期，并重排通知。
- 不做自动备份、不做云同步。

---

## 2. 配置文件

放在 `assets/config/`，启动时加载并校验。代码不得写死奖励链。

### 2.1 `rewards.json`

```json
[
  {"id":"cong","name":"葱","type":"ordinary","level":1,"order":1,"nextId":"xiangcai","permanent":false,"shelfLifeHours":72,"icon":"assets/rewards/cong.png"},
  {"id":"xiangcai","name":"香菜","type":"ordinary","level":2,"order":2,"nextId":"shanghaiqing","permanent":false,"shelfLifeHours":72,"icon":"assets/rewards/xiangcai.png"},
  {"id":"shanghaiqing","name":"上海青","type":"ordinary","level":3,"order":3,"nextId":"xiaobaicai","permanent":false,"shelfLifeHours":72,"icon":"assets/rewards/shanghaiqing.png"},
  {"id":"xiaobaicai","name":"小白菜","type":"ordinary","level":4,"order":4,"nextId":"dabaicai","permanent":false,"shelfLifeHours":72,"icon":"assets/rewards/xiaobaicai.png"},
  {"id":"dabaicai","name":"大白菜","type":"ordinary","level":5,"order":5,"nextId":"qincai","permanent":false,"shelfLifeHours":72,"icon":"assets/rewards/dabaicai.png"},
  {"id":"qincai","name":"芹菜","type":"special","level":6,"order":6,"nextId":"xilanhua","permanent":true,"shelfLifeHours":null,"icon":"assets/rewards/qincai.png"},
  {"id":"xilanhua","name":"西兰花","type":"special","level":7,"order":7,"nextId":"wosun","permanent":true,"shelfLifeHours":null,"icon":"assets/rewards/xilanhua.png"},
  {"id":"wosun","name":"莴笋","type":"special","level":8,"order":8,"nextId":"huanggua","permanent":true,"shelfLifeHours":null,"icon":"assets/rewards/wosun.png"},
  {"id":"huanggua","name":"黄瓜","type":"special","level":9,"order":9,"nextId":"sigua","permanent":true,"shelfLifeHours":null,"icon":"assets/rewards/huanggua.png"},
  {"id":"sigua","name":"丝瓜","type":"special","level":10,"order":10,"nextId":"kugua","permanent":true,"shelfLifeHours":null,"icon":"assets/rewards/sigua.png"},
  {"id":"kugua","name":"苦瓜","type":"bitter","level":1,"order":11,"nextId":null,"permanent":true,"shelfLifeHours":null,"bitterCombine":true,"icon":"assets/rewards/kugua.png"}
]
```

### 2.2 `duration_rewards.json`

```json
[
  {"minutes":15,"rewardId":"cong"},
  {"minutes":30,"rewardId":"xiangcai"},
  {"minutes":60,"rewardId":"shanghaiqing"},
  {"minutes":120,"rewardId":"xiaobaicai"},
  {"minutes":240,"rewardId":"dabaicai"}
]
```

### 2.3 `titles.json`

```json
{
  "titles": {
    "1":"1级苦瓜大王",
    "2":"2级苦瓜大王",
    "3":"3级苦瓜大王",
    "4":"4级苦瓜大王",
    "5":"5级苦瓜大王",
    "6":"6级苦瓜大王",
    "7":"7级苦瓜大王",
    "8":"8级苦瓜大王",
    "9":"9级苦瓜大王",
    "10":"10级苦瓜大王"
  },
  "fallback":"{n}级苦瓜大王"
}
```

---

## 3. 数据模型与 SQLite DDL

数据库版本：1。使用 `sqflite`。时间统一存毫秒时间戳 `INTEGER`。

```sql
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
);

CREATE UNIQUE INDEX idx_reward_slot ON reward_items(slot_index);

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
);

CREATE TABLE interruption_events (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  type TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  grace_ms INTEGER,
  outcome TEXT
);

CREATE TABLE title_progress (
  id INTEGER PRIMARY KEY CHECK(id = 1),
  max_guada_level INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

初始化写入 `title_progress(id=1, max_guada_level=0)`。

### 3.1 枚举

任务状态：

- `running`
- `success`
- `failed`
- `abandoned`
- `success_pending_reward`（异常兜底，正常不触发）

中断类型：

- `app_background`
- `focus_lost`
- `multi_window`
- `pip`
- `phone_ringing`
- `phone_offhook`
- `screen_off`
- `process_death`

中断结果：

- `returned`
- `timeout`
- `exempt`

设置键：

- `expiry_notification`：`"true"` / `"false"`，默认 `"true"`
- `onboarding_shown`：`"true"` / `"false"`

---

## 4. 任务状态机

### 4.1 任务生命周期

```
idle
  -> startTask()
running
  -> expectedEndAt 到达且无失败 -> success
  -> 普通切后台超过10秒 -> failed
  -> 焦点丢失超过60秒 -> failed
  -> 分屏/画中画 -> failed
  -> 电话/息屏 -> 继续 running
  -> 用户放弃 -> abandoned
  -> 冷启动发现 running -> failed(process_death)
```

### 4.2 开始任务

`startTask(durationMinutes)`：

1. 检查是否已有 `running` 任务；有则跳转任务页。
2. 检查仓库是否有空 `slot_index`；24 格全占则禁止开始，弹窗提示。
3. 从 `duration_rewards.json` 取奖励定义。
4. 生成 `task_sessions`：
   - `status = running`
   - `started_at = now`
   - `expected_end_at = now + durationMinutes * 60 * 1000`
5. 跳转任务页，拦截返回键。
6. 启动中断监听。

### 4.3 任务计时

- 真相是 `expected_end_at`，不是递减 Timer。
- UI Timer 每 200–500ms 刷新剩余时间。
- 每次刷新检查 `now >= expected_end_at`，触发完成。
- 息屏/电话期间计时继续。

### 4.4 完成任务

`completeTask(sessionId)`：

1. 事务开始。
2. 再次检查 `status = running`。
3. 找最小空闲 `slot_index`。
4. 插入 `reward_items`：
   - `definition_id = reward_definition_id`
   - `level = 1`（任务奖励只到普通奖励）
   - `created_at = now`
   - `expire_at = now + 72h`（普通）；特殊为 `null`
   - `source_task_id = sessionId`
5. 更新任务 `status = success`，`ended_at = now`。
6. 事务提交。
7. 取消中断监听。
8. 显示完成动画和奖励。
9. 如果普通奖励，安排过期通知。

异常兜底：完成时若无空格（正常不会，因为开始已检查且任务中不可操作），任务置 `success_pending_reward`，保存 `pending_reward_definition_id`，提示用户清理后领取；领取时再插入奖励。

### 4.5 失败/放弃

- `failTask(reason)`：`status = failed`，`failure_reason`，`ended_at = now`，不发奖励。
- `abandonTask()`：二次确认后 `status = abandoned`，不发奖励。
- 失败后可直接重新开始。

### 4.6 冷启动恢复

App 冷启动时：

1. 查询 `status = running` 的任务。
2. 若存在，全部置为 `failed`，原因 `process_death`。
3. 刷新仓库过期状态。
4. 重排过期通知。

注意：同一进程内从后台返回由中断管理器处理；冷启动才按进程被杀处理。

---

## 5. 中断检测详细逻辑

### 5.1 Flutter 侧

使用 `WidgetsBindingObserver` 监听 `AppLifecycleState`。

- `resumed`：任务页前台。
- `inactive`：失去焦点，可能通知栏/系统弹窗。
- `paused`：进入后台/切应用。
- `detached`：进程可能结束。

### 5.2 Android 原生 MethodChannel

Channel 名：`self_discipline/native_monitor`

事件：

- `screenOff`
- `screenOn`
- `focusLost`
- `focusGained`
- `multiWindowEntered`
- `multiWindowExited`
- `pipEntered`
- `pipExited`
- `phoneRinging`
- `phoneOffhook`
- `phoneIdle`
- `phonePermissionDenied`

方法：

- `startMonitoring()`
- `stopMonitoring()`
- `isPhonePermissionGranted()`
- `requestPhonePermission()`
- `isScreenOn()`

Kotlin 实现：

- `BroadcastReceiver` 监听 `ACTION_SCREEN_OFF` / `ACTION_SCREEN_ON`。
- `onWindowFocusChanged` 发送焦点事件。
- `isInMultiWindowMode` 发送分屏事件。
- `isInPictureInPictureMode` 发送画中画事件。
- `TelephonyCallback`（API 31+）/ `PhoneStateListener` 监听通话状态。
- 权限：`READ_PHONE_STATE`。
- 用户拒绝权限时发送 `phonePermissionDenied`，降级 60 秒宽限。

### 5.3 判定规则

任务运行中：

| 事件 | 处理 |
|---|---|
| `paused` 且非息屏/非电话 | 启动 10 秒宽限；10 秒内 `resumed` 取消；超时 failed |
| `focusLost` 且 Activity 仍前台、非电话/息屏 | 启动 60 秒宽限；返回取消；超时 failed |
| `multiWindowEntered` | 立即 failed |
| `pipEntered` | 立即 failed |
| `phoneRinging` / `phoneOffhook` | 标记电话中，不判失败，计时继续 |
| `phoneIdle` | 清除电话标记 |
| `screenOff` | 标记息屏，不判失败，计时继续 |
| `screenOn` | 清除息屏标记 |
| 冷启动发现 running | failed(process_death) |

宽限期间计时不暂停，只是不立即判失败。宽限 UI 显示“检测到离开，10 秒内返回”或“系统中断，60 秒内返回”。

电话权限拒绝时：来电可能触发 `focusLost`，按 60 秒宽限处理。

---

## 6. 仓库与合成逻辑

### 6.1 仓库加载

- 读取全部 `reward_items`，按 `slot_index` 排序。
- 生成 24 格数组，空格为 null。
- 每次加载、恢复、操作前调用 `refreshExpired`：
  - 过期条件：`expire_at != null && expire_at <= now`。
  - 不修改数据库状态字段，UI 动态显示“已过期”。
- 过期物品不可合成，可移动/交换/删除。

### 6.2 拖拽

`onDrop(sourceSlot, targetSlot)`：

1. 读取源、目标物品。
2. 源为空：忽略。
3. 目标为空：更新源物品 `slot_index = targetSlot`。
4. 目标非空：
   - 任一过期：交换位置。
   - 源为苦瓜且目标为苦瓜：弹确认，确认后合成。
   - 两者 `definition_id` 相同且都有 `nextId`：合成。
   - 其他：交换位置。

### 6.3 合成

事务内：

1. 校验两个物品未过期、存在。
2. 苦瓜：产物 `definition_id = kugua`，`level = a.level + b.level`。
3. 非苦瓜：产物 `definition_id = sourceDefinition.nextId`，`level = 1`。
4. 删除两个原材料。
5. 插入产物到目标格：
   - `created_at = now`
   - 若产物是普通：`expire_at = now + 72h`
   - 否则 `expire_at = null`
6. 若产物是苦瓜：更新 `title_progress.max_guada_level = max(old, product.level)`。
7. 取消两个原材料的过期通知；若产物普通，安排新通知。
8. 提交，播放动画。

### 6.4 删除

- 单个删除：二次确认，删除 DB 记录，取消通知。
- 一键清理过期：确认后删除所有 `expire_at <= now` 的记录，取消通知。
- 删除苦瓜不影响历史最高称号。

### 6.5 满仓

- 开始任务前检查 24 格是否全占。
- 全占则禁止开始，提示清理/合成。
- 过期物品也占格，所以用户必须手动删。

---

## 7. 页面与交互

### 7.1 首页

- 显示称号（历史最高苦瓜等级）。
- 显示 5 个时长卡片：15/30/60/120/240 分钟，对应奖励图标和名称。
- 点击卡片进入确认弹窗：“开始 60 分钟自律，成功获得上海青。期间离开将失败。”
- 开始按钮。
- 若仓库满，顶部提示并禁用开始。
- 底部导航：首页、仓库、设置。

### 7.2 任务页

- 大号倒计时 `HH:MM:SS` 或 `MM:SS`。
- 进度环。
- 当前奖励展示。
- 放弃按钮：二次确认。
- 拦截系统返回键。
- 中断宽限浮层：显示剩余宽限秒数。
- 电话中提示：“通话中，计时继续”。
- 息屏不显示异常。
- 完成：动画 + 奖励卡片 + “已放入仓库”。
- 失败：原因 + “重新开始”。

### 7.3 仓库页

- 6×4 网格。
- 每格显示图标、名称、苦瓜等级角标、普通奖励剩余保质期。
- 过期物品灰色遮罩 + “已过期”。
- 拖拽移动/交换/合成。
- 点击物品打开详情：名称、类型、等级、获得时间、过期时间、删除按钮。
- 顶部按钮：一键清理过期。
- 支持点选两个物品合成：选中第一个高亮，点第二个尝试合成；不可合成提示。

### 7.4 设置页

- 过期通知开关，默认开。
- 导出备份。
- 导入备份。
- 帮助/规则说明。
- 关于/版本。
- 重置数据（危险操作，二次确认）。

### 7.5 新手引导

首次启动展示：
- 选择时长，保持页面。
- 切屏会失败，电话/息屏豁免。
- 奖励会进仓库，普通奖励 3 天过期。
- 两个相同奖励合成下一级。
- 苦瓜可无限合成，称号按历史最高。

---

## 8. 技术架构

### 8.1 依赖建议

```yaml
dependencies:
  flutter_riverpod: ^2.x
  go_router: ^14.x
  sqflite: ^2.x
  path: ^1.x
  path_provider: ^2.x
  uuid: ^4.x
  flutter_local_notifications: ^17.x
  permission_handler: ^11.x
  file_picker: ^8.x
  share_plus: ^9.x
  intl: ^0.19.x
  json_annotation: ^4.x
```

### 8.2 项目结构

```
lib/
  main.dart
  app.dart
  core/
    constants/
    theme/
    utils/
    native/native_monitor.dart
    native/native_events.dart
  data/
    db/app_database.dart
    db/dao/reward_dao.dart
    db/dao/task_dao.dart
    db/dao/settings_dao.dart
    models/
    repositories/reward_repository.dart
    repositories/task_repository.dart
    repositories/settings_repository.dart
  domain/
    entities/
    services/synthesis_service.dart
    services/task_service.dart
    services/expiration_service.dart
    services/title_service.dart
    services/backup_service.dart
    services/notification_service.dart
    services/interruption_manager.dart
  features/
    home/
    task/
    warehouse/
    settings/
    onboarding/
  config/
    config_loader.dart
assets/
  config/rewards.json
  config/duration_rewards.json
  config/titles.json
  rewards/*.png
android/app/src/main/kotlin/.../MainActivity.kt
```

### 8.3 分层

- Repository：只做 DB 读写。
- Service：业务逻辑，事务。
- Riverpod Provider：状态和依赖注入。
- UI：只调用 Service/Provider，不直接写 SQL。
- 原生能力通过 `NativeMonitor` 接口隔离，Android 实现，iOS 以后空实现。

---

## 9. Android 权限与 Manifest

```xml
<uses-permission android:name="android.permission.READ_PHONE_STATE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

- Android 13+ 动态申请通知权限。
- 电话权限动态申请；拒绝则降级。
- 不需要前台服务；任务页必须前台。
- 不需要精确闹钟；过期通知用普通本地通知即可。若需更准，可加 `SCHEDULE_EXACT_ALARM`，首版可不加。

---

## 10. 通知

- 过期通知默认开启。
- 普通奖励入仓/合成刷新时安排通知：
  - `id = item.id.hashCode() & 0x7fffffff`
  - 时间 = `expire_at`
  - 标题：“奖励即将过期”
  - 内容：“你的{名称}将在48小时内过期，记得合成。”
  - 实际在 `expire_at - 12h` 提醒一次，可选。
- 删除/合成/清理时取消对应通知。
- 关闭开关时取消全部过期通知。
- 导入备份后取消全部并重排。

---

## 11. 备份格式

导出：

```json
{
  "schemaVersion": 1,
  "exportedAt": 1730000000000,
  "appVersion": "1.0.0",
  "data": {
    "settings": {
      "expiry_notification": "true",
      "onboarding_shown": "true"
    },
    "titleProgress": {
      "maxGuadaLevel": 3
    },
    "rewardItems": [
      {
        "id": "uuid",
        "definitionId": "cong",
        "level": 1,
        "slotIndex": 0,
        "createdAt": 1730000000000,
        "expireAt": 1730259200000,
        "sourceTaskId": "uuid",
        "effectsJson": null,
        "locked": 0
      }
    ],
    "taskSessions": [
      {
        "id": "uuid",
        "durationMinutes": 60,
        "rewardDefinitionId": "shanghaiqing",
        "startedAt": 1730000000000,
        "expectedEndAt": 1730003600000,
        "endedAt": 1730003600000,
        "status": "success",
        "failureReason": null,
        "pendingRewardDefinitionId": null,
        "createdAt": 1730000000000
      }
    ]
  }
}
```

导入规则：

1. 选择文件，读取 JSON。
2. 校验 `schemaVersion <= 当前支持版本`，否则提示升级。
3. 校验 `slotIndex` 0–23 且唯一。
4. 校验 `definitionId` 存在；未知则中止并提示。
5. 二次确认“将替换全部本地数据”。
6. 事务清空并写入。
7. 按当前时间重新判断过期。
8. 取消全部通知并重排。
9. 导入完成提示。

---

## 12. 关键边界与异常

- 任务中仓库数据不应变化；若异常变化导致满仓，走 `success_pending_reward`。
- 用户改系统时间：不处理防作弊，按本机时间。
- 息屏时 Timer 可能暂停：完成判断用 `expected_end_at`，恢复时补判。
- 电话权限拒绝：降级 60 秒宽限。
- 导入未知奖励 ID：中止，不部分导入。
- 导入重复 slot：中止。
- 过期物品不自动删除。
- 删除苦瓜不降历史称号。
- 苦瓜等级无上限；UI 显示 `N级苦瓜`。
- 配置校验失败：启动报错页，提示配置错误。

---

## 13. 测试与验收

### 13.1 单元测试

- 5 个时长映射正确。
- 完整升级链每一步正确。
- 普通+普通刷新 72 小时。
- 普通+特殊永久。
- 苦瓜 1+1=2，2+3=5。
- 过期判断边界：`expire_at == now` 算过期。
- 称号历史最高不被删除降低。
- 备份导出导入 roundtrip。
- 导入 schemaVersion 迁移。

### 13.2 Widget 测试

- 仓库 24 格渲染。
- 拖拽移动、交换、合成。
- 过期显示。
- 满仓禁用开始。
- 任务页倒计时和放弃确认。

### 13.3 手工验收

1. 15 分钟任务成功获得葱，72 小时后过期。
2. 两个葱合成香菜，香菜过期时间刷新。
3. 两个大白菜合成芹菜，永久。
4. 两个丝瓜合成 1 级苦瓜，称号“1级苦瓜大王”。
5. 1 级苦瓜 + 2 级苦瓜 = 3 级苦瓜，称号“3级苦瓜大王”。
6. 删除 3 级苦瓜，称号仍为“3级苦瓜大王”。
7. 任务中切后台 9 秒返回成功；11 秒失败。
8. 下拉通知栏 59 秒返回成功；61 秒失败。
9. 来电响铃/通话不失败。
10. 息屏 10 分钟不失败，回 App 继续。
11. 杀后台后重开，运行中任务判失败。
12. 仓库满禁止开始。
13. 过期物品占格，手动删除。
14. 一键清理过期。
15. 导出备份，清数据，导入恢复。
16. 关闭过期通知后不再提醒。

---

## 14. 开发顺序

1. 创建 Flutter Android 项目，配置依赖、主题、路由。
2. 加载三份 JSON 配置，写配置校验。
3. 建 SQLite 表、DAO、Repository。
4. 实现奖励定义、仓库加载、过期刷新。
5. 实现仓库页 24 格、拖拽移动/交换、合成事务。
6. 实现任务页、开始任务、倒计时、完成/失败/放弃。
7. 实现中断管理器：Flutter 生命周期 + Android 原生事件。
8. 实现电话权限、息屏、分屏、画中画检测。
9. 实现过期通知。
10. 实现备份导出/导入。
11. 实现称号、帮助、设置。
12. 写单元测试和手工验收，修边界。

---

## 15. 给 DSH 的直接执行指令

> 请按本规格实现 Flutter Android App。先完成配置层、SQLite 数据层、任务状态机、仓库合成与过期逻辑；再完成 Android 原生中断监听、通知和备份。所有奖励链、时长映射、称号必须从 `assets/config` 读取，不得写死。代码按 `core/data/domain/features` 分层，业务逻辑放 Service 并用事务保证合成原子性。每完成一个模块给出可运行代码和测试。遇到规格未覆盖处，优先选择不增加新机制、保持本地单机、配置化可扩展的实现。

以上可以直接交给 DSH 开始开发。