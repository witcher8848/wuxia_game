# Project Wuming（无名）

一名在户籍中早已死去的少年，循养父留下的《勘亡录》追查仍活着的“死人”，在官府清籍与门派旧怨中习武结伴。

这是两人协作的 2D 像素武侠 RPG 项目。六个月目标是 60～90 分钟垂直切片与 Steam Demo 候选版；当前本地工程为第二周探索灰盒，包含三个区域、移动碰撞、镜头、NPC／文书交互与存读档，还没有完整剧情、调查或战斗玩法。已收到开发者约 7 分钟的 Mac 试玩与原版基线确认；速度和独立存档槽反馈已实现、回归通过，待新版人工复测。新玩家测试获授权转为 P2 后续追踪，不再阻断本轮修改。原交付见[第二周评审](./08_week2_review.md)，本次改动／验证和待确认项以[反馈处理单](./docs/week2_feedback_followup.md)为准。

第一周工程已推送到 [codex/week1-foundation 候选分支](https://github.com/witcher8848/wuxia_game/tree/codex/week1-foundation)，尚未合并到 `main`；`week1-local-2026-09-15` 标签保留当时的工程里程碑。第二周成果和复核记录已提交为本地 `c8c1e28`（`codex/week2-exploration`），第三周Day 15为`eb67fad`。当前在`codex/week4-investigation`先开发第四周的独立调查基础；本次只有本地 Git 提交，未推送／发布或触发远端 CI。

## 第四周当前进度

[第四周每日任务](./武侠RPG_第四周每日任务.md)已拆为Day 22～28。Day 22接入了两份样本证据、事实／五态任务规则、有限条件与效果、原子提交和存档回归；入口是`ContentDB`内容注册与`GameSession.apply_investigation_step()`，暂无玩家可操作的调查界面。文字键的CSV与对话节点校验留给Day 23，质证／二项校勘UI留给Day 24。

**第三周Day 16～21仍未完成，未被第四周替代。** Day 22～25可独立推进；Day 26真实战斗接入前必须补齐移动、攻击、AI、胜负等前置工作，约34h原计划另计。现在双击`Run.command`仍是探索灰盒，`Battle.command`仍只有下述Day 15实验场，不能试玩完整“调查→战斗”闭环。

## 第三周当前入口

[第三周每日任务](./武侠RPG_第三周每日任务.md)已拆到 Day 15～21，共40h计划。已开始 Day 15：独立战斗状态、10×8棋盘、占位及稳定行动顺序；开发场景用两个我方和刀役／弓役占位，数据容量支持我方最多4人。

macOS 双击 [Battle.command](./Battle.command)，或运行 `./Battle.command`。WASD／方向键查看格子，E／Enter结束占位回合，R重置，Esc退出。**此入口目前不是完整战斗**：角色移动、攻击、敌人AI、绝技、胜负将在 Day 16～20接入；不读写探索存档，不计正式战斗场次。`Run.command`仍进入第二周探索灰盒，产品版本仍为`0.2.1-week2`，开发实验场不进入发行包。

验证：`./tools/check_project.sh`包含战斗骨架回归；图形检查用 `python3 tools/run_checked.py week3_day15_visual ./tools/godot.sh --path . --script res://game/tests/test_battle_foundation.gd -- --capture-battle`。截图及当前证据见每日任务末节，人工手感尚未验收。

## 快速启动

开发环境需要 Git、Bash、`curl`、`unzip` 和 Python 3.11 或更新版本。主要开发平台为 macOS；Windows x64 为目标发行平台。固定引擎版本在 [.godot-version](./.godot-version)，当前为 Godot 4.7.2 Standard，使用 GDScript 与 Compatibility。

第一次恢复工作区，在仓库根目录运行：

```bash
./tools/setup_godot.sh
./tools/godot.sh --version
./tools/check_project.sh
./tools/run.sh --dev
```

安装脚本从官方 Godot 发布下载编辑器及同版模板，用官方 SHA-512 清单检查文件。编辑器放在本地 `.tools/`，Windows Debug／Release 模板放在 Godot 用户模板目录；这两处均不提交。首次下载需要网络，完成后正常运行不依赖 Steam 登录或网络。

macOS 后续可双击仓库中的 [Run.command](./Run.command)，或执行 `./tools/run.sh --dev`。启动脚本先导入资源，再启动主场景。需要编辑场景时执行：

```bash
./tools/godot.sh --editor --path .
```

已有固定版本引擎时，可通过 `GODOT_BIN` 指定可执行文件；包装脚本仍会检查版本。不要用自动升级后的其他 Godot 版本直接保存工程。Windows 使用 Git Bash 执行工具脚本；实际 Windows 开发／运行兼容性以对应设备验收记录为准。

## 当前探索灰盒

从中文标题菜单选择“进入小镇”。可在街巷／祠堂入口、旧居院落与码头之间往返；祠堂内部暂未开放。当前行为如下：

| 操作 | 键鼠 | 手柄默认映射 |
|---|---|---|
| 移动 | WASD／方向键 | 左摇杆／方向键 |
| 确认 | Enter／Space／E／鼠标点按钮 | 南侧按钮 A |
| 返回／暂停 | Esc／右键 | B／Menu |
| 冲刺 | Shift | X |
| 观察可交互对象 | 按住 F | 已保留动作映射，实体手柄待验 |
| 快速存档 | F5；或暂停菜单保存 | 暂停菜单保存 |
| 手动存档 | 暂停菜单 → 手动存档 → 五个独立槽 | 共用菜单动作，实体设备未验 |
| 读档／全屏切换 | 标题／暂停菜单 | 菜单选择 |
| 调试信息 | 开发模式下 F3 | 无默认映射 |

当前按 2026-09-16 的决定先以键盘开发和验收。表中的键盘与手柄绑定同一套游戏动作，不需要手柄模拟键盘软件；现有手柄映射和接入接口保留，不为此重写玩法。2026-09-22 反馈版将步速调整为 100、冲刺 180 逻辑像素／秒，冲刺配更快步频和小范围尘点；用户确认不增加精力消耗。新版操作仍需本人复测。

靠近并面向 NPC、文书或出口时按 E；阅读面板可用 E／Esc 关闭，阅读期间锁定移动。输入配置还预留《命卷》、页签和威胁预览，功能将按后续任务接入；有映射不代表对应界面已经完成。实体手柄验收移至第 19 周输入完善阶段，或首次对外提供手柄支持之前；当前记为延期、未实测，不阻塞第一周／第二周键盘操作验收。自动注入的输入事件仍单独记为模拟验证。

场景与角色仍用程序绘制占位形状，不是正式像素资产；[美术规范](./05_art_bible.md)中的明亮县城图是已认可的概念参考，不是实机截图。第二周的角色碰撞、镜头、交互和区域往返已实现，逐项状态见[任务板](./docs/week2_task_board.md)。战斗、轻调查、主支线和恋爱内容目前属于设计规格，不是可玩功能。[人工试玩记录](./docs/week2_playtest.md)提供本周尚待补齐的体验验收表。

游戏状态写到 Godot 的 `user://`，不写回工程目录。自定义数据目录为 `ProjectWuming`：macOS 通常为 `~/Library/Application Support/ProjectWuming/`，Windows 为 `%APPDATA%\ProjectWuming\`。快速档为 `saves/quick.sav`，五个手动槽为 `saves/manual_01.sav`～`manual_05.sav`，互不覆盖；旧版本备份位于 `saves/backups/`。F5 更新快速档，手动槽覆盖前确认，标题／暂停的读档列表可独立选择。自动存档触发逻辑尚未接入，不因保留自动槽而宣称已实现。实际路径可通过日志／存档服务查询。存档测试只使用独立的 `user://tests/` 子目录，不覆盖玩家档位。

## 检查与 Windows 构建

```bash
./tools/check_project.sh
./tools/build_windows_debug.sh
./tools/build_windows_release.sh
```

检查入口覆盖本地文档链接、数据格式、资源引用、Godot 导入、状态／存档、工程约束、UI 回归、探索控制器／内容／流程、独立进程读档、全程脚本化键盘通行和主场景冒烟。日志输出到 `builds/qa/`，具体计数与边界见[第二周评审](./08_week2_review.md)。脚本通行不代替真实玩家体验。构建另对 PCK 内部真实资源做白名单必需项与开发文件排除检查。某步骤失败时先阅读对应日志并修复，不跳过失败来生成“通过”记录。

导出成功后，每次构建生成独立目录 `builds/windows/<版本>_<提交>_<debug或release>_<UTC时间>/`，当前反馈版为 `0.2.1-week2`（内容版本 0.2.0、存档 schema 1 不变）；包括 `ProjectWuming.exe`、`ProjectWuming.pck`、`build_info.json`、`SHA256SUMS.txt`、许可证与快速说明。必须保留 EXE 与 PCK 相邻。`build_info.json` 记录构建配置、基线提交、未提交修改状态和源文件指纹；工作区有修改时不能只凭提交号辨认候选包。

Windows 包导出与 PE x86_64 检查通过只能证明产物已生成；真实 Windows 启动、显卡显示、全屏、存档目录及物理手柄仍需对应设备记录。各周评审分别列出这些结果，不以 macOS 或无头测试代替。

## 恢复设计上下文

| 文件 | 回答的问题 |
|---|---|
| [01_game_vision.md](./01_game_vision.md) | 做什么游戏、玩家身份、差异与不做清单 |
| [02_vertical_slice_story.md](./02_vertical_slice_story.md) | 开篇、三日危机、调查链、两种主解与隐藏解 |
| [02_characters_factions.md](./02_characters_factions.md) | 六名核心 NPC、养父、三方势力和门派关系 |
| [03_core_gameplay.md](./03_core_gameplay.md) | 战斗、轻调查、成长、时间与重勘规则 |
| [04_technical_spec.md](./04_technical_spec.md) | 引擎、架构、输入、存档和平台边界 |
| [05_art_bible.md](./05_art_bible.md) | 640×360、32×32 瓦片、32×48 人物与资产规格 |
| [06_scope_and_backlog.md](./06_scope_and_backlog.md) | Must／Should／Could／Future、上限、风险与工时 |
| [07_week1_review.md](./07_week1_review.md) | 第一周当前证据与未完成验收 |
| [08_week2_review.md](./08_week2_review.md)／[人工试玩记录](./docs/week2_playtest.md) | 第二周实现、构建证据与待验体验 |
| [两周人工复核清单](./docs/week1_week2_human_review.md)／[第二周反馈处理单](./docs/week2_feedback_followup.md) | Day 1～14 逐任务确认、已有人工结果、反馈修复和 P2 追踪 |
| [第一周每日任务](./武侠RPG_第一周每日任务.md)／[六个月排期](./武侠RPG_六个月开发排期.md) | 日／周里程碑与决策门 |
| [第二周每日任务](./武侠RPG_第二周每日任务.md)／[第二周任务板](./docs/week2_task_board.md)／[开发流程](./docs/development_workflow.md) | 每日安排、当前状态、如何提交和验证 |
| [第三周每日任务](./武侠RPG_第三周每日任务.md)／[第四周每日任务](./武侠RPG_第四周每日任务.md) | 战斗前置缺口、调查每日排期与当前开发证据 |

## 工程地图与协作

`game/core/` 负责启动与共享服务；`game/domain/` 保存不依赖场景节点的状态／规则；`game/presentation/` 负责画面和输入；`game/content/` 放稳定 ID 的数据；`game/persistence/` 管理存档；`game/platform/` 隔离离线／Steam；`game/tests/` 与 `tools/` 提供验证和构建。`assets/source/` 保留源素材，`assets/runtime/` 只放运行资源。

功能分支使用 `codex/<简短工作名>`，提交格式为 `feat:`、`fix:`、`test:`、`docs:`、`build:` 或 `chore:` 加明确摘要。主分支保持可启动；提交只包含本任务文件，保留他人的未提交修改。远端是 [witcher8848/wuxia_game](https://github.com/witcher8848/wuxia_game)。2026-09-15 的候选分支与里程碑标签已推送，首次分支／标签 CI 均成功；对应提交、产物和测试边界见验收记录，不将该结果称为 `main` 已集成或第一周全部通过。

外部资源登记在[素材来源表](./docs/asset_sources.md)，AI 辅助内容登记在[AI 内容表](./docs/ai_content_register.md)。Godot 与 Noto 字体的许可证已放入 `licenses/`；它们不替代本项目自有内容的许可决定。
