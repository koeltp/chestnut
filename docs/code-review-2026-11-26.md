# 项目复盘（2026-11-26）

基于对数据层、UI 层、工程外围的全面调研得出的结论。本文档只记录问题与计划，不含具体实现。

## 一、做得不好的地方（按严重度排序）

### 1. image_edit_page 是全项目风险最高的文件

文件：`lib/widgets/image_edit_page.dart`（约 1392 行）

五类互相独立的职责挤在一个文件里，边界清晰但从未拆开：

| 职责 | 位置（行号） | 说明 |
| --- | --- | --- |
| 裁剪算法 | L180-220 | 归一化裁剪框切图、亮度校验、异步裁剪流程 |
| 标注烘焙 | L452-466 | 未烘焙标注绘制到底图，避免几何操作后笔迹错位 |
| 位图有效性校验 | L466 前后 | `_probeImage/_swapBase`，烘焙结果多维度校验 |
| 手势命中与拖拽 | L740-795 | `onTapUp/onPanDown` 等全套手势、归一化坐标命中测试 |
| 自定义绘制 | `_EditPainter` | 在 build 中创建 |

历史 bug（手势坐标错位、烘焙黑图）集中出现在手势区与烘焙区。文件越大，每次改动的爆炸半径越大。

### 2. budget_page 的流嵌套与 UI 混逻辑

文件：`lib/pages/budget/budget_page.dart`（约 1226 行）

- L455-488：连续嵌套三层 `StreamBuilder`，builder 内还做 map 转换；
- `_clearAllBudgets` 等持久化写操作直接长在页面里；
- 月度预算、分类预算、summary 四路流的组装逻辑与 UI 渲染缠在一起。

### 3. location_picker 把整条定位链内联进页面（已处理）

文件：`lib/pages/add_bill/location_picker_page.dart`（原约 1005 行）

地图 marker 渲染（`_renderPin/_renderDot`）、定位流程（`_locateAndMove/_applyLocation`）、附近 POI 加载（`_loadNear`）、搜索防抖（`_search`）全部内联。页面既是 UI 又是高德 SDK 的粘合层。

**处理结果**：拆出三个独立模块（与页面同目录）：

- `location_pick_controller.dart` — 附近列表 + 搜索 + 请求代数竞态控制（ChangeNotifier，含 `LocationEntry` 模型与 `distanceMeters` 共用距离函数）；
- `system_locator.dart` — 权限检查 / 缓存位置 / 实时定位的全部 Geolocator 交互（10 分钟缓存新鲜期、12 秒超时、forceLocationManager、WGS-84 → GCJ-02 转换）；
- `map_marker_icons.dart` — 图钉与 GPS 蓝点的离屏 Canvas 位图绘制。

页面保留地图交互状态机（移图 / 拖动判定 / Marker 缓存）与 UI 构建。另将 `_select` 与 `_createCustom` 中两段重复的逆地理补全合并为 `_resolveFullAddress`。

### 4. 图片编辑入口样板重复（已处理）

`Navigator.push(ImageEditPage)` + 取回 `Uint8List` 的导航样板在三个调用点各写了一遍：`bill_detail_sheet.dart`、`bill_image_sheet.dart`、`debt_note_edit_page.dart`（调研初稿误记为两处）。

**处理结果**：在 `image_edit_page.dart` 中新增顶层入口函数 `pushImageEdit(context, sourcePath)`，三处调用统一替换；后续落盘逻辑（暂存换文件 / 删旧存新替换 / 触发上传）因仓储接口各异，保持调用方自理，不做强行抽象。

### 5. 关键复杂度没有落点

`docs` 目录几乎为空，而净值走势的窗口/刻度规则、手势坐标系约定、烘焙对齐要求等全项目最复杂易错的规则，只存在于会话记忆中，代码与仓库文档均无记录。换会话、换工具、或半年后回看都需要重新考古。

### 6. UI 层测试空白

数据层有 1010 行测试兜底（`test/asset_repository_test.dart`），但历史 bug 最密集的流管理、手势、烘焙区域零 widget test。这些历史 bug 均值得沉淀为回归用例。

## 二、做得好的地方

- **数据层扎实**：分层边界干净（database / repository / service / provider 各司其职）；迁移幂等且降级前先备份重建；金额统一分单位存储；分页用增大 limit 避免 offset 错位；备份用 `VACUUM INTO` 避开写事务冲突。
- **stream_cache_mixin**（`lib/widgets/stream_cache_mixin.dart`）：系统性解决了 `StreamBuilder` 重复订阅问题。
- **竞态处理**：`location_picker_page.dart` 用请求代号丢弃过期定位/搜索响应，避免旧数据覆盖新数据。
- **工程规范**：严格 lint（`unawaited_futures` 等）、CI 锁定 Flutter 3.47.8 并跑 analyze + test、Android debug 用 `.debug` 后缀隔离生产数据。

## 三、处理计划

| 序号 | 问题 | 状态 |
| --- | --- | --- |
| 1 | image_edit_page 拆分（裁剪/烘焙/校验/手势/绘制独立模块） | 待处理 |
| 2 | budget_page 流组装与持久化逻辑外移 | 待处理 |
| 3 | location_picker 定位/搜索/POI 逻辑拆出 | 已完成（2026-11-26） |
| 4 | 图片编辑入口样板统一 | 已完成（2026-11-26） |
| 5 | 复杂规则沉淀进 docs（净值走势、手势坐标、烘焙对齐） | 待处理 |
| 6 | UI 层回归用例补齐 | 待处理 |
