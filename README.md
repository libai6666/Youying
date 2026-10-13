# 柚影 / Youying

独立 Flutter Android 媒体客户端，版本 `0.1.0+1`，当前为开发原型。
界面、源适配、收藏、历史、播放器桥接与下载逻辑均为独立重写，**不是原 APK 的完整源码**。
默认没有任何内置影视源，只访问用户主动配置的 HTTPS 地址。

## 快速开始（Windows）

要求：Flutter **3.47.7** / Dart **3.13.5**、JDK **17**、Android SDK Platform **36**、
Build-Tools、Platform-Tools、NDK **28.2.13676358**、Git。先安装并加入 PATH，接受 Android SDK 许可证。
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
.\dev.cmd -Action git             # 已有仓库只显示状态；缺失则初始化 main
```

可直接运行 `scripts/dev.ps1`。`.cmd` 只为当前 PowerShell 子进程选择 `RemoteSigned`，
不修改机器/用户策略，不绕过组织组策略；受管设备需先得到管理员允许。
脚本不自动安装工具、不修改 Git 用户信息、不自动提交或推送。

输出在 `dist/test/`、`dist/release/`，包含时间戳；控制台输出 APK 路径和 SHA-256。
正式构建没有 debug 签名回退，Android debug 证书也会被拒绝；APK 经 apksigner 验签成功才输出到 dist。

## 文档

- [项目状态、功能边界及产品约定](prd/01-product-status.md)
- [手机 USB 调试与故障排查](prd/02-usb-debug.md)
- [测试包、正式签名与发布清单](prd/03-build-signing.md)

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
