# 发版流程（RELEASING）

面向维护者与 fork / 自建者的标准发版流程。发布渠道（更新清单托管站点、下载地址）由部署者自行约定，本文只约束与代码和 APK 相关的通用规则。

## 版本号规则

- `pubspec.yaml` 的 `version` 为 `versionName+构建号`（如 `1.1.5+2009`），每次发布构建号 **+1**，不跳号不复用
- `--split-per-abi` 会给 arm64 包的 versionCode 附加 **2000 偏移**：`APK versionCode = pubspec 构建号 + 2000`（构建号 1 → 2001，构建号 2009 → **4009**）。应用内更新按 versionCode（而非 versionName）判断新旧，发布渠道的更新清单必须填 **APK 实际值**，不能照抄 pubspec
- 核对实际值：

```bash
aapt2 dump badging app-arm64-v8a-release.apk | grep versionCode
```

## 发布前检查

```bash
flutter analyze        # 无警告
flutter test           # 全量通过
```

真机回归（debug 包即可）：记账、首页、统计、预算、资产、备份等主流程 + 本次改动涉及的页面。

## 一键发布（推荐）

完整发版 = **写 CHANGELOG → 跑本地预检脚本 → 提交 + annotated tag → CI 自动发布 → 线上验证 → 真包回归**。

> 架构说明：`.github/workflows/release.yml` 在推送 `v*` tag 后自动完成构建、签名、生成
> `latest.json` 并创建 GitHub Release（上传 APK + 固定名副本 + 清单）。GitHub Release
> 是唯一事实源；因 GitHub 国内直连不可靠，**对外分发统一走 Cloudflare Worker 反代**
> `chestnut.taipi.top`（`cloudflare/worker.js`，白名单转发 Release 资产）：
> 应用从 `chestnut.taipi.top/latest/download/latest.json` 读清单，清单里的
> `apkUrl` 同指 Worker 域（CI 生成时已替换），博客与 README 下载按钮也指向 Worker 域。
> **线上事实源是 CI，本地脚本只做发版前预检。**

### 第 0 步：写 CHANGELOG（顺序不能反）

`CHANGELOG.md` 顶部追加新版本条目（`## [x.y.z] - 日期`，条目用 `- ` 列表）。它是版本留档与发布脚本文案提取的来源——先写 CHANGELOG 再走后面步骤。

条目书写约定：

- **releaseNotes 口径 = "用户可感知的增量"**：新增 / 修复 / 明显界面变化才进；纯代码重构、依赖升级等对用户零信息量的条目加 `[内部]` 前缀（`- [内部] xxx`），脚本提取时自动跳过——CHANGELOG 留档完整，更新弹窗只显示用户关心的
- **hotfix 不新开段**：版本名不变、仅构建号 +1 的紧急修复，修复条目**追加进该版本名已有的段**（App 按 versionCode 判新，CHANGELOG 同版本名一段）

### 第 1 步：跑本地预检脚本

```powershell
.\scripts\release.ps1 -VersionName 1.2.4   # 指定版本名，构建号自动 +1
.\scripts\release.ps1                       # 沿用 pubspec 当前版本名，仅构建号 +1
```

脚本自动完成：版本号写回 pubspec → `flutter analyze` + `flutter test`（失败即中止）→ arm64 release 构建 → aapt2 自检（versionCode = 构建号 + 2000、INTERNET 权限显式声明）→ 产物整理到 `dist/`（APK + manifest 本地预检副本）。

> 本地构建的 APK 仅用于预检与真包回归，**线上发布包由 CI 构建上传**，两者同
> commit 同配置，体积略有差异（本机 JDK 与 runner 不同）属正常。

### 第 2 步：主仓库提交 + annotated tag（更新文案源）

```powershell
git add pubspec.yaml CHANGELOG.md
git commit -m "chore(release): 1.2.4"
git tag -a v1.2.4 -m "明细列表同一天内按发生时刻倒序排列（如 9:30 在 9:20 上方）"
git push origin main v1.2.4
```

**tag message 就是应用内更新弹窗的 releaseNotes**：CI 逐行读取 annotated tag message 生成 `latest.json` 的 `releaseNotes` 与 Release 页面正文（见 release.yml）。必须把 CHANGELOG 里用户可感知的条目逐行写进 message，`[内部]` 条目不写。

