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
| `.\dev.cmd -Action signing` | 仅首次生成长期签名，已有密钥不覆盖 | 密钥保存在工程外 |
| `.\dev.cmd -Action version` | 查看当前版本并交互修改 | 不构建、不改签名 |
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

## 正式密钥：本机初始化和保管

**源码仓库不包含生产 keystore，不能把历史 debug 签名的 APK 当作正式包。**
如已有自己的长期签名密钥，继续使用；不要每次构建生成新密钥，否则不能覆盖升级。
还没有密钥时，在项目根目录执行：

```powershell
.\dev.cmd -Action signing
```

脚本在 `$HOME\AndroidKeys\youying` 生成 RSA 3072 / JKS 长期密钥，别名 `youying`，有效期 10000 天。
密码随机生成，不打印到终端。目录 ACL 限制为当前 Windows 用户和 SYSTEM。
重复运行会保留已有密钥；发现不完整的已有密钥/恢复资料会停止，而不是覆盖。

- `youying-release.jks`：长期私钥，不能上传或发给测试手机。
- `signing.clixml`：Windows DPAPI 加密的密码配置，只供原 Windows 用户在原电脑自动解密。
- `RECOVERY-PRIVATE.txt`：私有恢复资料，含明文密码。仅在本机受限目录保存，不上传、不提交。
- `release-certificate.cer` / `certificate-sha256.txt`：公开证书及 SHA-256 指纹，用于核对签名。

**把 keystore 和恢复密码分别备份到加密离线存储/密码管理器；不要只备份 clixml。**
换电脑或 Windows 用户时，不能依赖旧 clixml；恢复同一 keystore 后，通过下面四个变量/隐藏输入提供密码，不生成新密钥。
签名密钥丢失可能导致无法升级既有安装；商店的 App Signing 政策需按渠道单独配置。

原电脑、原用户运行 `.\dev.cmd -Action release` 会自动读取本机加密配置，不再每次输入密码。
已有环境变量优先；没有本机配置时，脚本会询问：

- `YOUYING_KEYSTORE`：文件路径，会转换为绝对路径。
- `YOUYING_KEY_ALIAS`：如 `youying`。
- `YOUYING_STORE_PASSWORD`、`YOUYING_KEY_PASSWORD`：通过隐藏输入读取，不打印、不持久保存。

这些值只临时传给当前 Gradle 子进程，用完恢复原环境。
也可由 CI 的安全 secret 管理注入四个环境变量，然后执行：

```powershell
.\dev.cmd -Action release -NonInteractive
```

无人值守模式支持本机加密配置或四个环境变量，缺少任何值即失败，不能弹出输入或使用 debug 签名。
Gradle 本身也检查 release 签名，因此绕过脚本直接 `flutter build apk --release` 同样不能逃避要求。
无文件、无私钥别名、过期证书或 Android debug 证书被拒绝；密码错误会失败。
本工程不读取旧式 `android/key.properties`；若你自行添加它，它也被 .gitignore 忽略。
如直接使用 Flutter CLI / Android Studio，须把四个变量提供给它们的父进程。

## 验签与升级

本机专用工具链入口是 `.local/toolchain.ps1`（已忽略，不提交）。`dev.cmd` 会自动加载它。
工具安装在 `D:\YouyingTools`；本机配置沿用已有的 `127.0.0.1:7897` 网络代理，下载依赖时需保持该代理运行。
换电脑需重新安装工具链并建立自己的本机配置，不复制机器路径到共享源码。
本机保留了原有 Platform-Tools，不影响其他工具；本工程优先使用 SDK 内的 adb。
`doctor` 可能提示发现多份 adb，这不影响 APK 构建；USB 调试若发生版本冲突，再统一 adb 版本。

正式发布前，用 SDK Build-Tools 的 `apksigner` 检查 APK，而不只看文件名。
以下 `36.0.0` 可替换成自己已安装的 Build-Tools 版本：

```powershell
& "$env:ANDROID_HOME\build-tools\36.0.0\apksigner.bat" verify --verbose --print-certs ".\dist\release\youying-release-实际时间戳.apk"
Get-FileHash ".\dist\release\youying-release-实际时间戳.apk" -Algorithm SHA256
```

确认验签成功、证书不是 Android Debug、证书摘要符合自己保管的密钥。
### 修改版本号

版本记录在 `pubspec.yaml` 的顶层 `version` 字段，格式为 `X.Y.Z+N`。
例如 `0.1.0+1` 中，`0.1.0` 对应 Android 的 versionName，`1` 对应 versionCode。
Android 配置已从 Flutter 读取它们，不需要同时手动改 Gradle。

```powershell
.\dev.cmd -Action version -ShowVersion                      # 只查看
.\dev.cmd -Action version -BumpBuild                        # 仅将构建号加 1
.\dev.cmd -Action version -Version 0.2.0                    # 新版本名，构建号自动加 1
.\dev.cmd -Action version -Version 0.2.1 -BuildNumber 10    # 两者显式指定
.\dev.cmd -Action release                                  # 再生成正式 APK
```

也可直接运行 `.\dev.cmd` 选 **8**，或 `.\dev.cmd -Action version` 进入交互；
版本名留空保留当前名字，构建号留空将当前值加 1。修改后显示修改前后的完整版本。
脚本只修改版本字段，不自动打包、安装、提交 Git 或改变签名；`release` 本身不自动递增版本。
`-NonInteractive` 用于自动化，必须给出修改参数或 `-ShowVersion`，不能无参数弹出输入。

构建号必须严格大于当前值且不超过 2100000000；换到 `1.0.0` 等新版本名也不能重置构建号。
版本名使用三段非负整数，不含前导零；错误格式、重复版本字段、构建号回退会在写入前失败。
保留原文件 UTF-8 BOM、换行、引号和注释，不重写其他配置；当前版本不会因添加脚本而自动改变。

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
