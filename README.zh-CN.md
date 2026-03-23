# Whisky (YAAGL Fork)

这个仓库是 `Whisky-App/Whisky` 的一个分支，目标是：

- 保持原版 Whisky 的 UI 和启动逻辑不变（仍然用 `wine start /unix` 启动）。
- 让“创建容器（Bottle）时”可以选择不同的 Wine 版本（WhiskyWine 仍保留）。
- YAAGL 风格的补丁/注册表/SteamPatch 等操作只在“创建时做一次”或“手动点按钮”执行，不在每次启动游戏时自动清理/回滚。

## 不需要本机 Xcode 的测试方式

本仓库的 GitHub Actions 会在每次 push 后编译并产出 `Whisky.app.zip`。

1. 打开仓库 Actions -> `Build (macOS)`
2. 进入最新成功的 run
3. 下载 Artifacts 里的 `Whisky.app`（里面有 `Whisky.app.zip`）
4. 本机解压并去除隔离属性后运行：

```bash
unzip -q Whisky.app.zip
xattr -dr com.apple.quarantine "Whisky.app"
open "Whisky.app"
```

## 主要改动

### 创建容器时选择 Wine 版本

创建 Bottle 时可选：

- WhiskyWine（原版默认）
- Wine 11.0 DXMT (signed)
- Wine 10.18 DXMT Experimental
- Wine 9.9 DXMT

如果对应 Wine 运行时未安装：只会下载一次并缓存；也可以手动选择本地压缩包（`.tar.gz` / `.tar.xz`）。

### 容器里的 HK4e 工具（手动/一次性）

在 Bottle -> Config -> HK4e：

- 选择游戏 EXE（会记录路径并自动加 Pin）
- SteamPatch：Apply / Remove（把 `steam.exe` + `lsteamclient.dll` 复制进 prefix）
- 自定义分辨率：Apply / Revert（写/删注册表键）
- Clean HK4e Tweaks（移除 SteamPatch + 回滚分辨率）
- Reset Prefix（重置整个 prefix；保留 Metadata 和 Program Settings）

注意：本 fork 不会像原版 YAAGL 那样每次启动游戏都自动清理/回滚。

### SteamPatch 资源（protonextras）

SteamPatch 会自动从 YAAGL 仓库直接下载所需的 `protonextras`（只下 4 个必需文件）并缓存到本机（只下载一次）。

如果仓库下载不可用，会降级为下载最新 YAAGL 应用 tarball 并解出 `sidecar/protonextras`。

可选：你仍然可以用环境变量覆盖资源路径：`HK4E_RUNTIME_ROOT=/path/to/yaaglwdos`。

## 安全说明

本 fork 不会修改 `/etc/hosts`。
