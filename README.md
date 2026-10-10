<p align="center">
  <img src="assets/images/logo.png" width="96" height="96" alt="栗子记账 Logo">
</p>

<h1 align="center">栗子记账 Chestnut</h1>

<p align="center">
  一款无广告、无账号、数据完全本地的 Android 记账 App
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter">
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android">
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.0-orange">
</p>

<p align="center">
  <a href="https://www.taipi.top/downloads/chestnut-1.0.0-arm64.apk">⬇️ 下载 APK（arm64-v8a）</a>
  &nbsp;·&nbsp;
  <a href="https://www.taipi.top/docs/article/%E6%A0%97%E5%AD%90%E8%AE%B0%E8%B4%A6.html">介绍文章</a>
  &nbsp;·&nbsp;
  <a href="https://www.taipi.top/docs/chestnut/privacy.html">隐私政策</a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">更新日志</a>
</p>

---

## 特性

- **快速记账**：收支一键切换、自定义数字键盘、小数金额、"再记一笔"连记不打断；备注、改期、复制、删除齐全
- **两级分类**：内置常用收支分类，支持增删改、层级互转、跨组移动、拖拽排序；数百个 Material 图标与分类色板，无图标时自动取名称首字
- **统计分析**：分类占比饼图（标签避让、可拖动旋转）、收支趋势柱状图（带去年同期对比）；月 / 年 / 全部维度、关键词与日期区间筛选
- **预算管理**：月度总预算 + 一级分类预算；80% 用量提醒、超支提示、日均可用金额、一键沿用上月预算
- **记账定位**：记账流程内置完整地图选点（拖图选点、附近 POI、地点搜索、跨城市补记）；账单详情位置可一键跳转高德 / 百度 / 腾讯 / 谷歌地图
- **数据自主**：账目 100% 存本机 SQLite，支持完整数据库快照导出 / 恢复、CSV 导出、升级降级自动备份
- **隐私安全**：PIN + 安全问题密码锁、指纹 / 面容快捷解锁；无广告、无推送、无账号、无统计 SDK
- **应用内更新**：有新版本自动提示，应用内下载（进度展示 + SHA-256 双校验）后拉起系统安装器

## 截图

<p>
  <img src="https://www.taipi.top/img/chestnut/add-bill.jpg" width="22%" alt="记一笔">
  <img src="https://www.taipi.top/img/chestnut/categories.jpg" width="22%" alt="分类管理">
  <img src="https://www.taipi.top/img/chestnut/stats.jpg" width="22%" alt="统计">
  <img src="https://www.taipi.top/img/chestnut/budget.jpg" width="22%" alt="预算">
</p>
<p>
  <img src="https://www.taipi.top/img/chestnut/location-picker.jpg" width="22%" alt="地图选点">
  <img src="https://www.taipi.top/img/chestnut/backup.jpg" width="22%" alt="备份与恢复">
</p>

> 截图为应用内实际界面，更多介绍见[博客文章](https://www.taipi.top/docs/article/%E6%A0%97%E5%AD%90%E8%AE%B0%E8%B4%A6.html)。

## 技术栈

| 方面 | 选型 |
|------|------|
| 框架 | Flutter / Dart 3，Material 3，全中文本地化 |
| 状态管理 | Provider |
| 本地数据库 | drift（类型安全 SQLite ORM），响应式 Stream 驱动 UI |
| 图表 | fl_chart（自绘饼图标签与同比标注） |
| 地图定位 | 高德地图 SDK + Web 服务，geolocator / geocoding，GCJ-02 坐标 |
| 安全 | local_auth 生物识别，crypto 加盐哈希 |
| 数据与分享 | file_picker（SAF）、share_plus、open_filex、path_provider |
| 版本更新 | package_info_plus + http 流式下载，清单托管于个人站点 |

工程要点：金额一律以**分**为单位整数存储；分类图标码点入库、运行时渲染（发布构建需关闭图标树摇）；数据库从干净的 v1 基线起步，结构变更走增量迁移并在迁移前自动 VACUUM 备份。

## 目录结构

```
lib/
├── data/            # drift 数据库、表定义与仓储层
├── models/          # 枚举与汇总视图模型
├── pages/           # 页面：记账、首页、统计、预算、设置、锁屏等
├── providers/       # Provider 状态
├── services/        # 高德服务、备份、CSV 导出、应用更新
├── theme/           # 颜色、尺寸、主题
├── utils/           # 金额、日期、密码哈希等工具
└── widgets/         # 通用组件（账单详情、键盘、帮助面板、更新弹窗等）
```

## 运行

需要已安装 Flutter SDK（Dart ^3.13）与 Android 工具链：

```bash
flutter pub get
flutter run --release
```

地图功能使用高德开放平台服务，需要替换为你自己申请的 Key：

- Android 平台 Key：`android/app/src/main/AndroidManifest.xml`（定位 SDK）与 [amap_service.dart](lib/services/amap_service.dart) 的 `androidMapKey`（地图 SDK）
- Web 服务 Key：[amap_service.dart](lib/services/amap_service.dart) 的 `_webKey`（POI 搜索 / 逆地理 / 地理编码）

> 注意：仓库中的 Key 为作者自用 Key，随源码公开。Android Key 与签名证书指纹绑定无法盗用；Web 服务 Key 为客户端直连，请注意配额监控，自行构建时请替换为自己的 Key。不配置地图 Key 不影响除地图外的记账功能。

## 真机无线调试（二维码配对）

不想插数据线时，可用 [adb-wifi-qr](https://pypi.org/project/adb-wifi-qr/) 在终端生成二维码，手机扫码完成配对：

```bash
# 安装（Python 3.8+，需 Android platform-tools 31+）
pip install adb-wifi-qr

# 生成二维码并在配对后自动连接
adb-wifi-qr --connect
```

手机端操作：**设置 → 系统管理 → 开发者选项 → 无线调试 → 使用二维码配对设备**，扫描终端中的二维码即可。

前提：手机系统 Android 11+，且手机与电脑在同一 Wi-Fi 下。配对只需一次；无线调试的连接端口每次开启会变化，重新打开后重跑上述命令，或用 `adb mdns services` 查到连接端口后 `adb connect <IP:端口>`。扫码不成功时可把终端调大、换深色背景，或加 `--timeout 120` 延长等待时间。

## 发布构建

只打 arm64 架构（近十年安卓手机均为该架构）：

```bash
flutter build apk --release --no-tree-shake-icons --split-per-abi --target-platform android-arm64
```

产物：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。签名证书在 `android/key.properties` 中配置（文件不入库）。

## 权限说明

| 权限 | 用途 | 是否必须 |
|------|------|----------|
| 网络 | 地图瓦片 / POI 搜索、检查应用更新 | 否 |
| 精确定位 | 记账定位时展示当前位置周边 | 否，默认关闭 |
| 生物识别 | 指纹 / 面容快捷解锁 | 否 |
| 安装未知来源应用 | 应用内更新后拉起系统安装器 | 仅更新时 |

## 隐私

所有账目、备注、位置数据仅保存在应用私有目录，不经过任何服务器；定位仅在你主动使用地图选点时触发，无后台位置上报。完整说明见[隐私政策](https://www.taipi.top/docs/chestnut/privacy.html)（App 内"关于 → 隐私政策"可离线查看）。

## 反馈

- Bug 与建议：[提交 Issue](https://github.com/koeltp/chestnut/issues)
- 邮箱：tp@taipi.top

## 许可证

基于 [MIT License](LICENSE) 开源。

Copyright © 2026 [taipi.top](https://www.taipi.top)
