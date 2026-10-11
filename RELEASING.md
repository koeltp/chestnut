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

完整发版 = **先写 CHANGELOG → 跑脚本 → 主仓库归档 → 博客上传 → 线上验证 → 真包回归**。以下按顺序执行，以 1.1.6 为例。

### 第 0 步：写 CHANGELOG（顺序不能反）

`CHANGELOG.md` 顶部追加新版本条目（`## [x.y.z] - 日期`，条目用 `- ` 列表）。它决定应用内更新弹窗文案，且脚本从同版本段提取 releaseNotes——先跑脚本后改 CHANGELOG 会导致清单是旧文案。

条目书写约定：

- **releaseNotes 口径 = "用户可感知的增量"**：新增 / 修复 / 明显界面变化才进；纯代码重构、依赖升级等对用户零信息量的条目加 `[内部]` 前缀（`- [内部] xxx`），脚本提取时自动跳过——CHANGELOG 留档完整，更新弹窗只显示用户关心的
- **hotfix 不新开段**：版本名不变、仅构建号 +1 的紧急修复，修复条目**追加进该版本名已有的段**（App 按 versionCode 判新，CHANGELOG 同版本名一段）

### 第 1 步：跑发布脚本

```powershell
.\scripts\release.ps1 -VersionName 1.1.6   # 指定版本名，构建号自动 +1
.\scripts\release.ps1                      # 沿用 pubspec 当前版本名，仅构建号 +1
```

脚本自动完成：版本号写回 pubspec → `flutter analyze` + `flutter test`（失败即中止）→ arm64 release 构建 → aapt2 自检（versionCode = 构建号 + 2000、INTERNET 权限显式声明）→ 产物整理：

- `dist/chestnut-<版本>-arm64.apk`（每版本唯一文件名，防 CDN 缓存吐旧包）
- `dist/manifest-<版本>.json`——**与博客 latest.json 同构**（含 `_comment`/`forceUpdate`/releaseNotes 数组/小写 sha256/日期 publishedAt），收尾时直接覆盖上传，不再手改 JSON

脚本结尾会打印剩余人工步骤提醒。

### 第 2 步：主仓库提交 + tag

```powershell
git add pubspec.yaml CHANGELOG.md
git commit -m "chore(release): 1.1.6"
git tag v1.1.6
git push origin main v1.1.6
```

（若脚本/文档/清单 schema 也有改动，一并提交。）

### 第 3 步：GitHub Release 建档（仅存档，不指 apkUrl——GitHub Releases 国内下载速度为 0）

```powershell
# gh 不在 PATH 时用绝对路径；配置目录写入受限时先重定向
$env:GH_CONFIG_DIR = "$env:TEMP\gh-config"
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
& $gh release create v1.1.6 dist\chestnut-1.1.6-arm64.apk --title "1.1.6" --notes $notes
& $gh release edit v1.1.6 --latest=true   # 连续建档时最后一个会抢 Latest，收尾必须显式指定
```

notes 用 CHANGELOG 同版本段的 Markdown（分组标题改 `##`）。

### 第 4 步：产物上传博客仓库（`D:\work\prod\blog`）

```powershell
# APK：复制新版，删除旧版（博客 downloads/ 只保留最新一版，历史版本在 GitHub Releases）
Copy-Item dist\chestnut-1.1.6-arm64.apk D:\work\prod\blog\src\.vuepress\public\downloads\ -Force
Remove-Item D:\work\prod\blog\src\.vuepress\public\downloads\chestnut-1.1.5-arm64.apk

# 清单：直接覆盖（脚本产物已与 latest.json 同构，_comment 保留）
Copy-Item dist\manifest-1.1.6.json D:\work\prod\blog\src\.vuepress\public\chestnut\latest.json -Force
```

### 第 5 步：博客文章同步

`D:\work\prod\blog\src\docs\article\栗子记账.md` 四处核对：下载按钮链接与文案（文首）、版本号/架构/体积小字、直链（第二节）、SHA-256 校验值（大写展示）。博客介绍文字本身人工撰写。

### 第 6 步：提交并推送博客（触发部署）

```powershell
git add src/.vuepress/public 'src/docs/article/栗子记账.md'
git commit -m "chore: 栗子记账 v1.1.6 发版"
git push    # 61MB 大文件的 GH001 警告属正常
```

### 第 7 步：线上验证（部署构建需几分钟，轮询确认）

```powershell
# 清单：带 ?t=毫秒 破 CDN 缓存，versionCode 应为新值
$t = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
(Invoke-WebRequest "https://www.taipi.top/chestnut/latest.json?t=$t" -UseBasicParsing).Content

# APK：Content-Length 应与清单 fileSize 一致（文件名每版本全新，无旧缓存风险）
Invoke-WebRequest "https://www.taipi.top/downloads/chestnut-1.1.6-arm64.apk?t=$t" -Method Head -UseBasicParsing
```

### 第 8 步：真包回归

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

- APK **每版本换文件名**：`chestnut-<版本>-arm64.apk`。同名覆盖会被 CDN 边缘节点在缓存 TTL 内继续吐旧包，导致校验失败且极难发现
- 应用内更新的清单按 versionCode 判断新旧，携带 `sha256` 与 `fileSize` 双校验；下载 URL 追加时间戳参数破 CDN 缓存
- 清单（`latest.json`）实际 schema——脚本 `dist/manifest-<版本>.json` 产出即此结构，直接覆盖上传：

```json
{
  "_comment": "维护者说明（原样保留）",
  "versionCode": 4010,
  "versionName": "1.1.6",
  "apkUrl": "https://www.taipi.top/downloads/chestnut-1.1.6-arm64.apk",
  "sha256": "小写十六进制（Get-FileHash 结果需 ToLower）",
  "fileSize": 64652736,
  "forceUpdate": false,
  "releaseNotes": [
    "条目与 CHANGELOG 同源，字符串数组（App 端 UpdateService 按数组解析）"
  ],
  "publishedAt": "2026-10-11"
}
```

## 发布后回归（release 真包必做）

- 安装 release 包验证（注意与 debug 包 `top.taipi.chestnut.debug` 区分，正式包为 `top.taipi.chestnut`）
- **地图打开 / 定位 / POI 搜索 / 分享文件**——debug 与 release 的权限注入差异历史上踩过坑，这条不能省
- 应用内「检查更新」链路：能读到新清单、校验通过、拉起安装

## 更新日志

`CHANGELOG.md` 每版本追加条目，与应用内更新弹窗的 releaseNotes 保持同源。**发版时先更新 CHANGELOG 再跑发布脚本**（顺序不能反，见"一键发布"）。
