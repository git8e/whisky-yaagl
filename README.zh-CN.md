# Whisky YAAGL Fork

[English README](README.md)

这是一个面向普通用户的 macOS 游戏启动与管理工具，主要用于更方便地运行一些特定的动漫游戏，但不限定于这些游戏。它基于 [Whisky](https://github.com/Whisky-App/Whisky) 开发，参考了 [YAAGL](https://github.com/yaagl/yet-another-anime-game-launcher) 的 Wine 环境配置与补丁方案，使用逻辑更接近于 CrossOver，能帮助你更轻松地完成游戏配置、启动与日常管理。

## 主要功能

- 创建容器时可选择多个 Wine 版本
- 支持原版 YAAGL 的部分补丁
- 每个容器独立 Wine 运行环境
- 支持同时运行多个相同或者不同的游戏
- 支持每个容器单独设置代理服务器
- 支持快速复制（APFS clone），多份重复文件只占用单份空间

## 系统要求

- Apple Silicon Mac
- macOS 15 或更高版本

## 是否安全

使用风险自负。或使用一个新的零氪账号体验。

## 安装方式

1. 优先从仓库的 `Releases` 下载最新的 `Whisky.app.zip`。
2. `Actions` 里的构建仅建议用于尝鲜和测试，可能不稳定。
3. 用 `Finder` 双击解压。
4. 将 `Whisky.app` 拖到 `/Applications`。
5. 从“应用程序”里打开；首次启动时会引导你下载 Wine 运行时，推荐默认使用 `Wine 11.4 DXMT (signed)`。
6. 运行时下载后会缓存到本地；每个容器会基于所选运行时生成自己的独立 runtime。

如果首次打开被系统拦截：

1. 打开“系统设置” -> “隐私与安全性”
2. 找到拦截提示，点击“仍要打开”

## 快速上手

1. 从仓库的 `Releases` 安装 `Whisky.app`（见“安装方式”）。
2. 首次启动时下载 Wine 运行时（推荐：`Wine 11.4 DXMT (signed)`）。
3. 选择好游戏可执行文件路径，并创建容器。
4. 补丁配置建议先保持默认选项，不确定时不要随意改动。
5. 从置顶的程序（或程序列表）启动。

## 相比 YAAGL 的优化点

本分支参考了 YAAGL 的 HK4e 流程实现思路，但会按 Whisky 的“多容器 / 可预先配置”的使用方式来设计，而不是 YAAGL 更偏“启动时 patch / 运行后 revert”的单目录流程。

- 多容器独立：不同游戏和运行环境可以完全分开，避免互相污染。
- 多容器并行：可同时启动同一款或不同游戏，互不影响。
- 运行更加稳定：如果某个容器损坏，可以直接单独删除重建，无需反复重装应用。
- 可预先配置：大多数选项在创建容器或配置页切换时完成，而不是每次启动时再 patch / revert。
- 可快速切换：Wine 安装包下载后会缓存到本地，切换版本或重建容器时通常不需要重新下载 Wine。
- 原生 macOS App 体验：启动更快，操作更流畅，资源占用更少。

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

## 遇到问题时建议先检查

1. `~/Library/Logs/Whisky/` 下最新日志
2. 游戏 exe 路径是否仍然存在，磁盘是否仍然挂载
3. 使用 HoYoPlay 检查游戏资源完整性

## 致谢

这个项目建立在 Whisky 以及 Wine、DXVK、MoltenVK、CrossOver、Apple D3DMetal 等项目之上。

特别感谢：

- [YAAGL](https://github.com/yaagl/yet-another-anime-game-launcher)：提供了很多 HK4e 相关流程的参考实现与思路。
- [Whisky](https://github.com/Whisky-App/Whisky)：提供了本分支的基础框架与 macOS 上的 Wine bottle 体验。
- OpenCode (gpt-5.2)：移植实现与文档整理。

也建议支持 upstream Whisky 和相关上游项目。
