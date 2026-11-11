# 新手接手开发指南

这份文档面向第一次接触本仓库的开发者，目标是**第一天能跑起来、第一周能独立改一处**。
它只写这个仓库特有的东西；Flutter / Provider / drift 的通用用法请自行查阅官方文档。

配套材料：

- 功能与截图：[README](../README.md)
- 真机无线调试、验证命令：[development.md](development.md)
- 发版流程：[RELEASING.md](../RELEASING.md)
- 版本变更：[CHANGELOG.md](../CHANGELOG.md)

---

## 1. 五分钟跑起来

需要 Flutter SDK（Dart ^3.13）与 Android 工具链，只支持 Android。

```bash
flutter pub get
flutter run --debug
```

首次启动会先进入隐私政策同意页，同意后才初始化地图 SDK 并进入主界面。
启动过程还会做备份恢复、数据库健康探测和临时文件清理，所以冷启动偶尔比热启动慢一点，属于预期行为。

调试命令（二维码配对、adb 直连）见 [development.md](development.md)。

---

## 2. 一条数据的生命周期

看懂下面三条链路，就理解了这个项目的分层。三条链分别是"写入、列表、图表"。

### 2.1 记一笔：从键盘到数据库

```
pages/add_bill/add_bill_page.dart （界面，拆成 .save/.rows/.chips/.transfer 等 part 文件）
  └─ pages/add_bill/add_bill_validation.dart   validateBillDraft：保存前校验
      └─ providers/bill_provider.dart          addBill
          └─ data/repositories/bill_repository.dart  addBill（db.transaction 内写账单 + 关联图片 + 资产流水）
              └─ data/tables/bills.dart        bills 表
```

### 2.2 首页列表：为什么写完自动刷新

```
pages/home/home_page.dart
  └─ providers/bill_provider.dart      summaryStream / homeSummaryStream
      └─ data/repositories/bill_repository.dart  watchBillsInMonth / watchMonthSummary
          └─ drift 的 watch()：表一变，查询自己重新跑一遍并把新结果推给 StreamBuilder
```

**全链路没有任何"手动刷新"调用。** 如果写完数据库界面没变，问题一定在流没接上，而不是渲染。

### 2.3 净值走势：从快照到曲线

```
data/tables/assets.dart（快照）→ data/net_value_agg.dart 预聚合
  └─ data/repositories/asset_repository.dart  netHistoryStream / ensureNetDaysCurrent
      └─ providers/asset_provider.dart        netHistoryStream
          ├─ pages/asset/asset_chart_cards.dart   卡片：只查"最近一屏"的点数
          └─ pages/asset/net_trend_full_page.dart 全屏：查全量，靠横滑看更早
              └─ pages/asset/net_trend_data.dart  纯函数：窗口点数 / 刻度步长 / 日·月·季·年聚合
                  └─ pages/asset/net_trend_chart.dart  fl_chart 绘制
```

净值曲线是仓库里逻辑密度最高的地方：**所有可计算的规则都在 `net_trend_data.dart` 里，且全是不依赖 `BuildContext` 的纯函数**，因此可以直接写单测。改图表前先读对应的测试文件。

---

## 3. 分层与目录职责

| 目录 | 放什么 | 不放什么 |
|---|---|---|
| `data/tables/` | drift 表定义、字段与约束 | 业务判断 |
| `data/repositories/` | SQL 查询、事务、数据聚合 | UI、`BuildContext` |
| `data/` 根目录 | 预聚合等数据层纯逻辑（如 `net_value_agg.dart`） | 页面状态 |
| `providers/` | 跨页面共享的 `ChangeNotifier` 状态 | 直接拼 SQL |
| `pages/` | 页面与页面内纯计算（`stats_logic.dart`、`stats_query.dart`、`net_trend_data.dart`） | 全局单例、跨页面状态 |
| `widgets/` | 可复用组件（`empty_state_card.dart`、`loading_placeholder.dart`、`stream_cache_mixin.dart`） | 只被一个页面用一次的私有组件（就留在页面里） |
| `services/` | 与外部系统交互：备份、更新、地图、云存储、导入导出 | 页面跳转 |
| `theme/` `utils/` `models/` | 颜色与尺寸常量、日期金额工具、枚举与视图模型 | 业务状态 |

