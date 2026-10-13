# Android 手机 USB 调试（Windows）

## 1. 电脑准备

安装 Flutter 3.47.7、JDK 17 和 Android Studio / Android SDK。
SDK Manager 安装 Platform 36、Build-Tools、Platform-Tools、NDK 28.2.13676358。
将 Flutter 的 `bin` 与 SDK 的 `platform-tools` 加入 PATH。
也可设置 `ANDROID_HOME` 指向 SDK 根目录；如设置 `ANDROID_SDK_ROOT`，保持两者一致。
如果 adb 没在 PATH，脚本会尝试上述变量及 `%LOCALAPPDATA%\Android\Sdk`。

新终端运行：

```powershell
flutter --version
java -version
adb version
flutter doctor -v
flutter doctor --android-licenses
```

Windows 上可能需要手机厂商的 OEM USB 驱动；Google USB Driver 主要适用于 Google 设备。
优先官网下载，不安装来源不明的“万能驱动”。Android 调试不需要 Windows Desktop 的 Visual Studio 工作负载。

## 2. 手机准备

1. 打开“设置 → 关于手机”，连续点击“版本号 / 软件版本”约 7 次，按提示输入锁屏密码。
2. 回到“系统 / 更多设置 → 开发者选项”，打开 **USB 调试**。
3. 用支持数据传输的 USB 线连接电脑，解锁手机；必要时选择“文件传输 / MTP”。
4. 手机弹出 RSA 调试授权时核对电脑并选择允许。仅自己的可信电脑可选择“始终允许”。
5. 部分厂商另有“通过 USB 安装”开关，安装 debug 包失败时再检查；不要随意关闭其他安全保护。

## 3. 检查连接

```powershell
adb devices -l
flutter devices
```

| 状态 | 处理 |
| --- | --- |
| `device` | ADB 可用；确认 Flutter 列表也能识别 |
| `unauthorized` | 解锁手机，确认 RSA 弹窗；无弹窗时撤销 USB 调试授权后重连 |
| `offline` | 重新插拔，检查线和端口，必要时重启 ADB |
| 无设备 | 换数据线 / USB 口，检查 USB 模式和 Windows 设备管理器驱动 |
| 多台手机 | 使用 `-Device SERIAL` 指定；脚本不随机挑设备 |
| 有 MuMu / emulator | 默认 `-d` 选择唯一 USB 实机；显式指定设备序列号可选其他 Android 设备 |

排查时可执行以下命令，但会中断电脑上其他 ADB 会话：

```powershell
adb kill-server
adb start-server
adb devices -l
```

## 4. 从项目启动

在 **Youying 项目根目录** 打开 PowerShell：

```powershell
.\dev.cmd                          # 选择 3：USB 调试
.\dev.cmd -Action debug            # 默认唯一 USB 手机
.\dev.cmd -Action debug -Device SERIAL
```

替换 `SERIAL` 为 `adb devices -l` 第一列；不要复制状态词 `device`。
脚本执行 `flutter pub get`，检查连接/授权，再以 debug 模式安装并运行。
等价手动命令：

```powershell
flutter pub get
flutter run --debug -d SERIAL
```

终端快捷键：`r` 热重载、`R` 热重启、`q` 结束调试；完整快捷键看终端的 `h`。
修改 Kotlin、Gradle、manifest 或增加插件需要停止并重新运行，不能仅用热重载。
真实媒体功能要自己添加有授权的 HTTPS 源；默认源数量是零，空搜索结果不是“恢复出了失效源”。

## 5. 重新连接 / 日志 / 安装测试包

```powershell
flutter logs -d SERIAL
flutter attach -d SERIAL
```

`attach` 只适用于已经运行且启用 Dart VM Service 的 debug 应用；不是给任意 APK 附加调试，
正式 release 包不支持热重载，也不能通过 attach 恢复原 APK 的 Dart 源码。
不要同时启动多个 Flutter 客户端争用同一调试服务。

构建并安装测试包：

```powershell
.\dev.cmd -Action test
adb -s SERIAL install -r ".\dist\test\youying-test-实际时间戳.apk"
```

测试包为 `dev.youying.app.debug`，可与 release 包共存。
若已有同包名但由另一电脑 debug 密钥签名的包，更新可能提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。
先备份需要的数据，再通过手机界面卸载旧测试包；卸载删除该包的数据。不要盲目卸载正式包。

## 6. 安全

不接受未知电脑 RSA 指纹；不要在公共电脑保留授权。完成调试后可关闭 USB 调试、撤销授权。
日志可能包含源 URL、标题或鉴权信息，分享前脱敏；Git 不跟踪调试日志或签名文件。
脚本不能控制或修复你的驱动，当前交付也不代表已经在你的手机上运行成功。

官方参考：[Android 真机运行](https://developer.android.com/studio/run/device)、
[OEM 驱动](https://developer.android.com/studio/run/oem-usb)、
[Flutter Android 设置](https://docs.flutter.dev/platform-integration/android/setup)、
[Flutter 热重载](https://docs.flutter.dev/tools/hot-reload)。
