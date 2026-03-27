# Whisky-yaagl: YAAGL 移植要点 (Skill)

这份文档用来记录把 YAAGL 的 HK4e 相关能力移植到 `whisky-yaagl` 时，必须注意的机制差异、冲突点和推荐实现方式。

## 1. 核心机制差异

### 1) 前缀/容器模型

- YAAGL: 更像“单应用目录 + 单套 Wine + 运行时补丁”，很多操作在启动时临时 patch、运行后 revert。
- Whisky: 多 bottle（多前缀）是第一原则；每个 bottle 都可能提前配置好、长期存在；Wine runtime 是共享资源（多个 bottle 复用同一 runtime）。

结论:

- 任何“写进 prefix 的东西”应尽量做到“可持久化 + 幂等”。
- 任何“写进 wine runtime 的东西”都必须意识到它会影响所有使用该 runtime 的 bottle。

### 2) 补丁策略

- YAAGL: `patch -> run -> revert` 是常态，依赖内部的 `patched`/`installed_dxmt_version` 记录。
- Whisky: 更适合 “提前配置(创建 bottle / 配置页) -> 运行时只读取配置并启动”。

结论:

- 需要把 YAAGL 的“每次启动 patch”的逻辑拆成：
  - bottle 级持久配置（prefix）
  - runtime 级持久配置（wine distribution）
  - 启动时仅做轻量校验（缺了再补齐）

### 3) DXMT 落点与风险

- YAAGL 的 DXMT 0.74+ 逻辑倾向于修改 Wine distribution 的 `lib/wine/x86_64-windows`（builtin 目录），并在启动时设置 `WINEDLLOVERRIDES=d3d11,dxgi=n,b`。
- Whisky 的 runtime 是共享的；对 runtime 打补丁会影响所有 bottle。

冲突点:

- 如果允许“按 bottle 开关 DXMT”，直接 revert runtime 会误伤其它 bottle。
- 如果旧 bottle 曾经把 `d3d11/dxgi` 放进 prefix `system32`，在 0.74+ 模式下仍可能被 `n,b` 优先加载，导致版本混用。

推荐做法:

- 把“是否启用 DXMT 注入”作为 bottle 配置，但 runtime 的修改要谨慎：
  - 开启时：确保 DXMT 文件存在，并对对应 runtime 做一次性补丁（幂等、带备份）。
  - 关闭时：优先只还原 prefix 级改动；如确实要还原 runtime，必须明确告知它会影响同 runtime 的其它 bottle。
- 迁移时：对 0.74+ 模式，建议清理旧 prefix 中的 `d3d11/dxgi/d3d10core` 备份残留，避免加载顺序冲突。

### 4) SteamPatch / HDR / 代理等

- YAAGL: 多为启动期 patch，部分也会 revert。
- Whisky: 更适合在“创建 bottle/配置页”一次写入，启动时只在缺失时补齐。

## 2. 本仓库的落地原则 (whisky-yaagl)

1) Bottle 可以提前配置好

- 创建 bottle 时就把可持久化的配置写入 prefix（如 SteamPatch、代理注册表、HK4e 持久注册表项、DXMT 注入相关文件）。
- 配置页修改时立即应用/撤销，而不是等到下次启动。

2) 多 bottle / 多 runtime 的一致性

- prefix 级操作尽量只影响当前 bottle。
- runtime 级操作以 runtimeId 为单位；不做“自动回滚 runtime”这种容易误伤的行为。

3) 启动时只做“轻量兜底”

- 启动时可以检查：需要的 runtime 是否已被打过补丁、prefix 是否缺文件；缺了再补。
- 避免每次启动都做全量 patch/revert。

## 3. 易踩坑清单

- `WINEDLLOVERRIDES`:
  - `d3d11,dxgi=n,b` 会优先加载 prefix system32 的同名 DLL；如果你想走 runtime builtin 方案，需要确保 prefix 没残留旧版 DLL。
- DXMT 版本记录:
  - YAAGL 用 `installed_dxmt_version` 做分流；Whisky 侧如果也要分流，应把版本记录从“全局单例”升级为“按 runtime 或按 bottle 维度”。
- 共享 runtime 的补丁回滚:
  - 任何 revert runtime 行为都必须意识到它会影响其它 bottle。

## 4. 建议的测试路径

1) 新建 bottle，选择 DXMT runtime，创建完成后不启动游戏，直接打开 prefix 检查关键文件是否存在。
2) 首次启动：确认日志中 `WINEDLLOVERRIDES` 与 DXMT 环境变量符合预期。
3) 同 runtime 创建两个 bottle，分别切换 DXMT 注入开关，验证不会互相破坏。
4) 从旧版本升级：旧 bottle 里曾经注入过 `d3d11/dxgi` 的情况，验证迁移清理逻辑能让游戏正常启动。
