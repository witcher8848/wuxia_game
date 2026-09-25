# 武侠 RPG 技术规格 v0.1

> Day 4 输出件
>
> 状态：规格已冻结；当前键盘优先，保留手柄映射，实体手柄实测后移；Windows 真机及独立备份仍待验
>
> 项目代号：`Project Wuming`（无名）
>
> 最后更新：2026-09-16

本文件把 [`03_core_gameplay.md`](./03_core_gameplay.md) 的玩法规则转化为工程约束。它决定引擎、平台、模块边界、输入、存档、Steam 隔离、构建与备份方式；Day 6 建立项目时应按本文执行，而不是重新选择技术栈。

---

## 一、冻结决策

| 项目 | v0.1 决策 | 原因 |
|---|---|---|
| 引擎 | Godot `4.7.2-stable` Standard | 截至 2026-09-11 的最新 4.x 稳定维护版；不使用 4.8 开发快照 |
| 语言 | GDScript，静态类型写法 | 单人开发迭代快，与引擎工具链一致；不引入 .NET 运行时 |
| 渲染器 | Compatibility／`gl_compatibility` | 纯 2D 像素项目不需要 Forward+；优先覆盖较旧 Windows 显卡 |
| 开发环境 | macOS 主开发，Windows 10/11 x64 实机为发布验证环境 | 当前工作区在 macOS；Steam 首发必须在 Windows 真机持续验证 |
| 首发平台 | Windows 10/11 x86_64 | 与六个月 Steam Demo 范围一致 |
| 基础画面 | 640×360、16:9、Viewport 拉伸、整数缩放 | 对应 720p、1080p、1440p 和 4K 的 2×、3×、4×、6×显示 |
| 内容格式 | JSON 静态数据＋CSV 本地化＋Godot 场景 | 文本差异清楚，适合 AI 辅助、自动校验和 Git 审查 |
| 存档格式 | 有版本信封的 JSON，原子写入并保留上一版备份 | 易迁移、易诊断；切片不做加密或二进制私有格式 |
| Steam 接入 | `PlatformService` 接口＋离线实现＋Steam 适配器 | 无 Steam 环境也必须能启动、测试和发布非 Steam 构建 |
| Steam 云 | 优先采用 Steam Auto-Cloud | 不为六个月切片编写自有云同步逻辑 |
| 自动化 | 本地一键构建＋GitHub Actions 无头检查和 Windows 导出 | 每次主分支变更都有可下载验证包 |