**放错层的判断方法**：

1. 依赖 `BuildContext` / 有 `setState` → 留在 `pages/` 或 `widgets/`；
2. 只跟数据库打交道，不关心界面 → `data/repositories/`；
3. 不依赖任何 Flutter 对象、输入输出都是数据 → 抽成纯函数，放到 `pages/xxx/xxx_logic.dart` 或 `utils/`，并补测试。

---

## 4. 状态与流的三条铁律

这三条能挡掉本仓库 80% 的"改了没反应 / 旧数据残留 / 偶发崩溃"。

### 4.1 不要在 `build` 里新建 Stream

每次 `build` 都 `factory()` 一次，`StreamBuilder` 就会反复取消 / 重订阅，首帧全量查询被重复执行。用 [StreamCacheMixin](../lib/widgets/stream_cache_mixin.dart)：

```dart
final stream = ensureStream(
  'flow-${period}-${month.year}-${month.month}', // key 必须包含查询条件
  () => repo.watchHomeFlow(period, month),
);
return StreamBuilder(stream: stream, ...);
```

查询条件变化时要让缓存失效（换 key 或调 `invalidate`），否则会一直用旧条件的流。

### 4.2 drift 的流是单订阅

同一个流实例只能被一个 `StreamBuilder` 监听，第二处 `listen` 会抛：

```
Bad state: Stream has already been listened to
```

多处共用时要**共用同一个实例**（`ensureStream` 缓存的就是这个），而不是各自 `repo.watchXxx()`。

### 4.3 换流时 `StreamBuilder` 会保留旧快照

`StreamBuilder` 换了新的 `stream` 但新流还没出数据时，`snapshot.data` 仍是旧流的结果。表现是"切了月份，列表还是上个月的"。

修复方式：给 `StreamBuilder` 加随查询变化的 key，强制重建元素：

```dart
StreamBuilder<List<Bill>>(
  key: ValueKey(query.fingerprint),
  stream: stream,
  ...
)
```

同时 builder 内要按顺序判断：`hasError` → 错误占位；`!hasData` → 加载占位；最后才是内容。占位组件统一用 [loading_placeholder.dart](../lib/widgets/loading_placeholder.dart) 里的 `LoadingPlaceholder` / `ErrorPlaceholder`。

---

## 5. 启动链（`lib/main.dart`）

启动顺序是有约束的，改动前先看清注释。关键顺序：

1. `ErrorWidget.builder` 换成白底友好错误页；
2. `BackupService().restoreIfNeeded()` —— **必须在数据库首次打开之前**完成文件替换；
3. 清理上次会话的导出临时文件、图片暂存目录；
4. 预加载 `SharedPreferences`；
5. 已同意隐私政策时声明高德 SDK 合规状态；
6. `checkDatabaseHealth()`，库损坏则进兜底页，不注入数据库依赖；
7. 每日自动备份（库不健康时跳过）；
8. `runApp`。

几条结构性约束：

- `MultiProvider` 必须包在 `MaterialApp` 之上，否则 `push` 出的二级页面找不到 Provider；
- Provider 的注册顺序就是依赖顺序，`create` 里只能 `read` 前面已注册的；
- 锁屏遮罩挂在 `MaterialApp.builder` 上，位于 `Navigator` 之上；
- 隐私同意前不能做任何联网行为和第三方 SDK 初始化。

新增启动期任务时，先回答两个问题：**同意隐私政策前能不能跑？数据库还没打开时能不能跑？**

---

## 6. 改代码的标准动作

```bash
dart format lib test          # 1. 格式化
flutter analyze               # 2. 静态检查，要求 0 issue
flutter test                  # 3. 全量单测
flutter test test/perf_baseline_test.dart   # 4. 改性能相关时跑基线，看毫秒数对比
```

