# 栗子记账一键发布脚本（Windows PowerShell）
#
# 用法：
#   .\scripts\release.ps1                  # 沿用 pubspec 当前版本名，构建号 +1
#   .\scripts\release.ps1 -VersionName 1.1.7   # 指定版本名，构建号自动 +1
#
# 按 RELEASING.md 流程执行：发布前检查 → 版本号落盘 → release 构建 →
# 构建后自检（versionCode / 权限 / SHA-256）→ 产物重命名 + 更新清单生成。
# 提交、打 tag、上传产物与发布后回归仍需人工完成（见脚本结尾提示）。

param(
  # 目标版本名（如 1.1.7）；不传则沿用 pubspec 里的版本名
  [string]$VersionName
)

# 不用 'Stop'：PS 5.1 下原生命令的 stderr 输出（如 flutter 的镜像提示横幅、
# gradle 的 JVM 警告）在重定向/作业宿主中会包装成 ErrorRecord，Stop 模式会
# 直接炸掉脚本。失败控制靠每步之后的 Assert-LastExit 退出码判定，更可靠。
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot\..

function Invoke-Step {
  param([string]$Title)
  Write-Host ""
  Write-Host "==> $Title" -ForegroundColor Cyan
}

function Assert-LastExit {
  # 原生命令失败立即终止：发布流程任何一步带病通过都会把问题带到用户手机上
  param([string]$What)
  if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ $What 失败（exit $LASTEXITCODE），发布中止" -ForegroundColor Red
    exit 1
  }
}

# ---------- 1. 版本号 ----------

Invoke-Step '读取并更新版本号'
$pubspecPath = Join-Path (Get-Location) 'pubspec.yaml'
$pubspec = [System.IO.File]::ReadAllText($pubspecPath)
if ($pubspec -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$') {
  Write-Host '✗ pubspec.yaml 中找不到 version: x.y.z+build' -ForegroundColor Red
  exit 1
}
$oldName = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$oldBuild = [int]$Matches[4]
if (-not $VersionName) { $VersionName = $oldName }
$newBuild = $oldBuild + 1   # 构建号每版 +1，不跳号不复用（RELEASING.md）
$newVersion = "$VersionName+$newBuild"
# .* 到行尾为止，不碰换行（\s* 会把 version 行后的空行吞掉）
[System.IO.File]::WriteAllText(
  $pubspecPath,
  ($pubspec -replace '(?m)^version:.*$', "version: $newVersion"),
  [System.Text.UTF8Encoding]::new($false)
)
Write-Host "版本：$oldName+$oldBuild → $newVersion（arm64 包 versionCode 应为 $($newBuild + 2000)）"

# ---------- 2. 发布前检查 ----------

Invoke-Step 'flutter analyze'
flutter analyze
Assert-LastExit 'flutter analyze'

Invoke-Step 'flutter test'
flutter test 2>&1 | Select-Object -Last 3
Assert-LastExit 'flutter test'

# ---------- 3. release 构建 ----------

Invoke-Step 'flutter build apk（arm64，关闭图标树摇）'
flutter build apk --release --no-tree-shake-icons --split-per-abi --target-platform android-arm64
Assert-LastExit 'flutter build apk'
$apk = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
if (-not (Test-Path $apk)) {
  Write-Host "✗ 找不到构建产物：$apk" -ForegroundColor Red
  exit 1
}

# ---------- 4. 构建后自检 ----------

