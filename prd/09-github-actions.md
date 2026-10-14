# GitHub Actions 云端正式 APK

这套流程在 GitHub 托管的 Ubuntu 24.04 上安装 JDK 17、Flutter 3.47.7、Android Platform 36、
Build-Tools 36.0.0 和 NDK 28.2.13676358，沿用 `scripts/dev.ps1` 的依赖、静态分析、测试、正式构建和验签。
不使用本机的 `127.0.0.1:7897` 代理或 `.local/toolchain.ps1`，也不在云端重新生成签名。

## 1. 上传构建配置

工作流文件是 `.github/workflows/android-release.yml`。修改需提交到仓库默认分支，当前为 `main`；
仅把源码推上去并不会自动生成 APK，也不会自动开始收费构建。

本次配置涉及以下五个文件，请先检查再提交：

```powershell
git status --short
git add .github/workflows/android-release.yml scripts/copy-github-signing.ps1 scripts/dev.ps1 README.md prd/09-github-actions.md
git commit -m "Add manual signed Android release workflow"
git push
```

不要用 `git add -f` 添加被忽略的密钥、APK 或本机环境。工作流必须进入默认分支后，Actions 页面才会提供运行按钮。

## 2. 配置四项签名 Secrets（仅首次）

仓库：[libai6666/Youying](https://github.com/libai6666/Youying)。
打开 [Settings → Secrets and variables → Actions](https://github.com/libai6666/Youying/settings/secrets/actions)，
依次点 **New repository secret**，保存以下四项：

| Name | Secret 值 | 来源 |
| --- | --- | --- |
| `YOUYING_KEYSTORE_BASE64` | 现有 JKS 文件的单行 Base64 | 不是文件路径，也不是新的密钥 |
| `YOUYING_KEY_ALIAS` | 现有签名别名 | 由本机配置读取 |
| `YOUYING_STORE_PASSWORD` | 现有 keystore 密码 | 由本机 DPAPI 解密 |
| `YOUYING_KEY_PASSWORD` | 现有私钥密码 | 由本机 DPAPI 解密 |

在原 Windows 用户的项目目录运行：

```powershell
.\dev.cmd -Action github-signing
```

也可菜单选 **9**。先关闭 Windows 剪贴板历史、云同步及剪贴板管理器，阅读提示后输入 `YES`。
脚本每次显示一个 Name：先在网页填好 Name，再在终端回车复制对应值，粘贴到网页 Secret 框并点 **Add secret**，
回到终端回车继续下一项。正常结束或异常退出都会尝试清空剪贴板；硬关闭窗口后请手动清空。
脚本不把值显示到终端，不生成秘密文件、不修改原签名、不自动上传。不要用它做屏幕共享演示。

Base64 只是编码，不是加密；这个值等同于持有私钥文件，必须放 **Secrets**，不能放 Variables、源码、Issue 或聊天。
GitHub 保存后不再显示 Secret 原值，不影响 Actions 使用。原电脑的 `signing.clixml` 不能在 Linux 上解密，不能上传代替这四项。
四项值应全部来自现有签名，以保证之后的 APK 能覆盖升级。密钥和密码仍需分别离线加密备份。

## 3. 手动开始正式构建

1. 确认仓库是 **Private**。本流程拒绝公开仓库，避免签名 APK 通过公开 Actions 制品分发；不会替你修改仓库可见性。
2. 打开 [Actions → Android 正式 APK](https://github.com/libai6666/Youying/actions/workflows/android-release.yml)。
3. 如果 GitHub 提示先启用 Actions，请由仓库管理员确认启用。
4. 点 **Run workflow**，分支选择 **main**（默认分支）。
5. `architecture` 选择 `universal`（通用包）或 `arm64`（较新 Android 手机，包更小）。
6. 点确认运行，进入本次运行查看各步骤。

首次需下载工具链和 Android/Maven 依赖；后续复用 Flutter/Pub/Gradle 依赖缓存，仍会受 GitHub 和仓库服务状态影响。
工作流最长运行 60 分钟，不自动重跑失败任务。私有仓库使用你账户的 Actions/存储额度，额度、计费和预算以 GitHub 页面为准。
同分支的构建会排队，不会主动取消正在运行的构建。

此流程只通过 `workflow_dispatch` 手动触发，不在 push、PR、fork 或 tag 时自动调用签名。
GitHub Token 仅 `contents: read`，不自动创建 Release、不上传到应用商店，也不提交或递增版本。
只有有写权限、可以运行流程及修改仓库的可信协作者才应接触这个仓库和签名配置。

## 4. 下载和安装

运行成功后，在运行页面底部 **Artifacts** 下载 `youying-release-架构-运行号-重试号`。
网页下载的是 ZIP，先解压，再把里面带时间戳的 `.apk` 发到手机安装；不要把 ZIP 当 APK 安装。
制品包含正式 APK 和 `SHA256SUMS.txt`，只保留 7 天，不会上传 JKS、密码、DPAPI 配置或整个工作区。
下载需要仓库读权限。请及时保存需要保留的 APK，别把 Actions 制品当作长期备份。

工作流调用 `apksigner verify --verbose --print-certs` 后才复制和上传 APK。
日志中的签名证书 SHA-256 应与原电脑密钥目录中的 `certificate-sha256.txt` 一致；二者是证书指纹，
不要与 `SHA256SUMS.txt` 中整个 APK 的文件 SHA-256 混淆。
密钥只解码到运行器临时目录，目录权限 700、文件权限 600，成功/失败均清理；不进入依赖缓存或制品。
云端专门降低 Gradle 内存和并发，并关闭配置缓存和堆转储，避免套用本机的 8GB 堆设置或持久化签名数据。

每次发布新版本，先在本机修改并提交版本，再运行 Actions：

```powershell
.\dev.cmd -Action version -Version 0.2.0  # 或 -BumpBuild；按实际版本选择
git add pubspec.yaml
git commit -m "Bump app version"
git push
```

沿用同一签名、相同 application ID，并确保构建号大于手机上已安装的版本。
正式包与调试包 application ID 不同，可以并存；构建成功不代表已完成真机播放和下载验收。

## 常见问题

- **没有 Run workflow**：确认工作流已推送到默认分支、Actions 未禁用且账号有写权限。
- **检查仓库和签名配置失败**：检查仓库私有状态、默认分支和四项 Secret 的拼写/是否为空；不是 Variables。
- **签名密码错误或 Base64 无效**：重新运行本机复制助手，逐项替换四项 Secrets；不要生成新密钥。
- **网络下载失败**：可以在同次运行中重新运行失败任务；不要给云端配置你电脑的 localhost 代理。
- **APK 不能覆盖安装**：核对 application ID、签名证书指纹、构建号；不要先卸载来掩盖签名错误，否则会丢应用数据。
- **日志公开问题**：不要移除私有仓库检查来临时绕过分发限制，也不要把签名信息加入调试日志。

官方说明：[创建 Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)、
[手动运行](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)、
[下载制品](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)。
