# 柚影 / Youying

独立 Flutter Android 媒体客户端，当前为开发原型；版本以 `pubspec.yaml` 为准。
界面、源适配、收藏、历史、播放器桥接与下载逻辑均为独立重写，**不是原 APK 的完整源码**。
预设 7 个公开源：保留 360、极速，新增猫眼（第三方）、豪华、光速、如意、红牛；新装默认启用。
七源在本机通过搜索、详情、分类及首页接口检查；红牛媒体清单 TLS 失败，不能确认可播放，设置中有明确提示。
升级一次性补充 5 个新源，并移除无尽、量子的旧失效接口；保留自定义接口和启停状态，不恢复已删除的旧预设。
可启停或删除；本轮迁移后删除的新源也不会因重启而恢复。不改动收藏、历史、播放进度或下载记录。
首页会请求所选已启用源的分类、近期内容和剧集/综艺/动漫列表；不会自动拉取远程源配置。
界面按参考截图调整为“首页 / 排行榜 / 我的”，不含登录和广告。排行榜采用源返回顺序，明确标注非热度榜。
公开收录不等于内容授权、永久可用或已完成播放/下载验收。

## 快速开始（Windows）

要求：Flutter **3.47.7** / Dart **3.13.5**、JDK **17**、Android SDK Platform **36**、
Build-Tools、Platform-Tools、NDK **28.2.13676358**、Git。先安装并加入 PATH，接受 Android SDK 许可证。
本机已配置的工程会自动加载被 Git 忽略的 `.local/toolchain.ps1`，无需每次手动设置 PATH；
长期签名保存在工程外的 `$HOME\AndroidKeys\youying`，具体恢复/备份方法见[正式签名文档](prd/03-build-signing.md)。
如使用其他 Flutter 版本，需自行确认 AGP/Kotlin/NDK 兼容性，不能只看 Dart 版本。

在项目根目录打开终端：

```powershell
.\dev.cmd                         # 交互选择菜单
.\dev.cmd -Action doctor          # 检查环境
.\dev.cmd -Action check           # 依赖、分析、单元/组件测试
.\dev.cmd -Action debug           # 唯一 USB 手机，热重载调试
.\dev.cmd -Action debug -Device SERIAL
.\dev.cmd -Action test            # debug 签名通用测试 APK
.\dev.cmd -Action release         # 自己的签名密钥，分析/测试后构建
.\dev.cmd -Action signing         # 仅首次初始化；已有长期密钥不会覆盖
.\dev.cmd -Action github-signing  # 引导复制四项 GitHub Actions 签名 Secrets，不上传、不显示值
.\dev.cmd -Action version -ShowVersion        # 只查看版本，不修改
.\dev.cmd -Action version -BumpBuild          # 保留版本名，构建号加 1
.\dev.cmd -Action version -Version 0.2.0      # 设置版本名，构建号自动加 1
.\dev.cmd -Action git             # 已有仓库只显示状态；缺失则初始化 main
```

可直接运行 `scripts/dev.ps1`。`.cmd` 只为当前 PowerShell 子进程选择 `RemoteSigned`，
不修改机器/用户策略，不绕过组织组策略；受管设备需先得到管理员允许。
脚本不自动安装工具、不修改 Git 用户信息、不自动提交或推送。

输出在 `dist/test/`、`dist/release/`，包含时间戳；控制台输出 APK 路径和 SHA-256。
正式构建没有 debug 签名回退，Android debug 证书也会被拒绝；APK 经 apksigner 验签成功才输出到 dist。

版本格式为 `X.Y.Z+N`：前半是显示版本名，`N` 是 Android 构建号，升级必须递增，不能在新版本名下重置为 1。
菜单 **8** 可以交互查看/修改；也可用 `-Action version -Version 0.2.1 -BuildNumber 10` 显式设置两者。
脚本拒绝相同/降低的构建号及错误格式，只修改版本字段，保留注释、编码和换行，不触碰签名、不构建 APK。
只查看请使用 `-ShowVersion`；每次需要发新包时先修改版本，再执行 `-Action release`。

## 文档

GitHub 云端正式包：先按[配置说明](prd/09-github-actions.md)保存四项仓库 Secrets，
再到 Actions 手动运行 **Android 正式 APK**，成功后下载 Artifacts 中的 APK 与 SHA-256。
流程只允许私有仓库的默认分支，不自动发布 Release，不使用本机代理或 Windows DPAPI 文件。

- [项目状态、功能边界及产品约定](prd/01-product-status.md)
- [手机 USB 调试与故障排查](prd/02-usb-debug.md)
- [测试包、正式签名与发布清单](prd/03-build-signing.md)
- [资源兼容协议、下载范围及本轮验证](prd/04-resource-adapter.md)
- [公开源首次调查](prd/05-public-source-research.md)
- [多源预设、抽查结果与原应用界面差异](prd/06-source-presets-and-ui-gap.md)
- [三栏页面对齐、数据来源与验收边界](prd/07-ui-alignment.md)
- [新增五源、清理失效预设及升级验证](prd/08-public-sources-v2.md)
- [GitHub Actions 云端正式打包](prd/09-github-actions.md)

`lib/` 是 Dart 代码，`android/` 是 Android/Media3 桥接，`test/` 是自动化测试，
`prd/` 是项目文档，`scripts/` 是本机工作流。
`pubspec.lock` 和 Gradle Wrapper 属于版本管理；缓存、构建产物、SDK 路径、签名与环境秘密不入 Git。

## 身份与数据

正式包：`dev.youying.app`；调试/测试包：`dev.youying.app.debug`（“柚影 · 测试”）。
两者可同时安装；不同包的数据相互独立，也不自动迁移旧重建包或原 APK 的收藏/历史。
本名称/包标识是新工程开发标识，不代表已登记商标或拥有同名域名；发布前须确认最终身份。
新的橙色播放图标为本工程独立制作，不复用原 APK 的图标。

原分析资料保留在独立的 `apk-analysis-085e4792` 目录，没有搬入本 Git 工程。
可编译不等于已完成手机、网络源和实际播放验收；正式签名也不等于已符合应用商店发布要求。