# 定位 Android SDK（ANDROID_HOME → local.properties 的 sdk.dir → 默认安装路径）
$sdk = $env:ANDROID_HOME
if (-not $sdk -and (Test-Path 'android\local.properties')) {
  $line = (Get-Content 'android\local.properties' | Where-Object { $_ -match '^sdk\.dir=' })
  if ($line) { $sdk = $line.Substring(8).Replace('\\', '\').Replace('\:', ':') }
}
if (-not $sdk) { $sdk = "$env:LOCALAPPDATA\Android\Sdk" }
$aapt2 = Get-ChildItem "$sdk\build-tools" -Directory -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending |
  ForEach-Object { Join-Path $_.FullName 'aapt2.exe' } |
  Where-Object { Test-Path $_ } |
  Select-Object -First 1

Invoke-Step 'APK 自检（versionCode / 权限）'
if (-not $aapt2) {
  Write-Host "⚠ 未找到 aapt2（SDK：$sdk），跳过自检——请人工核对 versionCode 与权限" -ForegroundColor Yellow
} else {
  # badging 输出是多行数组：先合并成单个字符串再 -match，
  # 否则数组语义不回填 $Matches，版本信息会解析成空值
  $badgingText = (& $aapt2 dump badging $apk) -join "`n"
  Assert-LastExit 'aapt2 dump badging'
  if ($badgingText -match "versionCode='(\d+)' versionName='([^']+)'") {
    $actualCode = [int]$Matches[1]
    $actualName = $Matches[2]
    $expectedCode = $newBuild + 2000   # --split-per-abi 给 arm64 附加 2000 偏移
    Write-Host "versionName=$actualName versionCode=$actualCode（期望 $expectedCode）"
    if ($actualName -ne $VersionName -or $actualCode -ne $expectedCode) {
      Write-Host '✗ 版本信息与期望不符，发布中止' -ForegroundColor Red
      exit 1
    }
  } else {
    Write-Host '✗ 无法从 badging 解析版本信息，发布中止' -ForegroundColor Red
    exit 1
  }
  # release 不会像 debug 那样自动注入 INTERNET，漏声明会导致网络功能静默失败
  $perms = & $aapt2 dump permissions $apk
  Assert-LastExit 'aapt2 dump permissions'
  if ($perms -match 'android\.permission\.INTERNET') {
    Write-Host 'INTERNET 权限已声明 ✓'
  } else {
    Write-Host '✗ 缺少 INTERNET 权限（主 AndroidManifest 未显式声明？），发布中止' -ForegroundColor Red
    exit 1
  }
}

# ---------- 5. 产物：重命名 + 哈希 + 更新清单 ----------

Invoke-Step '整理产物'
$dist = Join-Path (Get-Location) 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# 每版本换文件名：同名覆盖会被 CDN 边缘节点吐旧包（RELEASING.md 踩坑记录）
$apkName = "chestnut-$VersionName-arm64.apk"
$apkDist = Join-Path $dist $apkName
Copy-Item $apk $apkDist -Force

$hash = (Get-FileHash $apkDist -Algorithm SHA256).Hash
$size = (Get-Item $apkDist).Length
Write-Host "APK：dist\$apkName（$([math]::Round($size / 1MB, 1)) MB）"
Write-Host "SHA-256：$hash"

# 从 CHANGELOG 提取当前版本的条目作为 releaseNotes（与 CHANGELOG 同源）
# 必须 -Encoding UTF8：PS 5.1 默认按 ANSI 读无 BOM 的 UTF-8，中文会变乱码
# 清单的 releaseNotes 是字符串数组（App 端 UpdateService 按此解析）：
# 只取"· "条目行；【分组头】不进清单；[内部] 前缀条目是纯内部重构，
# 对用户零信息量——进 CHANGELOG 留档但不进应用内更新弹窗
$notes = @()
$inSection = $false
foreach ($line in (Get-Content 'CHANGELOG.md' -Encoding UTF8)) {
  if ($line -match "^## \[$VersionName\]") { $inSection = $true; continue }
  if ($inSection -and $line -match '^## \[') { break }
  if ($inSection -and $line -match '^- \[内部\]') { continue }
  if ($inSection -and $line -match '^- (.+)$') { $notes += $Matches[1] }
}
$releaseNotes = @($notes | Where-Object { $_.Trim() })

# 应用内更新清单：与博客 latest.json 同构，收尾时直接覆盖上传即可。
# versionCode 判断新旧（构建号+2000 实际值），sha256 小写，forceUpdate 默认 false
$manifestCode = $newBuild + 2000
if ($actualCode) { $manifestCode = $actualCode }   # aapt2 自检通过时以 APK 实际值为准
$manifest = [ordered]@{
  _comment     = '栗子记账最新版本清单。发版步骤：1) pubspec 版本号与构建号(+N)+1；2) flutter build apk --release --no-tree-shake-icons --split-per-abi 取 arm64 包，文件名带版本号放入 /downloads/；3) GitHub koeltp/chestnut 网页建 release（tag vx.y.z）上传 APK 存档（仅存档/对外展示，不指 apkUrl——GitHub Releases 国内下载速度为 0）；4) 更新本文件 versionCode/versionName/apkUrl/sha256/fileSize/releaseNotes；5) push。注意：--split-per-abi 会给 arm64 包的 versionCode 加 2000 偏移（构建号1→2001、2→2002），本文件 versionCode 必须填 APK 实际值，App 按它判断新旧'
  versionCode  = $manifestCode
  versionName  = $VersionName
  apkUrl       = "https://www.taipi.top/downloads/$apkName"
  sha256       = $hash.ToLower()
  fileSize     = $size
  forceUpdate  = $false
  releaseNotes = $releaseNotes
  publishedAt  = (Get-Date).ToString('yyyy-MM-dd')
}
$manifestPath = Join-Path $dist "manifest-$VersionName.json"
# 不用 Out-File：它默认写带 BOM 的 UTF-8，App 侧 jsonDecode 不认 BOM
[System.IO.File]::WriteAllText(
  $manifestPath,
  ($manifest | ConvertTo-Json),
  [System.Text.UTF8Encoding]::new($false)
)
Write-Host "更新清单：dist\manifest-$VersionName.json"

# ---------- 6. 收尾提示 ----------

Write-Host ""
Write-Host "✅ $VersionName 构建完成" -ForegroundColor Green
Write-Host "剩余人工步骤（详见 RELEASING.md「一键发布」）："
Write-Host "  1. 提交 pubspec.yaml + CHANGELOG.md，打 tag v$VersionName，gh release create（收尾 --latest=true）"
Write-Host "  2. APK 传博客仓库 D:\work\prod\blog\src\.vuepress\public\downloads\，删旧版只留最新"
Write-Host "  3. dist\manifest-$VersionName.json 内容覆盖博客 src\.vuepress\public\chestnut\latest.json"
Write-Host "  4. 博客文章 src\docs\article\栗子记账.md 同步版本号/下载直链/SHA-256"
Write-Host "  5. push 博客部署，线上验证 latest.json 与带 ?t= 的 APK 哈希"
Write-Host "  6. release 真包回归：地图打开 / 定位 / POI / 分享文件 / 应用内检查更新"
