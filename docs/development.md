# 开发笔记：真机无线调试

从 [README](../README.md) 挪出的实操笔记，按需取用。

## 二维码配对（推荐）

不想插数据线时，可用 [adb-wifi-qr](https://pypi.org/project/adb-wifi-qr/) 在终端生成二维码，手机扫码完成配对：

```bash
# 安装（Python 3.8+，需 Android platform-tools 31+）
pip install adb-wifi-qr

# 生成二维码并在配对后自动连接
adb-wifi-qr --connect
```

手机端操作：**设置 → 系统管理 → 开发者选项 → 无线调试 → 使用二维码配对设备**，扫描终端中的二维码即可。

前提：手机系统 Android 11+，且手机与电脑在同一 Wi-Fi 下。配对只需一次；无线调试的连接端口每次开启会变化，重新打开后重跑上述命令，或用 `adb mdns services` 查到连接端口后 `adb connect <IP:端口>`。扫码不成功时可把终端调大、换深色背景，或加 `--timeout 120` 延长等待时间。

## 不扫码的直连组合

只有一台机器、懒得扫码时：

```bash
# 构建调试包 → 安装到当前连接的设备 → 拉起 App
flutter build apk --debug ; adb install -r build\app\outputs\flutter-apk\app-debug.apk ; adb shell monkey -p top.taipi.chestnut.debug -c android.intent.category.LAUNCHER 1

# 多设备/无线连接时用 -s 指定 IP:PORT（IP:PORT 换成 adb mdns services 查到的值）
flutter build apk --debug ; adb -s 192.168.10.3:36691 install -r build\app\outputs\flutter-apk\app-debug.apk ; adb -s 192.168.10.3:36691 shell monkey -p top.taipi.chestnut.debug -c android.intent.category.LAUNCHER 1
```
