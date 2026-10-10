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

## 构建

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
- 清单字段示意：

```json
{
  "versionCode": 4009,
  "versionName": "1.1.5",
  "apkUrl": "<每版本唯一文件名的 APK 直链>",
  "sha256": "<大写十六进制>",
  "fileSize": 61234567,
  "releaseNotes": "<与 CHANGELOG 同源>",
  "publishedAt": "<ISO 8601 时间>"
}
```

## 发布后回归（release 真包必做）

- 安装 release 包验证（注意与 debug 包 `top.taipi.chestnut.debug` 区分，正式包为 `top.taipi.chestnut`）
- **地图打开 / 定位 / POI 搜索 / 分享文件**——debug 与 release 的权限注入差异历史上踩过坑，这条不能省
- 应用内「检查更新」链路：能读到新清单、校验通过、拉起安装

## 更新日志

`CHANGELOG.md` 每版本追加条目，与应用内更新弹窗的 releaseNotes 保持同源。
