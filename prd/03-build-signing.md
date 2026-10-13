# 调试、测试包、正式签名包

## 选择入口

在项目根目录运行 `.\dev.cmd`，按菜单选择；也可给出参数。
脚本适用于 Windows PowerShell 5.1，文件采用 UTF-8 BOM 保证中文读取。
已有 PowerShell 7 可直接运行 `pwsh -File .\scripts\dev.ps1`，但本轮只验证 Windows 5.1 工作流。

| 命令 | 行为 | 签名 / 包标识 |
| --- | --- | --- |
| `.\dev.cmd -Action doctor` | 环境/设备检查 | 不构建 |
| `.\dev.cmd -Action check` | pub get、analyze、test | 不构建 |
| `.\dev.cmd -Action debug` | USB 手机 flutter run、热重载 | debug / `dev.youying.app.debug` |
| `.\dev.cmd -Action test` | pub get、构建 debug APK | debug / `dev.youying.app.debug` |
| `.\dev.cmd -Action release` | pub get、analyze、test、自有签名 release APK、apksigner 验签 | 私有密钥 / `dev.youying.app` |
| `.\dev.cmd -Action git` | 没有 .git 才初始化 main；否则 status | 不提交、不推送 |

测试包是可安装的 debug APK，不等于“执行自动化测试”。建议先执行 `check` 再构建测试包。
默认通用 APK 包含 ARMv7、ARM64、x86_64，体积较大。
只给现代 ARM64 手机打包可用：

```powershell
.\dev.cmd -Action test -TargetPlatform android-arm64
.\dev.cmd -Action release -TargetPlatform android-arm64
```

MuMu 常用 x86_64，可选择 `android-x64`，具体以 `adb shell getprop ro.product.cpu.abilist` 为准。
输出是 `dist/test/youying-test-时间戳.apk` 或 `dist/release/youying-release-时间戳.apk`，并打印 SHA-256。
任何工具失败即停止，不复制旧 APK 当作成功产物；脚本不自动安装测试/正式包。

## 正式密钥：由你创建和保管

**工程没有生产 keystore，不能把历史 debug 签名的 APK 当作正式包。**
如已有自己的长期签名密钥，继续使用；不要每次构建生成新密钥，否则不能覆盖升级。
还没有密钥时，在电脑上的项目目录之外创建，例如个人目录的 `AndroidKeys`：

```powershell
New-Item -ItemType Directory -Force "$HOME\AndroidKeys"
keytool -genkeypair -v -keystore "$HOME\AndroidKeys\youying-release.jks" -storetype JKS -keyalg RSA -keysize 3072 -validity 10000 -alias youying
```

命令会交互询问密码及证书资料；不要把密码写成命令参数、复制到日志或提交进 Git。
使用高强度密码，离线备份 keystore、别名和密码，限制文件访问权限。
签名密钥丢失可能导致无法升级既有安装；商店的 App Signing 政策需按渠道单独配置。

运行 `.\dev.cmd -Action release`。脚本会询问：

- `YOUYING_KEYSTORE`：文件路径，会转换为绝对路径。
- `YOUYING_KEY_ALIAS`：如 `youying`。
- `YOUYING_STORE_PASSWORD`、`YOUYING_KEY_PASSWORD`：通过隐藏输入读取，不打印、不持久保存。

这些值只临时传给当前 Gradle 子进程，用完恢复原环境。
也可由 CI 的安全 secret 管理注入四个环境变量，然后执行：

```powershell
.\dev.cmd -Action release -NonInteractive
```

无人值守模式缺少任何变量即失败，不能弹出输入或使用 debug 签名。
Gradle 本身也检查 release 签名，因此绕过脚本直接 `flutter build apk --release` 同样不能逃避要求。
无文件、无私钥别名、过期证书或 Android debug 证书被拒绝；密码错误会失败。
本工程不读取旧式 `android/key.properties`；若你自行添加它，它也被 .gitignore 忽略。
如直接使用 Flutter CLI / Android Studio，须把四个变量提供给它们的父进程。

## 验签与升级

正式发布前，用 SDK Build-Tools 的 `apksigner` 检查 APK，而不只看文件名。
以下 `36.0.0` 可替换成自己已安装的 Build-Tools 版本：

```powershell
& "$env:ANDROID_HOME\build-tools\36.0.0\apksigner.bat" verify --verbose --print-certs ".\dist\release\youying-release-实际时间戳.apk"
Get-FileHash ".\dist\release\youying-release-实际时间戳.apk" -Algorithm SHA256
```

确认验签成功、证书不是 Android Debug、证书摘要符合自己保管的密钥。
修改 `pubspec.yaml` 的 `version: 0.1.0+1` 发布新版本，`+` 后 versionCode 必须增长。
正式包和旧 `dev.reconstructed.xiaoyouzi_rebuilt` 不是同一个应用，不能原地升级或自动继承数据。

## 发布前必做

- [ ] 确认品牌/包标识/素材使用权；本工程是重建而非原源码。
- [ ] 有权使用的视频源完成搜索、选集和真实播放验收。
- [ ] 手机上完成网络异常、权限、后台/前台、下载和续播测试。
- [ ] 自己的长期密钥已安全备份，验签/安装/覆盖升级通过。
- [ ] 版本号递增，明确最低 Android 版本和支持 ABI。
- [ ] 隐私说明、用户数据处理、网络源合法性和目标发布渠道要求已审核。
- [ ] 检查 `git status`；没有 token、日志、.env、keystore 或密码。

`.gitignore` 不能自动删除此前已经跟踪的秘密，也不是安全扫描器。当前交付不附带生产凭证。
源码、prd、scripts、依赖锁和 wrapper 应版本管理；不将 APK、ZIP、build 或 SDK 路径提交。
初始化脚本不代你配置 Git 姓名/邮箱，也不会连接 GitHub；后续设置远程由你决定。

官方参考：[Flutter Android 发布](https://docs.flutter.dev/deployment/android)、
[Android 签名](https://developer.android.com/studio/publish/app-signing)、
[apksigner](https://developer.android.com/tools/apksigner)。
