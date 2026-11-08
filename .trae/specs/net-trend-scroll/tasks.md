# 任务清单：净值走势横向平移缩放

## [x] T1 日档窗口 7 天 → 15 天
- 文件：`lib/pages/asset/asset_chart_cards.dart`
- 位置：`_NetTrendCardState._displayPoints` 的 `_TrendRange.day` 分支
- 改动：`now.subtract(const Duration(days: 6))` → `const Duration(days: 14)`，同步更新注释（含今天共 15 个自然日）

## [x] T2 全部档取消按年抽稀
- 文件：同上，`_TrendRange.all` 分支
- 改动：`return [..._lastPerPeriod(fresh, 4), ...end]` → `return [...fresh, ...end]`

## [x] T3 接入横向缩放/平移
- 文件：同上，`_NetTrendCardState`
- 改动：
  1. 新增 `final TransformationController _transform = TransformationController();` 与 `double _scale = 1.0;`
  2. `initState` 注册监听（写入 `_scale` + `setState`），`dispose` 移除监听并释放控制器
  3. `LineChart(...)` 增传 `transformationConfig: FlTransformationConfig(scaleAxis: FlScaleAxis.horizontal, minScale: 1, maxScale: 3, panEnabled: true, scaleEnabled: true, transformationController: _transform)`

## [x] T4 底部标签按可视密度自适应
- 文件：同上
- 改动：
  1. `labelStep` 由 `points.length` 改为 `visibleCount = points.length / _scale` 计算，`max(1, (visibleCount / 5).ceil())`
  2. `_dateLabel` 增加 `all` 档按 `visibleCount` 分支（>60 → `yyyy`，>12 → `yy-MM`，否则 `MM-dd`）

## [x] T5 静态检查
- 执行：`flutter analyze`（`d:\work\code\Chestnut`），确认无新增告警

## T6 真机验收（用户自测或联调）
- 日档 15 点；全部档为全部历史点
- 四档双指放大后横向拖动，左轴刻度固定
- 放大后底部标签约 5 个且不重复
- 长按 tooltip 正常；mask 模式左轴隐藏
- 重点观察：在图表区域上下滑动能否正常滚动页面（若被吞，记录并回报，按 spec 回退方案决策）
