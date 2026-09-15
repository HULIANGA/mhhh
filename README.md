# MHHH · Fieldnotes

个人开发的 3D 俯视角狩猎游戏。使用 **Godot 4.7.2 + GDScript**，交付 **Windows x86_64 桌面版与桌面浏览器版**；Mac 上通过浏览器验证。

当前阶段：**M1 移动训练场**。竞技场、角色移动、鼠标朝向、跟随镜头、三处移动检查点、暂停和重置。背上的大剑是占位外观，当前没有攻击、翻滚和怪物。

已完成 Web 与 Windows 导出，通过物理回归，用户已确认浏览器验收通过。Windows 实机验收仍待完成，详情见 [M1 验收记录](docs/M1_ACCEPTANCE.md)。

## 启动浏览器试玩

需要 Python 3.11+、curl 和网络。首次安装引擎到 `.tools/`，不会写入系统应用目录。下载可重复运行；工具和构建产物不进入 Git。

```sh
python3 tools/setup.py
python3 tools/dev.py preview
```

打开 **http://127.0.0.1:8060**。Windows 上命令中的 `python3` 可替换为 `py -3`。预览服务只绑定本机，停止时按 Ctrl+C。

已有引擎时可设置 `GODOT_BIN` 为可执行文件路径；导出仍需要运行安装脚本获取匹配模板。不要直接双击 `index.html`，必须通过 HTTP 服务加载。

| 操作 | 效果 |
|---|---|
| WASD | 屏幕方向移动 |
| 鼠标移动 | 控制角色朝向，脚前金色箭头表示正面 |
| Esc / Pause | 暂停或继续 |
| R | 重置角色和检查点 |
| F1 | 显示帧率、坐标和移动距离 |

依次走到地面上的 01、02、03 金色标记。进入范围后标记消失，左下角更新进度；完成后仍可自由移动。

## 检查和导出

```sh
python3 tools/dev.py check     # 导入资源、检查脚本
python3 tools/dev.py test      # 使用真实场景和物理运行移动回归
python3 tools/dev.py web       # build/web/index.html
python3 tools/dev.py windows   # build/windows/MHHH.exe
python3 tools/dev.py all       # 两个平台一起导出
python3 tools/dev.py serve     # 仅启动服务，不重新构建
```

修改代码后重新运行 `web` 并刷新浏览器；`serve` 不会自动重建。Windows 可执行文件需要在 Windows 实机验收，Mac 上导出成功不代表已通过运行验收。

## 用编辑器学习

打开 `.tools/Godot.app`，导入根目录的 `project.godot`。Windows 则打开 `.tools/` 中的 Godot exe。主场景为 `scenes/main.tscn`。

- `scripts/player.gd`：消费统一输入，控制移动、朝向与可替换的角色占位模型。
- `scripts/input/`：统一输入帧与键鼠适配器，接口说明见 [统一游戏输入](docs/INPUT.md)。
- `scripts/follow_camera.gd`：镜头距离和跟随速度。
- `scripts/arena.gd`：地面、实体边界和检查点。
- `scripts/main.gd`、`scripts/hud.gd`：流程、暂停与界面。
- `web/shell.html`：浏览器加载页；游戏本体始终由 Godot 运行。

**第一个练习**：把玩家的 `move_speed` 从 `5.2` 改为 `4.2`，重新导出 Web 后试玩，比较移动节奏；再尝试调整镜头 `size`。每次只改一个变量。

开发里程碑见 [开发计划](docs/DEVELOPMENT_PLAN.md)，验收与限制见 [M1 验收](docs/M1_ACCEPTANCE.md)。所有当前几何模型与图标均在项目中制作，不使用外部美术素材。
