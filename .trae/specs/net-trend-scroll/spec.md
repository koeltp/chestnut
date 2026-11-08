# 净值走势图横向平移缩放

## 背景与目标

资产页「净值走势」卡片当前把全部数据点固定塞进一屏宽度（`SizedBox(height: 180)`），
点数一多曲线就被压扁、日期标签互相挤。用户要求：

1. 日档默认展示最近 15 个自然日（现为 7 天）；
2. 日 / 月 / 年 / 全部四档都支持横向平移 + 缩放；
3. 「全部」档不再按年抽稀，展示全部历史日级快照点。

## 现状（已确认）

文件：[lib/pages/asset/asset_chart_cards.dart](file:///d:/work/code/Chestnut/lib/pages/asset/asset_chart_cards.dart)

- `_displayPoints`：
  - `day`：`now - 6 天` 起，含今天共 7 点；
  - `month`：最近 12 个自然月，按 `yyyy-MM` 取段末；
  - `year`：最近 12 个自然年，按 `yyyy` 取段末；
  - `all`：`_lastPerPeriod(fresh, 4)`，按年取段末（即每年 1 点）。
- `_chart`：`LineChart(LineChartData(...))`，未传 `transformationConfig`，无任何手势缩放能力；
  `labelStep = (points.length / 5).ceil()`，底部标签按 `idx % labelStep` 抽稀。

## 依赖能力（fl_chart 1.3.0，已核实包内源码）

- `LineChart` 构造参数支持 `transformationConfig`（`line_chart.dart` L25、L63）。
- `FlTransformationConfig` 字段：`scaleAxis`（`FlScaleAxis.horizontal`）、`minScale`、`maxScale`、
  `panEnabled`、`scaleEnabled`、`trackpadScrollCausesScale`、`transformationController`。
- `scaleAxis != none` 时，`AxisChartScaffoldWidget` 用 `CustomInteractiveViewer`
  （`clipBehavior: Clip.none`、`panEnabled`、`scaleEnabled`、`minScale`、`maxScale`）包裹图表，
  并把经逆变换算出的 `chartVirtualRect` 传给图表与坐标轴标题（坐标轴标题渲染在变换外层，不会滚走）。
- `scaleAxis: horizontal` 时，x 轴按可视窗口重算，y 轴范围与左轴刻度保持固定。
- `CustomInteractiveViewer` 未暴露 `panAxis`（默认 `PanAxis.free`），`boundaryMargin` 为 `EdgeInsets.zero`、
  `constrained: true` —— 内容在 1x 恰好铺满，此时平移被钳制（必须先放大才能横向拖动）。
- 开启缩放后 `render_base_chart.dart` 不再向图表注册 pan 识别器，拖动交给 InteractiveViewer；
  点击 / 长按仍可触发 tooltip。

## 变更设计

### 1. 数据窗口（`_displayPoints`）

- `day`：`cutoff = now - 14 天`（含今天最多 15 个自然日），其余逻辑保留（与实时同日的历史点让位）。
- `all`：改为 `return [...fresh, ...end]`，即全部历史日级快照 + 今日实时点，不再按年抽稀。
- `month` / `year`：保持不变（12 个月 / 12 年），但同样获得平移缩放能力。

### 2. 手势（`_chart`）

- `_NetTrendCardState` 新增字段：

```dart
final TransformationController _transform = TransformationController();
double _scale = 1.0;
```

- `initState` 中注册监听：把 `_transform.value.getMaxScaleOnAxis()` 写入 `_scale` 并 `setState`，
  让底部标签抽稀随缩放实时重算；`dispose` 中移除监听并 `dispose()` 控制器。
- `LineChart` 增传：

```dart
transformationConfig: FlTransformationConfig(
  scaleAxis: FlScaleAxis.horizontal,
  minScale: 1,
  maxScale: 3,
  panEnabled: true,
  scaleEnabled: true,
  transformationController: _transform,
),
```

### 3. 底部日期标签自适应（`_chart`）

- `visibleCount = points.length / _scale`（近似可视点数，`_scale >= 1`）。
- `labelStep = max(1, (visibleCount / 5).ceil())`，替换现有 `(points.length / 5).ceil()`。
- 标签格式（`_dateLabel` 增加按可视密度的分支，仅 `all` 档变化）：
  - `day` → `MM-dd`；`month` → `yy-MM`；`year` → `yyyy`（均保持现状）；
  - `all` → `visibleCount > 60` 用 `yyyy`；`12 < visibleCount <= 60` 用 `yy-MM`；
    `visibleCount <= 12` 用 `MM-dd`。
- 其余（首/末标签特判、`idx` 越界保护、单点 ±1 轴、左轴整刻度、tooltip、模糊模式隐藏左轴）全部保留。

## 交互约定

- 1x 时曲线铺满一屏，拖动无效；**需先双指放大（最多 3x）再横向平移**。这是 fl_chart 内置机制，不额外削弱。
- 左轴刻度固定不随横向平移移动；底部标签按可视窗口重算。
- 长按/点击查看日期与金额的 tooltip 仍可用。

## 风险与验证项

- **纵向滚动冲突（需真机确认）**：图表区域被 `CustomInteractiveViewer` 接管手势，
  在卡片上下滑动页面时可能被图表吞掉。若影响明显，回退方案为「仅移除 transformationConfig」，
  由用户确认后再决定是否改用自定义横向拖动窗口。
- 全部档点数可能达数百，首屏曲线必然被压扁，属预期行为（放大后可见细节）。

## 验收标准

1. `flutter analyze` 无新增告警。
2. 日档显示最近 15 天（含今天，最多 15 个点）。
3. 全部档点数为历史全部日级快照数（不再一年一点）。
4. 四档均可双指横向放大后左右拖动；左轴刻度不随拖动改变。
5. 底部日期标签在放大后仍保持约 5 个、且不重复堆叠。
6. 模糊（mask）模式下左轴数值仍隐藏；长按 tooltip 正常。