Godot 官方归档列出 `4.7.2-stable` 为当前稳定版，而 4.8 仍处于开发阶段；项目固定使用 Standard 版，不下载 .NET 版。[Godot 官方版本归档](https://godotengine.org/download/archive/)

### 1.1 版本升级规则

- `project.godot` 首次创建后记录 `config/features` 对应的 Godot 4.7 特性。
- 六个月切片期间不跨到 Godot 4.8，也不使用 beta、RC 或 dev 构建。
- 若 Godot 发布 4.7.x 新补丁，只在独立分支打开项目副本并完成启动、存档、输入、战斗和 Windows 导出回归后升级。
- 升级前提交全部源文件并复制一份测试存档；Godot 官方也建议在维护版升级前使用版本控制或备份。
- 插件版本跟随项目锁定，不使用自动更新。
- 正式构建在日志和 `build_info.json` 中记录精确引擎版本、提交哈希与内容版本。

### 1.2 本机现状

2026-09-14 已在项目本地 `.tools/godot/` 安装官方 Godot 4.7.2 Standard，`./tools/godot.sh --version` 输出 `4.7.2.stable.official.ed1daf0bf`。官方 SHA-512 已验证编辑器与模板下载包，匹配的 Windows x86_64 Debug／Release 模板已安装并成功导出；项目入口为 `project.godot`。全局 PATH 不要求安装 Godot，版本检查统一经包装脚本执行。Mac GUI 与自动测试已运行。2026-09-15，`codex/week1-foundation` 分支与 `week1-local-2026-09-15` 标签推送成功，首次远端 Linux 检查／Windows 导出和 Windows 云端无头启动均通过；尚未合并到 `main`。实体 Windows、手柄和独立磁盘备份仍待验，详细证据见 [第一周评审](./07_week1_review.md)。

---

## 二、平台、渲染与窗口

### 2.1 渲染器

- 使用 Compatibility 渲染器，不启用 Forward+、HDR、3D 灯光或高级后处理。
- Compatibility 面向较旧或低端桌面硬件，符合纯 2D 像素项目的覆盖目标。[Godot 渲染器说明](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)
- 所有场景效果必须能用 CanvasItem、普通 2D 材质、动画和少量兼容着色器实现。
- 不为一个视觉效果切换全局渲染器；做不到时优先简化效果。
- Windows 最低图形基线按 Compatibility 的 OpenGL 3.3 或 Direct3D 11 支持评估，并在低端集显实机测试。[Godot 系统要求](https://docs.godotengine.org/en/stable/about/system_requirements.html)

### 2.2 画面与缩放

| 设置 | 值 |
|---|---|
| 设计视口 | 640×360 |
| 默认窗口 | 1280×720 |
| 宽高比 | 固定 16:9 |
| 拉伸模式 | `viewport` |
| 拉伸比例 | `keep`，非 16:9 显示黑边 |
| 缩放模式 | `integer` |
| 纹理过滤 | 像素素材 `nearest`，关闭 mipmap |
| HiDPI | 保持启用 |
| 默认模式 | 无边框窗口；设置中提供窗口和独占全屏 |

Godot 官方将 640×360、Viewport、Keep 与整数缩放列为像素桌面游戏的合理组合；1366×768 等非整数比例下允许出现黑边，以换取像素宽度一致。[Godot 多分辨率说明](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)

实现约束：

- 世界、角色和 Camera2D 的最终绘制坐标取整数，避免移动时像素抖动。
- 像素 PNG 在导入预设中关闭 Filter、Mipmaps 和有损压缩。
- 非像素资源只限动态字体、商店素材源文件和必要的高分辨率 Logo，不进入世界场景缩放链。
- 不允许各场景自行改变基础分辨率。
- 截图、过场和 UI 都必须在 640×360 设计视口下先通过可读性检查。

### 2.3 性能与发布目标

| 项目 | 目标 |
|---|---|
| 帧率 | 60 FPS；战斗逻辑不依赖帧率 |
| 内存 | 垂直切片常驻内存低于 1 GB |
| 冷启动 | 普通 SSD 上进入标题画面低于 5 秒 |
| 场景切换 | 普通区域低于 2 秒；较慢设备显示可取消误解的加载提示 |
| Windows 架构 | x86_64，只发布 64 位 |
| 最低系统 | Windows 10 x64、支持 OpenGL 3.3 或 Direct3D 11 的显卡 |
| 构建体积 | Demo 解压后目标低于 1 GB |

这些是项目目标而不是对所有硬件的保证。第一个外部测试版本必须收集真实低端机器的启动、显存和帧率数据，再决定 Steam 商店最低配置。

---

## 三、代码与目录架构

### 3.1 依赖方向

```text
presentation  ──调用──>  core/use_cases  ──调用──>  domain
      │                       │                   │
      └──只读视图模型          └──接口─────────────┘
                                  ▲
                 platform / persistence adapters
```

- `domain` 保存与 Godot 场景无关的战斗、调查、任务、关系和时间规则。
- `core` 编排用例、状态转换、场景切换和事件结算。
- `presentation` 只负责输入、节点、动画、UI 和声音，不成为剧情状态权威。
- `platform` 与 `persistence` 实现文件系统、Steam 和操作系统接口。
- 依赖只能指向图中右侧或接口，领域规则不得直接查找 UI 节点或 Steam 单例。

### 3.2 计划目录

```text
wuxia_game/
├── project.godot
├── export_presets.cfg
├── README.md
├── docs/
├── game/
│   ├── core/
│   │   ├── bootstrap/
│   │   ├── commands/
│   │   ├── events/
│   │   └── services/
│   ├── domain/
│   │   ├── battle/
│   │   ├── evidence/
│   │   ├── quests/
│   │   ├── relationships/
│   │   ├── time/
│   │   └── state/
│   ├── presentation/
│   │   ├── exploration/
│   │   ├── battle/
│   │   ├── dialogue/
│   │   └── ui/
│   ├── content/
│   │   ├── data/
│   │   ├── dialogue/
│   │   └── localization/
│   ├── platform/
│   │   ├── offline/
│   │   └── steam/
│   ├── persistence/
│   ├── tests/
│   └── tools/
├── assets/
│   ├── source/
│   └── runtime/
└── builds/
```

Day 6 可以创建这些目录，但未出现第二个实现前不为每个接口建立空文件，避免形式化架构超过实际功能。

### 3.3 运行时权威

- `GameSession` 持有唯一 `GameState`，对应 Day 3 的路线、时间、任务、人物、证据、武学与玩家状态。
- 探索场景、战斗场景和 UI 从 `GameSession` 读取状态快照，通过命令请求改变状态。
- 领域系统返回事件，如 `GAIN_EVIDENCE`、`SET_FACT`、`CHANGE_RELATION`、`ADVANCE_TIME` 和 `START_BATTLE`。
- 事件只有在验证通过后一次性写回状态；禁止 UI 先改数值再通知存档。
- `BattleState` 与 `GameState` 分离，胜利结算后才写回；失败直接丢弃战斗状态。
- 2026-09-25 Day 15 起点：`game/domain/battle/battle_state.gd`为不读写存档的临时战斗权威，原子校验棋盘／占位／单位数据，按身法维护稳定队列。Demo两人，我方容量4人；`game/tools/battle_lab/`只是独立开发实验场，被两个导出预设排除，后续正式战斗表现层另接入。当前无战斗结算写回，不变更schema 1。
- 节点路径、场景实例 ID 和动画进度不得进入永久存档。

### 3.4 初始自动加载项

Day 6 只建立五个必要 Autoload：

| 名称 | 责任 | 不负责 |
|---|---|---|
| `App` | 启动、顶层场景切换、退出流程 | 具体任务与战斗规则 |
| `GameSession` | 当前路线和 `GameState` 生命周期 | 文件格式和 Steam |
| `ContentDB` | 加载并校验静态内容定义 | 运行时任务推进 |
| `SaveService` | 存档、迁移、备份与恢复 | 决定游戏后果 |
| `PlatformService` | 成就、云状态、语言和平台能力入口 | 直接保存剧情状态 |

音频与设置先作为普通服务；只有证明需要跨所有场景保持状态时再提升为 Autoload。

### 3.5 场景边界

```text
Main
├── SceneHost       # 当前探索或战斗场景
├── UIRoot          # HUD、对话、命卷、暂停和过场遮罩
└── TransitionLayer # 淡入淡出与加载反馈
```

- 探索区域各自是可卸载场景，不把整座县城放进一个巨大节点树。
- 战斗复用探索背景和角色素材，但创建独立逻辑网格与 `BattleState`。
- 对话是覆盖层，不复制探索场景。
- 场景切换先保存目标场景 ID 与出生点 ID，再卸载旧场景。
- 所有出生点、交互点、战斗和对话入口使用稳定字符串 ID。

---

## 四、内容与代码规范

### 4.1 GDScript 约束

- 新脚本使用静态类型、明确返回类型和 `class_name` 仅限可复用领域类型。
- 文件、变量和函数使用 `snake_case`；类使用 `PascalCase`；稳定内容 ID 使用大写前缀加英文下划线。
- 单个脚本优先控制在 300 行以内；超过后按职责拆分，不按“工具函数”随意堆放。
- 不使用场景树全局搜索作为常规依赖注入。
- 不在 `_process` 中轮询任务与剧情条件；由命令、事件和时段推进触发。
- 战斗、伤害和状态逻辑保持确定性，不读取真实时间或渲染帧数。
- 调试构建遇到重复 ID、缺失引用和非法状态时立即失败；发布构建记录错误并回到安全界面。

### 4.2 静态内容格式

| 内容 | 格式 | 说明 |
|---|---|---|
| 武学、敌人、证据、事实、任务、物品 | JSON | 使用稳定 ID；启动时转为有类型的领域定义 |
| 对话节点 | JSON | 台词只存本地化键；条件和结果使用受控操作符 |
| 简中与英文文本 | UTF-8 CSV | 第一列为稳定文本键，不在场景中直接写大段台词 |
| 地图与 UI | `.tscn`／`.tres` | 只保存布局、节点和资源引用 |
| 图像 | PNG | 运行时无损；源文件保存在 `assets/source` |
| 音频 | OGG | 长音乐使用 OGG；短音效按实际质量测试后确定 OGG 或 WAV |

不引入 YAML、数据库服务器、运行时脚本下载或自定义二进制内容格式。JSON 数据加载后必须经过字段、类型、引用、唯一性和可达性检查。

### 4.3 内容 ID

```text
CHAR_PRISONER
EV_GRAVE_TAG_03
FACT_NO_BODY_REGISTERED
QUEST_FIND_GRAVEKEEPER
SK_YUE_THRUST
BATTLE_CHENGYUE_GATE
DIALOGUE_BOATMAN_CHALLENGE
```

- ID 发布后不复用给其他内容。
- 重命名显示文本不改变 ID。
- 删除已进入公开存档的 ID 时提供迁移或保留废弃定义。
- 存档只保存 ID 和运行状态，不复制静态内容全文。

### 4.4 本地化与文本

- 简体中文为权威文本；英文 Demo 文本在内容稳定后人工校对。
- 场景、图片和动画中不烘焙剧情文字。
- 数值、按键、角色名和证据名使用占位符，不在句子中字符串拼接。
- 每条文本有上下文备注和最长预期字符数。
- UI 必须用伪长文本测试；英文按简中宽度的 1.5 倍预留。
- 字体与许可登记见 [`05_art_bible.md`](./05_art_bible.md)。

---

## 五、输入与操作映射

### 5.1 原则

- 游戏逻辑只读取 InputMap 动作，不直接判断具体键码。
- 完整版目标仍为键鼠与手柄全程可用，最近一次有效设备决定提示图标。当前开发与验收先以键盘完成全流程，手柄按下方阶段决定执行。
- 所有菜单可只用方向、确认、取消和肩键操作。
- 左摇杆死区初始设为 0.25，之后用不同手柄测试漂移；Godot 支持按动作设置死区。[Godot 手柄说明](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html)
- 不占用 Steam 默认截图键 F12。
- 键盘与手柄允许分别重映射；确认和取消不能同时失去绑定。

#### 阶段决定：先键盘，保留手柄映射（2026-09-16）

用户明确决定先使用键盘，保留手柄到键盘功能的对应关系。第一周工程和第二周灰盒以键盘完整操作为输入验收标准；保留现有手柄 InputMap、共享动作、菜单桥接、断开处理及模拟回归，不要求现在提供实体手柄。

这里的“映射”是键盘和手柄绑定同一个游戏动作，例如 `W/↑` 与左摇杆向上都触发 `move_up`，不是把手柄伪装为系统键盘或依赖外部模拟软件。玩法代码继续读取动作，后续接入手柄不另建一套玩法逻辑。现有手柄响应不删除，但未实测就不承诺硬件兼容性。

实体手柄移动、菜单导航、死区、图标切换、断开恢复和重绑定体验，移至第 19 周输入完善里程碑验收；若更早对外提供手柄支持，须在该版本外测前完成。该项记为“延期，未实测”，不记为通过。此次只调整输入验收，不自动改变 Windows 真机、备份或其他验收要求。

### 5.2 默认 InputMap

| 动作 ID | 键鼠 | 手柄 | 用途 |
|---|---|---|---|
| `move_up/down/left/right` | WASD、方向键 | 左摇杆、十字键 | 探索、战斗格、菜单导航 |
| `confirm` | Enter、Space、E、鼠标左键 | A／南键 | 交互、选择、确认 |
| `cancel` | Esc、鼠标右键 | B／东键 | 返回、关闭、取消移动或招式 |
| `sprint` | 左 Shift | X／西键 | 探索冲刺；菜单中不使用 |
| `inspect` | F | 右肩键 | 标出当前场景的关键与方案调查点 |
| `open_codex` | Tab、J | Y／北键 | 打开或关闭《命卷》 |
| `tab_previous` | Q | 左肩键 | 《命卷》与战斗面板上一页 |
| `tab_next` | R | 右肩键 | 《命卷》与战斗面板下一页；与长按观察区分上下文 |
| `pause` | Esc | Menu／Start | 暂停与系统菜单 |
| `quick_save` | F5 | 无默认绑定 | 非战斗、非重大对话时快速保存 |
| `toggle_threat` | T | 左扳机 | 战斗中保持显示敌方威胁范围 |

`inspect` 和 `tab_next` 虽可共享右肩键，但不能在同一上下文同时生效。Day 6 建立输入上下文栈：`exploration`、`dialogue`、`codex`、`battle`、`system_menu`，顶层上下文独占确认、取消和肩键。

### 5.3 重映射与提示

- 设置界面检测重复绑定并允许交换、保留或取消。
- 系统保留一个不可移除的键盘取消路径，防止玩家无法退出重映射页。
- 手柄断开时暂停一次并切回键鼠提示，不要求重新启动。
- 未知手柄使用通用 ABXY 图标；PlayStation、Xbox 和 Nintendo 图标作为后续可替换图集。
- 战斗操作不依赖 1～9 快捷键，手柄玩家不会多走菜单层级。

---

## 六、存档、设置与版本迁移

### 6.1 用户目录

启用 Godot 的自定义用户目录，工作名为 `ProjectWuming`。永久数据只写入 `user://`；导出后的 `res://` 视为只读。Godot 保证 `user://` 在导出项目中可写，并会按操作系统映射到用户数据目录。[Godot 文件系统说明](https://docs.godotengine.org/en/stable/tutorials/scripting/filesystem.html)

```text
user://
├── saves/
│   ├── manual_01.sav ... manual_05.sav
│   ├── quick.sav
│   ├── auto_01.sav ... auto_03.sav
│   ├── anchors/
│   │   └── CH01_FINAL_DECISION.sav
│   └── backups/
├── profile/
│   └── meta.json
├── config/
│   └── settings.cfg
├── logs/
└── temp/
```

- `saves` 与 `profile/meta.json` 是玩家跨机器需要的进度。
- `settings.cfg` 保存分辨率、音量、语言和键位，不进入 Steam 云，避免机器间覆盖硬件设置。
- `logs` 和 `temp` 不进入 Steam 云，也不进入 Git。
- 战前重试快照放在内存；只有异常退出恢复功能得到验证后，才考虑写入 `temp`。

### 6.2 存档信封

每个 `.sav` 是 UTF-8 JSON，顶层字段固定为：

```text
schema_version
game_version
content_version
save_id
save_kind
created_at_utc
playtime_seconds
route_id
scene_id
spawn_id
preview
payload
```

`preview` 只包含存档列表需要的角色名、章节、时段、地点和缩略图键；完整 `GameState` 位于 `payload`。首个 schema 版本为整数 `1`，内容版本与构建一起记录。

### 6.3 安全写入

保存流程必须按顺序执行：

1. 把完整 JSON 写到目标存档同目录、扩展名为 `.tmp` 的临时文件。
2. 重新读取临时文件并完成 JSON、必填字段与 schema 校验。
3. 若目标存档已存在，先复制到 `saves/backups/` 中该槽的 `.bak.tmp`；验证副本后再替换固定 `.bak`。例如 `manual_01.sav` 对应 `backups/manual_01.bak`。
4. 将原正式文件暂时改名为同目录 `.old`，再把已校验的 `.tmp` 改名为正式文件；第二次改名失败时立即把 `.old` 恢复原名。
5. 重新读取正式文件验证成功后删除 `.old`，再更新存档列表；最终验证失败时从 `.old` 或 `.bak` 恢复。

自动存档不得覆盖手动存档。读档失败时依次尝试 `saves/backups/` 中的同槽 `.bak`、上一个循环自动档，并向玩家说明恢复来源，不静默创建空白进度。

2026-09-23 反馈版的显式选槽规则：五个手动槽与 `quick` 分开显示／载入，F5 仅写 `quick`，覆盖已有手动槽先确认且默认取消。槽位摘要只读本槽正式文件、回滚文件和备份，不触发跨槽回退或写入；UI 明确选择一个槽后只恢复该槽及其备份，不静默借用另一自动槽的路线。底层恢复接口保留显式允许自动备用的能力；需要读取自动槽时由用户在列表另选，并显示真实来源。当前仅展示已有自动槽内容，剧情自动保存触发仍按后续里程碑实现。schema 1 与已有文件名不变。

Godot 官方存档示例使用 `FileAccess` 和 JSON，但本项目不直接序列化场景节点，而是序列化 Day 3 已定义的 `GameState`。[Godot 存档说明](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)

### 6.4 迁移规则

- 载入旧 schema 时按 `1→2→3` 逐级迁移，不写跨版本巨型转换器。
- 迁移前复制原存档到 `backups/pre_migration_<version>`。
- 缺失的新增字段使用明确默认值；被删除的内容 ID 必须有映射或可解释的降级结果。
- 存档 schema 高于当前游戏版本时拒绝覆盖，并提示玩家使用更新版本。
- 迁移成功后仍保留原备份，直到玩家完成一次新存档。
- 每次 schema 变更都增加至少一个旧版本样本测试。

### 6.5 重大选择与重勘

- 重大选择前创建只读锚点，文件名使用稳定 `anchor_id`。
- 垂直切片只保留 `CH01_FINAL_DECISION` 一个通关后可见重勘节点。
- 重勘复制锚点的 `payload`，生成新 `route_id`，不原地修改旧路线。
- `profile/meta.json` 记录已看结局和路线摘要；任务、证据、关系、物品与武学仍按锚点恢复。
- 锚点由 `SaveService` 创建，是否允许重勘由领域规则决定，UI 不能自行解锁。

---

## 七、Steam 与平台隔离

### 7.1 接口边界

游戏只依赖 `PlatformService`，不在剧情、UI 或存档代码中直接调用 Steam 插件。最小接口为：

```text
initialize() -> PlatformCapabilities
is_available() -> bool
get_platform_language() -> String
unlock_achievement(id) -> void
set_stat(id, value) -> void
store_stats() -> void
open_store_page() -> void
shutdown() -> void
```

`PlatformCapabilities` 明确表示成就、统计、覆盖层和云状态是否可用。接口失败只禁用对应平台功能，不能阻止单机游戏启动、保存或完成结局。

### 7.2 两个实现

- `OfflinePlatformService`：默认实现，记录调试日志并让所有核心玩法正常工作。
- `SteamPlatformService`：在选定并锁定兼容 Godot 4.7.2 的扩展后实现，只负责 Steam 初始化、回调、成就和统计。

Day 4 不锁定具体第三方 Steam 插件。第 9～12 周接入前必须检查许可证、维护状态、4.7.2 兼容性、Windows 导出和发布包内容；插件源码与许可证随仓库固定版本保存。

Valve 要求 Steamworks API 初始化成功后才能使用其接口，并要求开发用 `steam_appid.txt` 不进入发布包。[Steamworks API 初始化说明](https://partner.steamgames.com/doc/sdk/api)

### 7.3 Steam Auto-Cloud

六个月版本优先用 Auto-Cloud，不调用远程存储 API。Valve 的文档说明 Auto-Cloud 通过后台配置文件组即可在启动和退出时同步，适合不需要游戏内选择云文件的项目。[Steam Cloud 文档](https://partner.steamgames.com/doc/features/cloud?l=english)

计划同步：

- `saves/*.sav`
- `saves/anchors/*.sav`
- `saves/backups/*.bak`，最多保留最近一份每槽备份
- `profile/meta.json`

明确排除：

- `config/settings.cfg`
- `logs/**`
- `temp/**`
- 崩溃转储、截图和本机缓存

Steam Cloud 上线前必须测试：本机保存、退出上传、第二台 Windows 机器下载、冲突选择、断网保存、重新联网和旧存档迁移。不得把 Auto-Cloud 当成本地安全写入的替代品。

### 7.4 成就原则

- 游戏内部先发出领域事件，平台适配器再将其映射为成就。
- 成就失败或离线不影响结局记录，重连后可根据 `profile/meta.json` 补发。
- 隐藏路线和重大剧情成就可以隐藏描述，普通选择不设置带价值判断的“正确答案”成就。
- 六个月切片成就总数暂不上锁；Day 5 决定 Must／Should 后再控制数量。

---

## 八、构建、测试与发布包

### 8.1 导出预设

| 预设 | 用途 | 主要设置 |
|---|---|---|
| `Windows Debug` | 内部测试 | x86_64、控制台日志开启、调试工具开启、Compatibility |
| `Windows Release` | 外部测试与 Steam | x86_64、控制台关闭、调试作弊关闭、Compatibility |

- 使用与 Godot 4.7.2 精确匹配的官方导出模板。
- 首版输出独立 `.exe` 与 `.pck`，不嵌入 PCK，便于检查发布包和后续差分更新。
- Godot 官方 Windows 导出默认支持 x86_64，并把项目内容打包为 PCK 与优化运行时。[Windows 导出说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)
- Release 包不包含 `.godot`、源素材、测试、日志、`steam_appid.txt`、未使用语言和开发文档。
- 发布目录命名为 `builds/windows/<game_version>_<git_short_sha>/`。

### 8.2 命令行入口

Day 6 建立统一脚本，不要求开发者记忆编辑器菜单：

```text
./tools/check_project.sh
./tools/build_windows_debug.sh
./tools/build_windows_release.sh
```

脚本内部通过参数传入稳定 Godot 可执行文件路径，不假定 Homebrew 自动升级后的全局版本。Godot 支持以 `--headless --path` 和导出预设进行命令行导出。[Godot 命令行说明](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

### 8.3 每次构建检查

构建在发现以下任一问题时失败：

- Godot 版本不是 4.7.2 stable。
- GDScript 解析错误或无头启动失败。
- JSON、CSV 或本地化文件无法解析。
- 内容 ID 重复、引用缺失或证据链输出不存在。
- 启动场景、导出模板或 Windows 预设缺失。
- 发布包中包含 `steam_appid.txt`、源素材或调试作弊开关。

成功构建生成：

```text
ProjectWuming.exe
ProjectWuming.pck
build_info.json
licenses/
README.txt
```

### 8.4 自动化

GitHub Actions 分两阶段建立：

1. Day 6：每次推送执行文档检查、JSON／CSV 校验和 Godot 无头解析。
2. 首个导出预设完成后：主分支推送生成 Windows Debug artifact；版本标签生成候选 Release 包和 SHA-256 清单。

自动化失败时不发布旧 artifact 冒充新构建。外部 Windows 测试包仍需在 Windows 10 和 Windows 11 各完成一次人工启动、键鼠操作、存档和退出检查。以键盘为测试范围的早期版本应明确标注手柄未验；首次对外提供手柄支持前补齐实体手柄检查，最迟纳入第 19 周输入完善验收。

---

## 九、备份、Git 与依赖

### 9.1 源文件备份

- 代码、文档、运行时资源和小型源文件进入 Git。
- `.godot/`、导入缓存、`builds/`、本机日志、导出模板和用户存档进入 `.gitignore`。
- 每个可运行里程碑创建普通提交；主开发日结束前推送远端，网络或认证失败时保留本地提交并在下一次工作开始前补推。
- 每周创建一个带日期的里程碑标签；标签不代替发布版本号。
- 二进制源文件单个超过 25 MB 时先评估 Git LFS；不得把大体积音频、视频或未裁剪原稿直接塞入普通 Git 历史。
- GitHub 不是唯一备份：工作区所在磁盘启用系统级每日备份，至少每周验证能恢复一个源文件。

### 9.2 玩家存档备份

- 每槽始终保留上一份 `.bak`。
- 三个循环自动档覆盖前先完成安全写入。
- schema 迁移前保留原文件。
- Steam Auto-Cloud 只同步已经通过本地校验的正式文件。
- 存档损坏报告显示日志位置和恢复按钮，不要求玩家手动寻找系统目录。

### 9.3 依赖政策

- 前四周除 Godot 本体外不引入运行时插件。
- 新依赖必须记录名称、版本、来源、许可证、用途、替代方案和移除成本。
- 只为当前 Must 功能引入依赖，不以“以后可能用”安装大型框架。
- 插件源码或固定发布包进入仓库，禁止运行时从网络下载代码。
- 字体、音效、纹理和参考素材同样进入资产来源登记表。

### 9.4 安全与隐私

- 单机 Demo 不采集遥测、账号、地理位置或通讯录。
- 崩溃日志默认仅保存在本机，玩家主动发送前显示内容。
- 存档不加密；不要把结局保密误当作安全需求。
- 不把 Steam ID、绝对用户路径和机器名写进普通日志或分享用存档。
- 外部文件名和存档字符串在用于路径前必须校验，不允许路径穿越。

---

## 十、Day 6 执行清单

Day 6 执行状态（2026-09-16 按用户决定调整输入验收；其余范围不变）：

1. [x] 安装并验证 Godot 4.7.2 Standard 与同版本 Windows 导出模板。
2. [x] 创建 Compatibility 项目和 640×360 窗口设置，完成 Mac 图形渲染检查。
3. [x] 建立目录、`.gitignore`、主场景和五个必要 Autoload。
4. [x] InputMap 与 Mac 系统键盘操作已验证；保留手柄共享动作映射和模拟检查。实体手柄实测按第 5.1 节延期，不作为当前输入项的通过条件。
5. [x] 建立空 `GameState`、`ContentDB` 和 schema 1 存档往返测试。
6. [x] 建立 `OfflinePlatformService`，无 Steam 环境正常启动。
7. [x] 创建 Windows Debug／Release 预设和本地检查脚本，两个包均通过资源审计。
8. [ ] 在 Windows x64 真机启动导出包，完成存档位置与全屏检查；当前缺少设备证据。

---

## 十一、技术验收

- [x] 已锁定 Godot 4.7.2 Standard、GDScript、Compatibility 和 Windows x64。
- [x] 已定义 640×360、Viewport、Keep、整数缩放、纹理过滤和窗口策略。
- [x] 已定义代码层级、依赖方向、目录、Autoload 与场景边界。
- [x] 已定义 JSON、CSV、场景和运行时资源的职责及稳定 ID 规则。
- [x] 已定义完整键鼠、鼠标与手柄 InputMap、上下文和重映射约束。
- [x] 已定义 `user://` 目录、schema 字段、安全写入、备份与迁移。
- [x] 已定义重大选择锚点和单节点重勘的存档边界。
- [x] 已定义离线／Steam 双适配器、Auto-Cloud 同步和排除范围。
- [x] 已定义 Windows Debug／Release、命令行检查和自动构建方案。
- [x] 已定义源代码、玩家存档、第三方依赖和隐私策略。
- [x] 已记录工具链、本机实现和首次远端 CI 证据，以及实体设备／独立备份验收缺口；规格完成不等于所有平台测试完成。

技术规格已经足够让 Day 6 直接创建工程。若实现过程中发现 Godot 4.7.2 的具体 API 名称变化，可以在不改变本节架构和行为约束的前提下调整实现细节。