然后真机验证。**改了数据流、图表窗口、`late` 初始化的对象，必须 hot restart**：`hot reload` 不会重建流、不会换掉 `initState` 里的订阅，表现是"代码明明改了、界面没变"。

提交前自检：

- [ ] `flutter analyze` 无 issue
- [ ] `flutter test` 全绿
- [ ] 涉及表格改动时补了迁移测试
- [ ] 涉及纯函数改动时补了单测
- [ ] 真机走过一遍受影响的路径

---

## 7. 高风险区

| 区域 | 规则 | 相关文件 / 测试 |
|---|---|---|
| 数据库结构 | 加表/加列必须 `schemaVersion + 1` 并写迁移，迁移前自动备份；每次迁移补一条测试 | `data/database.dart`、`test/migration_v9_test.dart` |
| 净值走势 | 点不抽稀，一屏点数 = 绘图区宽度 ÷ 20dp；刻度按标签实测宽度算容量；卡片只查窗口点数，全屏查全量 | `pages/asset/net_trend_data.dart`、`test/net_trend_density_test.dart`、`test/net_trend_points_test.dart` |
| 备份与恢复 | 涉及数据库文件替换，只能在数据库打开前执行 | `services/backup_service.dart` |
| 云同步 | 上传失败要留给下次启动/回前台重试，不要吞掉状态 | `test/image_sync_test.dart` |
| 底部安全区 | 底部 inset 只在 `main_page.dart` 的 `BottomAppBar` 处理一次；页面统一 `SafeArea(bottom: false)` | `lib/pages/main_page.dart` |
| 金额 | 一律 `int` 分存储，显示时才转元，不用浮点入库 | `utils/money_util.dart`、`test/money_util_test.dart` |
| 分类图标 | 图标存码点、运行时渲染；发布构建必须关闭图标树摇 | README「发布构建」 |

---

## 8. 第一个任务菜单

按难度递增，每个都能在半天内完成，并且不碰数据结构。

### 任务一：补一条边界测试（最安全）

- 改哪：`test/money_util_test.dart`
- 做什么：给 `utils/money_util.dart` 里某个换算加一个边界用例（负数、0、超大金额、四舍五入临界值）
- 怎么验：`flutter test test/money_util_test.dart`
- 学到什么：测试写法、金额口径

### 任务二：给首页空状态加一句副文案

- 改哪：`lib/pages/home/home_page.dart`（约 294 行调用处）+ `lib/widgets/empty_state_card.dart`
- 做什么：给"这个月还没有账单"的空状态补一句引导文案
- 怎么验：真机切到没有账单的月份查看；跑 `flutter test test/empty_state_card_test.dart`
- 学到什么：通用组件与页面参数、widget 测试

### 任务三：给设置页某个入口补说明文字

- 改哪：`lib/pages/settings/settings_page.dart`
- 做什么：给一个功能入口加副标题，说明它做什么、数据存在哪
- 怎么验：真机查看"我的"页；确认长文案不换行截断
- 学到什么：设置项结构、`theme/app_dimens.dart` 的间距规范

---

## 9. 排错速查

| 现象 | 大概率原因 |
|---|---|
| `Bad state: Stream has already been listened to` | 同一个单订阅流被两处 `listen`，改用 `ensureStream` 共用实例 |
| `Provider not found` | 二级页面在 `MultiProvider` 之外；或 Provider 注入在 `home` 内部 |
| 代码改了界面没变 | `hot reload` 没换流/没换订阅，改用 hot restart |
| 切换筛选条件后列表还是旧数据 | `StreamBuilder` 缺少随条件变化的 `ValueKey` |
| 改表后报 `no such column` | 忘了 `schemaVersion + 1` 或没写迁移 |
| 发布包图标变成方块 | 构建时漏了 `--no-tree-shake-icons` |
| 图表窗口点数不对 | 改的是常量而不是 `net_trend_data.dart` 里的计算；先跑密度测试 |

遇到重复失败时不要硬试，先跑一遍 `flutter analyze` 和对应的定向测试，多数问题在那里就有答案。
