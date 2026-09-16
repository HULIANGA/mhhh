# M4 验收记录

## 当前进度

M4 按 [分步实施计划](M4_PLAN.md) 逐项开发和验收。每一步通过后独立提交，M4.8 完成最终资产、全量回归、双平台构建与连续 5 场人工试玩后再标记整个里程碑完成。

| 步骤 | 当前结果 |
|---|---|
| M4.1 Blender/GLB 工具链与空资产契约 | 已通过 |
| M4.2 表现适配层与判定解耦 | 已通过 |
| M4.3 大剑模型与判定对齐 | 未开始 |
| M4.4 女性猎人低模、骨架与基础动作 | 未开始 |
| M4.5 双角荒原兽低模、骨架与基础动作 | 未开始 |
| M4.6 顶部怪物 UI 与战斗可读性 | 未开始 |
| M4.7 原创合成音效 | 未开始 |
| M4.8 全量回归、构建与人工验收 | 未开始 |

## M4.1 工具链与资产契约

2026-09-16 使用系统安装的 Blender 5.2.2 LTS 完成第一份 `.blend → .glb → Godot` 端到端资产导出。本步骤新增：

- Blender 5.2.2 自动发现与严格版本检查，支持 `BLENDER_BIN`、项目 `.tools/` 和 macOS 标准应用位置。
- Apple Silicon macOS 与 Windows x86_64 的项目内 Blender 安装脚本，下载包使用官方 SHA-256 校验。
- Blender 无界面资产生成脚本，同时保存可编辑 `.blend` 源文件与 Godot 使用的 `.glb`。
- 不依赖 Blender 的 GLB 2.0 结构校验，检查网格、骨架、动画、材质和七个稳定挂点。
- Godot 真实导入测试，检查 `Skeleton3D`、`AnimationPlayer`、挂点节点以及循环动画契约。
- `art-export`、`art-check` 两个开发命令；常规 `test` 也会执行已提交资产的结构和 Godot 导入测试。

Godot 首次扫描时会把仓库中的 `.blend` 当作运行时资源，并在 headless 导入中要求编辑器 Blender 路径。最终通过 `art/blender/.gdignore` 明确隔离美术源文件和作者脚本，只让 `assets/models/*.glb` 进入运行时导入及平台构建。

Blender/GLB 源动作 `idle_loop` 在 Godot 中按导入器约定变为运行时动画 `idle`，同时保留循环模式。后续所有 `*_loop` 动作均按同一规则处理，适配层不得直接假设源动作名等于运行时名称。

重复执行 `art-export` 后，GLB 的 SHA-256 保持一致；`.blend` 会因 Blender 保存元数据变化产生不同二进制哈希，因此验收采用结构契约而非 `.blend` 字节一致性。

## M4.1 自动回归与构建

2026-09-16 运行新增资产测试及 M1～M3 十一组既有测试，十二组全部通过。资产测试包含：

- GLB 2.0 头、网格、蒙皮骨架、动画和材质完整。
- `WeaponSocket`、`BladeBase`、`BladeTip`、左右角 Base/Tip 全部存在。
- Godot 可以实例化 GLB，并生成 `Skeleton3D` 与 `AnimationPlayer`。
- `idle_loop` 以运行时 `idle` 名称导入且保持循环。

同日完成 Web 与 Windows x86_64 release 构建。契约资产当前不进入主场景，因此本步骤没有玩家可见变化，无需单独浏览器手感验收；正式模型接入从 M4.2 起逐步进行浏览器验收。

## M4.2 表现适配层与判定解耦

2026-09-16 完成占位表现适配层。`HunterPresentation` 和 `MonsterPresentation` 分别挂载在玩家、怪物子场景中；当前占位几何仍由适配层初始化流程生成，玩法控制器只通过稳定的 `BladeBase`、`BladeTip`、`HornLBase`、`HornLTip` 节点读取命中轨迹。后续满足同名挂点契约的 GLB 或测试模型可替换表现而不改变攻击时序和伤害逻辑。

本步骤同时保留原有走路、攻击、扑击、冲撞、受击、倒地表现入口，并将剑刃和双角判定从网格类型及固定局部长度改为挂点轨迹。M1～M3 回归及适配后的剑击、横扫、扑击、冲撞、受击和重开测试全部通过。

新增 `tests/presentation_test.gd` 验证两个适配器、武器／双角挂点存在并且挂点长度覆盖当前可见占位表现。
