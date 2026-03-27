# Whisky YAAGL Fork

[English README](README.md)

这是一个更面向普通用户的 `Whisky` 分支，主要用于在 macOS 上更方便地运行 HK4e / 原神相关环境。

它不是官方版 Whisky。

## 这个版本适合谁

如果你希望：

- 在创建容器时直接选择不同的 Wine 运行时
- 少做手动注册表和补丁操作
- 更方便地设置 HK4e / 原神启动参数
- 更容易查看日志、打开任务管理器、排查启动问题

那么这个分支就是为这类使用场景做的。

## 主要功能

- 创建容器时可选择多个 Wine 运行时
- 支持 `SteamPatch`、`Retina 模式`、`HDR`、`自定义分辨率`
- 可保存游戏可执行文件路径，并在容器首页置顶显示
- 支持每个容器单独设置代理服务器
- 支持快速打开 `C 盘`、终端、任务管理器、控制面板、注册表编辑器、Wine 配置
- 改善了启动反馈和日志定位

## 系统要求

- Apple Silicon Mac
- macOS 14 或更高版本

## 下载方式

不需要本机安装 Xcode。

1. 打开仓库的 `Actions`
2. 进入最新成功的 `Build (macOS)`
3. 在页面底部的 `Artifacts` 下载 `Whisky.app.zip`
4. 用 `Finder` 双击解压
5. 将 `Whisky.app` 拖到 `/Applications`
6. 从“应用程序”里打开

如果首次打开被系统拦截：

1. 打开“系统设置” -> “隐私与安全性”
2. 找到拦截提示，点击“仍要打开”

## 首次启动

首次打开时，应用会引导你下载 Wine 运行时。

- 推荐默认使用 `Wine 11.4 DXMT (signed)`
- 运行时下载一次后会缓存到本地，不需要每次重复下载

## 快速上手

1. 从仓库的 `Actions` 下载 `Whisky.app`（见“下载方式”）。
2. 首次启动时下载 Wine 运行时（推荐：`Wine 11.4 DXMT (signed)`）。
3. 创建容器：
   - 选择 HK4e 区服：`OS`（国际服）或 `CN`（原神）
   - 可选开启 SteamPatch / HDR
   - 可选填写代理 IP + 端口
4. 在容器的 HK4e 配置里选择游戏 exe（OS 选 `GenshinImpact.exe`，CN 选 `YuanShen.exe`）。
5. 从置顶的程序（或程序列表）启动。

## 创建容器时可以设置什么

创建容器时可选择：

- Wine 运行时
- Windows 版本
- Retina 模式
- HK4e 区服（OS / CN）
- SteamPatch
- HDR
- 代理服务器 IP 和端口
- 自定义分辨率
- 可选的游戏可执行文件路径（用于自动置顶）

这些配置会尽量持久保存，避免每次启动时重复做相同操作。

## HK4e / 原神相关功能

在 `Bottle -> Config -> HK4e` 中可以设置：

- 游戏可执行文件
- 将左侧 Command 映射为 Ctrl
- SteamPatch
- HDR
- 自定义分辨率

这一版会尽量把 HK4e 相关设置保留在容器里，只在确实发生变化时才重新写入。

## 常用工具

每个容器都可以快速打开：

- `C 盘`
- 终端
- 任务管理器
- 控制面板
- 注册表编辑器
- Wine 配置
- 日志目录 / 最新日志

如果你的游戏安装在外置磁盘上，而磁盘已弹出或未连接，应用会在启动时弹窗提示“找不到目标文件”。

## 代理服务器

本分支支持在“创建容器”和“容器配置”中设置代理服务器。

- 代理按容器保存
- 会写入 Wine 的 Internet Settings
- IP 和端口分开填写
- 之后可以随时在配置页修改或关闭

## 数据存储目录

本分支把数据存放在：

- `~/Library/Application Support/Whisky/`
  - `Bottles/`
  - `Libraries/`
  - `Downloads/`
- `~/Library/Logs/Whisky/`

如果检测到旧版 Whisky 数据，会尽量在首次启动时自动迁移。

## 日志位置

日志目录：

- `~/Library/Logs/Whisky/`

当前版本会尽量把一次启动过程写进同一个日志文件，方便排查问题。

## 证书导入

这个分支支持对所选 Wine 运行时做证书补丁，让新建 prefix 时自动导入需要的根证书。

- 证书内容已随 App 打包
- 这样可以减少创建容器时因为网络问题导致失败的情况

## 这个分支不会做什么

- 不会修改 `/etc/hosts`
- 不是官方 Whisky 发布版本
- 目前没有 Homebrew cask

## 遇到问题时建议先检查

1. `~/Library/Logs/Whisky/` 下最新日志
2. 游戏 exe 路径是否仍然存在
3. 如果游戏装在外置磁盘，磁盘是否仍然挂载

## 致谢

这个项目建立在 Whisky 以及 Wine、DXVK、MoltenVK、CrossOver、Apple D3DMetal 等项目之上。

特别感谢：

- [YAAGL](https://github.com/yaagl/yet-another-anime-game-launcher)：提供了很多 HK4e 相关流程的参考实现与思路。
- [Whisky](https://github.com/Whisky-App/Whisky)：提供了本分支的基础框架与 macOS 上的 Wine bottle 体验。
- OpenCode (gpt-5.2)：移植实现与文档整理。

也建议支持 upstream Whisky 和相关上游项目。