（若脚本/文档/workflow 也有改动，一并提交。）

### 第 3 步：CI 自动发布 + 线上验证

推送 tag 后 GitHub Actions 自动执行（仓库 Actions 页盯全绿，约 10~15 分钟）：构建（含 `--no-tree-shake-icons`）→ 签名指纹校验 → 生成 latest.json → 创建 GitHub Release 并上传三件产物：

- `chestnut-<版本>.apk`——版本化文件名（防 CDN/缓存吐旧包）
- `chestnut-latest.apk`——固定名副本，`releases/latest/download/` 直链恒指最新
- `latest.json`——应用内更新清单

验证（Actions 全绿后）：

```powershell
# 经 Worker 域验证（国内用户实际走的链路）
(Invoke-WebRequest "https://chestnut.taipi.top/latest/download/latest.json" -UseBasicParsing).Content
```

核对 `versionCode`（应为构建号 + 2000）、`releaseNotes`（应为 tag message 内容）、`apkUrl`（应为 Worker 域）。

### 第 4 步：真包回归

见下文"发布后回归"——手机现有正式包走「我的 → 检查更新」升级，再测地图/定位/POI/分享。

## 构建（手动，备用）

只打 arm64 架构，并关闭图标树摇（分类图标码点入库、运行时渲染，树摇会裁掉运行时引用的图标）：

```bash
flutter build apk --release --no-tree-shake-icons --split-per-abi --target-platform android-arm64
```

产物：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`（注意带 v8a 后缀）。签名证书在 `android/key.properties` 配置（文件不入库），debug 与 release 统一使用同一证书。

## 构建后自检

1. **权限**：`aapt dump permissions <apk>`——联网权限必须在主 AndroidManifest.xml 显式声明，release 构建不会像 debug 那样自动注入 INTERNET，漏声明会导致地图 / 检查更新等全部网络功能静默失败（debug 正常、release 异常，极难排查）
2. **versionCode**：按上文 `aapt2 dump badging` 核对实际值
3. **SHA-256 与文件大小**：记录下来，供发布渠道与应用内更新校验使用

```powershell
Get-FileHash <apk> -Algorithm SHA256
```

## 命名与分发

- APK **每版本换文件名**：CI 上传 `chestnut-<版本>.apk` 与固定名副本 `chestnut-latest.apk`（后者配合 `releases/latest/download/` 直链恒指最新）
- 应用内更新的清单按 versionCode 判断新旧，携带 `sha256` 与 `fileSize` 双校验
- 清单（`latest.json`）实际 schema——CI 按此结构生成并随 Release 上传：

```json
{
  "versionCode": 6020,
  "versionName": "1.2.4",
  "apkUrl": "https://github.com/koeltp/chestnut/releases/download/v1.2.4/chestnut-1.2.4.apk",
  "sha256": "小写十六进制（CI 用 sha256sum 计算）",
  "fileSize": 63282123,
  "releaseNotes": [
    "逐行来自 annotated tag message（App 端 UpdateService 按数组解析）"
  ],
  "publishedAt": "2026-10-24T04:46:57+00:00"
}
```

> App 端 `UpdateInfo.fromJson` 对缺失字段容错（`forceUpdate` 缺省 false、
> `releaseNotes`/`publishedAt` 可空），CI 生成不带 `forceUpdate` 字段的清单即可。

## 发布后回归（release 真包必做）

- 安装 release 包验证（注意与 debug 包 `top.taipi.chestnut.debug` 区分，正式包为 `top.taipi.chestnut`）
- **分类图标正常渲染**（码点入库运行时构造，构建若漏了 `--no-tree-shake-icons` 会显示成方框，且只在 release 包出现）
- **地图打开 / 定位 / POI 搜索 / 分享文件**——debug 与 release 的权限注入差异历史上踩过坑，这条不能省
- 应用内「检查更新」链路：能读到新清单、校验通过、拉起安装

## 更新日志

`CHANGELOG.md` 每版本追加条目，作为仓库留档；应用内更新弹窗的 releaseNotes 在发版时**从 CHANGELOG 的用户可感知条目提炼进 annotated tag message**（CI 读取 message 生成清单，见"一键发布"第 2 步）。
