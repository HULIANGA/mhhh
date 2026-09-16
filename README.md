# MHHH · Fieldnotes

个人开发的 3D 俯视角狩猎游戏。使用 **Godot 4.7.2 + GDScript**，交付 **Windows x86_64 桌面版与桌面浏览器版**；Mac 上通过浏览器验证。

当前阶段：**M4 美术与表现替换**。M4.1 工具链与 M4.2 表现解耦均已通过，现进入 M4.3 大剑模型与判定对齐；多种普攻动作暂缓到后续迭代。

M2 已于 2026-09-16 通过输入、移动和战斗回归及浏览器人工验收，Web 与 Windows 构建成功；Windows 实机兼容检查保留到最终跨平台验收。详情见 [M2 验收记录](docs/M2_ACCEPTANCE.md)。

## 启动浏览器试玩

需要 Python 3.11+、curl 和网络。首次安装引擎到 `.tools/`，不会写入系统应用目录。下载可重复运行；工具和构建产物不进入 Git。

```sh
python3 tools/setup.py
python3 tools/dev.py preview-local
```

打开 **http://127.0.0.1:8060**。Windows 上命令中的 `python3` 可替换为 `py -3`。预览服务只绑定本机，停止时按 Ctrl+C。

需要让同一局域网内的其他设备访问时，改用：

```sh
python3 tools/dev.py preview-lan
```

终端会显示局域网访问地址。`preview-local` 仅监听 `127.0.0.1`，`preview-lan` 监听所有网络接口；日常本机调试优先使用前者。

已有引擎时可设置 `GODOT_BIN` 为可执行文件路径；导出仍需要运行安装脚本获取匹配模板。不要直接双击 `index.html`，必须通过 HTTP 服务加载。

M4 美术资产锁定 **Blender 5.2.2 LTS**。工具会依次查找 `BLENDER_BIN`、项目 `.tools/Blender.app` 和 macOS 的标准 Blender 应用位置；未安装时可运行 `python3 tools/setup_blender.py` 下载到 `.tools/`，不会写入系统应用目录。游戏运行和普通 GLB 校验不依赖 Blender，只有重新生成美术资产时才需要。

| 操作 | 效果 |
|---|---|
| WASD | 屏幕方向移动 |
| 鼠标移动 | 控制角色朝向，脚前金色箭头表示正面 |
| 鼠标左键 | 单击执行一次普攻；持续按住约 0.28 秒后自动重复，每刀完整收刀后才进入下一刀 |
| 鼠标右键 | 按住蓄力；达到一档后松开释放，未达到一档则取消；满蓄力自动释放二档攻击 |
| 空格 | 朝移动方向翻滚；无移动输入时朝角色正面翻滚 |
| Esc / Pause | 暂停或继续 |
| R | 重置玩家、体力、怪物和训练靶 |
| F1 | 显示帧率、坐标和移动距离 |

右后方的场地怪物会追近玩家并按距离使用三种攻击：贴身时以横扫为主，但保留低概率扑击和冲撞；中距离以扑击为主，较远时使用长前摇冲撞。超过约 12 米时怪物会先追近而不是原地攻击；扑击／冲撞交界处的权重随距离连续变化，越远越偏向冲撞。有替代招式时连续两次同招后会强制换招，重复招式后的冷却也更长。扑击前会显示短距离落点圈，随后抬起前腿明显腾空；冲撞前会后撤刨地、压低并点亮双角，同时显示长条路径。三招都在前摇结束时锁定方向；扑击和冲撞使用覆盖每帧实际移动路径的连续物理探针，冲撞可以持续约 14.4 米。冲撞会撞碎场内的木质路障；撞上中央石柱或场地边界等不可摧毁物体时，则会侧翻倒地约 2.2 秒。离开锁定路径或翻滚都可规避，每次攻击最多扣血一次。蓝灰色收招、攻击冷却或倒地阶段可以安全反击，怪物身体接触本身不造成伤害。击杀怪物会显示胜利，玩家生命归零会显示失败并冻结战斗；同一物理帧双方同时倒下时固定判负。按 R 可恢复双方位置、生命、决策序列和障碍物并立即开始新一局。中央训练靶仍可用于练习。普攻不消耗体力；蓄力期间逐渐消耗体力，满蓄力累计消耗 30，提前释放或取消只消耗已经扣除的部分；开始翻滚扣 24。开始蓄力仍需至少 30 体力。攻击期间不可翻滚取消，蓄力期间可以用翻滚放弃蓄力。

## 检查和导出

```sh
python3 tools/dev.py check     # 导入资源、检查脚本
python3 tools/dev.py test      # 使用真实场景运行输入、移动、战斗和生命回归
python3 tools/dev.py art-check # 校验已提交的 GLB，并通过 Godot 检查骨架、动画和挂点
python3 tools/dev.py art-export # 使用 Blender 重新生成并校验 .blend/.glb 资产
python3 tools/dev.py web       # build/web/index.html
python3 tools/dev.py windows   # build/windows/MHHH.exe
python3 tools/dev.py all       # 两个平台一起导出
python3 tools/dev.py serve-local # 仅本机启动服务，不重新构建
python3 tools/dev.py serve-lan   # 局域网启动服务，不重新构建
```

修改代码后重新运行 `web` 并刷新浏览器；`serve-local` 和 `serve-lan` 不会自动重建。旧命令 `preview`、`serve` 仍兼容，并继续按仅本机模式运行。Windows 可执行文件需要在 Windows 实机验收，Mac 上导出成功不代表已通过运行验收。

## 用编辑器学习

打开 `.tools/Godot.app`，导入根目录的 `project.godot`。Windows 则打开 `.tools/` 中的 Godot exe。主场景为 `scenes/main.tscn`。

- `scripts/player.gd`：消费统一输入，控制移动、朝向、体力与战斗状态机。
- `scripts/combat_action_data.gd`、`data/*.tres`：玩家和怪物招式的伤害、消耗、范围与动作时长配置。
- `scripts/monster.gd`、`scripts/monster_attack_data.gd`、`scenes/monster.tscn`：怪物生命、受击、死亡、追击、共用攻击状态机与程序化占位外观。
- `scripts/training_dummy.gd`：保留用于 M2 回归的训练靶生命、单次攻击去重与命中反馈。
- `scripts/input/`：统一输入帧与键鼠适配器，接口说明见 [统一游戏输入](docs/INPUT.md)。
- `scripts/follow_camera.gd`：镜头距离和跟随速度。
- `scripts/arena.gd`：地面、实体边界和检查点。
- `scripts/main.gd`、`scripts/hud.gd`：流程、暂停与界面。
- `web/shell.html`：浏览器加载页；游戏本体始终由 Godot 运行。

**调参练习**：修改 `data/` 中一次攻击的前摇、收招或伤害，重新导出 Web 后只比较这一项变化。动作越重，不代表所有时间都必须更长；优先让前摇可读、命中清楚、收招有代价。

开发里程碑见 [开发计划](docs/DEVELOPMENT_PLAN.md)，当前阶段详见 [M4 分步实施计划](docs/M4_PLAN.md) 与 [M4 验收](docs/M4_ACCEPTANCE.md)，已完成阶段见 [M3 验收](docs/M3_ACCEPTANCE.md)、[M2 验收](docs/M2_ACCEPTANCE.md) 和 [M1 验收](docs/M1_ACCEPTANCE.md)。所有当前几何模型与图标均在项目中制作，不使用外部美术素材。
