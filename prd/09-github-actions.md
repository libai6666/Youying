# GitHub Actions 云端正式 APK

这套流程在 GitHub 托管的 Ubuntu 24.04 上安装 JDK 17、Flutter 3.47.7、Android Platform 36、
Build-Tools 36.0.0 和 NDK 28.2.13676358，沿用 `scripts/dev.ps1` 的依赖、静态分析、测试、正式构建和验签。
不使用本机的 `127.0.0.1:7897` 代理或 `.local/toolchain.ps1`，也不在云端重新生成签名。

## 1. 上传构建配置

工作流文件是 `.github/workflows/android-release.yml`。修改需提交到仓库默认分支，当前为 `main`；
推送到 `main` 后会自动生成正式通用 APK；这会使用 GitHub Actions 和存储额度。
其他分支、PR、fork PR 和 tag 不触发本流程。合并 PR 到 `main` 会触发一次构建。

首次启用自动构建，请先确认下面第 2 节的四项 Secrets 已保存，再检查并提交改动。
以下命令包含当前功能改造、回归测试及构建配置；不要遗漏新的脚本和测试文件：

```powershell
git status --short
git add lib test scripts .github/workflows/android-release.yml README.md prd/09-github-actions.md prd/10-migration-checklist.md
git diff --cached --stat
git commit -m "Improve media aggregation and automate signed Android builds"
git push
```

推送含此工作流的提交后，即开始首次自动打包，无需再点 Run workflow。
后续推送通常只需提交自己修改的源码/测试；上面的清单是本轮改造的首次提交示例。
不要用 `git add -f` 添加被忽略的密钥、APK 或本机环境，也不要把工程外的 APK 取证资料提交进去。
工作流必须进入默认分支后，Actions 页面才会提供手动运行按钮。

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

剪贴板操作失败时会先自动重试；仍不可用时可暂停剪贴板管理器、同步或远程剪贴板功能，再按回车重试当前操作，
或输入 `Q` 退出。已保存到 GitHub 的 Secrets 不受影响，退出时也会尝试清空剪贴板。
若前三项已保存、只缺最后一项，可从项目目录单独恢复，不用重填前三项：

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\copy-github-signing.ps1 -StartAt YOUYING_KEY_PASSWORD
```

`-StartAt` 也接受其余三个 Secret 名称，会从指定项继续到最后一项；网页已有同名 Secret 时点击铅笔更新，不要重复新建。

Base64 只是编码，不是加密；这个值等同于持有私钥文件，必须放 **Secrets**，不能放 Variables、源码、Issue 或聊天。
GitHub 保存后不再显示 Secret 原值，不影响 Actions 使用。原电脑的 `signing.clixml` 不能在 Linux 上解密，不能上传代替这四项。
四项值应全部来自现有签名，以保证之后的 APK 能覆盖升级。密钥和密码仍需分别离线加密备份。

## 3. 自动或手动构建

### 默认：推送后自动打包

`git push` 到 `main` 成功后，在 [Actions → Android 正式 APK](https://github.com/libai6666/Youying/actions/workflows/android-release.yml)
查看本次运行。默认是 `universal`，包含 Android ARM、ARM64 和 x64，兼顾手机与 MuMu。
一次 push 无论有几个提交都只触发一次；没有新提交时再次执行 `git push` 不会触发。
自动触发目前固定为 `main`，仍要求它是默认分支；如果以后更改默认分支，须同时修改工作流的 `push.branches`。

### 可选：手动选择架构

1. 确认仓库是 **Private**。本流程拒绝公开仓库，避免签名 APK 通过公开 Actions 制品分发；不会替你修改仓库可见性。
2. 打开 [Actions → Android 正式 APK](https://github.com/libai6666/Youying/actions/workflows/android-release.yml)。
3. 如果 GitHub 提示先启用 Actions，请由仓库管理员确认启用。
4. 点 **Run workflow**，分支选择 **main**（默认分支）。
5. `architecture` 选择 `universal`（通用包）或 `arm64`（较新 Android 手机，包更小）。
6. 点确认运行，进入本次运行查看各步骤。

首次需下载工具链和 Android/Maven 依赖；后续复用 Flutter/Pub/Gradle 依赖缓存，仍会受 GitHub 和仓库服务状态影响。
工作流最长运行 60 分钟，不自动重跑失败任务。私有仓库使用你账户的 Actions/存储额度，额度、计费和预算以 GitHub 页面为准。
同分支同一时刻只运行一个构建，不主动取消已经开始的任务；若快速连续推送，GitHub 可能用较新的待运行任务替换旧的待运行任务。

此流程由 `main` 的 push 或 `workflow_dispatch` 触发，不在 PR、fork PR 或 tag 时调用签名。
GitHub Token 仅 `contents: read`，不自动创建 Release、不上传到应用商店、不回写源码或创建机器人提交。
只有有写权限、可以运行流程及修改仓库的可信协作者才应接触这个仓库和签名配置。

## 4. 下载和安装

运行成功后，在运行页面底部 **Artifacts** 下载 `youying-release-版本-架构-运行号-重试号`。
网页下载的是 ZIP，先解压，再把里面带时间戳的 `.apk` 发到手机安装；不要把 ZIP 当 APK 安装。
制品包含正式 APK、`SHA256SUMS.txt` 和 `BUILD-INFO.txt`（实际版本、架构、源码提交和运行链接），
只保留 7 天，不会上传 JKS、密码、DPAPI 配置或整个工作区。
下载需要仓库读权限。请及时保存需要保留的 APK，别把 Actions 制品当作长期备份。

工作流调用 `apksigner verify --verbose --print-certs` 后才复制和上传 APK。
日志中的签名证书 SHA-256 应与原电脑密钥目录中的 `certificate-sha256.txt` 一致；二者是证书指纹，
不要与 `SHA256SUMS.txt` 中整个 APK 的文件 SHA-256 混淆。
密钥只解码到运行器临时目录，目录权限 700、文件权限 600，成功/失败均清理；不进入依赖缓存或制品。
云端专门降低 Gradle 内存和并发，并关闭配置缓存和堆转储，避免套用本机的 8GB 堆设置或持久化签名数据。

## 5. 手动管理版本，云端只打包

**版本以你提交的 `pubspec.yaml` 为准，工作流不再自动加 1。**
例如提交的是 `0.2.0+10`，自动 push 构建、手动构建、失败后重跑都会使用 `0.2.0+10`。
GitHub 的运行序号只区分运行记录/制品名称，不参与版本计算，也不回写版本文件。

### 本地只改版本，不打包

在项目根目录执行下面任意一种命令：

```powershell
.\dev.cmd -Action version -ShowVersion                 # 查看，不修改
.\dev.cmd -Action version -Version 0.2.0               # 设置显示版本名，构建号加 1
.\dev.cmd -Action version -BumpBuild                   # 保留显示版本名，构建号加 1
.\dev.cmd -Action version -Version 0.2.1 -BuildNumber 10 # 指定两者，构建号允许相同或回退
```

这些命令只修改版本字段，不运行 Flutter 构建、不签名、不提交或推送。
只在本地修改或提交、暂不推送 `main`，就不会触发云端打包。
上面是独立示例，不必依次执行；显式构建号请按实际已发布版本调整。

### 准备打包时再提交版本并推送

```powershell
.\dev.cmd -Action version -Version 0.2.0
git add pubspec.yaml
git commit -m "Bump app version"
git push
```

每次发布升级包都由你手动设置 **Android 构建号 N**，范围为 1 到 2100000000；
脚本允许相同或回退并只给出警告，但低于设备已安装构建号的 APK 无法覆盖安装，
正常发版仍应保持递增。只增显示版本名但复用旧构建号不适合作为新升级包。
忘记改版本时，push 仍会打包，但版本不会变化。
如果曾分发过旧自动递增逻辑生成的包，请查看其 `BUILD-INFO.txt` 或已安装版本，
下一次手动指定的构建号应大于那个包，不能只依据本地旧版本号加 1。
沿用同一签名、相同 application ID，并保证构建号递增才能正常覆盖升级。
正式包与调试包 application ID 不同，可以并存；构建成功不代表已完成真机播放和下载验收。

## 常见问题

- **没有 Run workflow**：确认工作流已推送到默认分支、Actions 未禁用且账号有写权限。
- **push 后没运行**：确认推送的是 `main`、确实包含新提交且已提交工作流；其他分支、仅 tag 或 `Everything up-to-date` 不会触发。
- **自动构建占用额度**：每次推送 `main` 都可能构建；先在功能分支开发，准备好后合并到 `main`。
- **检查仓库和签名配置失败**：检查仓库私有状态、默认分支和四项 Secret 的拼写/是否为空；不是 Variables。
- **签名密码错误或 Base64 无效**：重新运行本机复制助手，逐项替换四项 Secrets；不要生成新密钥。
- **网络下载失败**：可以在同次运行中重新运行失败任务；不要给云端配置你电脑的 localhost 代理。
- **APK 不能覆盖安装**：核对 application ID、签名证书指纹、构建号；不要先卸载来掩盖签名错误，否则会丢应用数据。
- **日志公开问题**：不要移除私有仓库检查来临时绕过分发限制，也不要把签名信息加入调试日志。

官方说明：[创建 Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)、
[push 触发](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#push)、
[运行序号](https://docs.github.com/en/actions/reference/workflows-and-actions/variables)、
[手动运行](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)、
[下载制品](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)。
