# Project Wuming（无名）

一名在户籍中早已死去的少年，循养父留下的《勘亡录》追查仍活着的“死人”，在官府清籍与门派旧怨中习武结伴。

这是两人协作的2D像素武侠RPG项目。六个月目标是60～90分钟垂直切片与Steam Demo候选版；当前已连接三个区域探索、质证／校勘、情报影响实际战斗、一次性结算与跨进程存读的首个灰盒闭环，尚非完整剧情Demo。探索版已收到约7分钟的Mac试玩与基线确认，速度／独立存档槽反馈已实现但待新版人工复测；战斗原型已收到并处理三轮对话试玩反馈，不要求重复填表，画面与数值后续细化。新玩家测试获授权转为P2跟踪。各阶段证据见[第二周评审](./08_week2_review.md)、[反馈处理单](./docs/week2_feedback_followup.md)及[第三周评审](./09_week3_review.md)。

第一周工程已推送到 [codex/week1-foundation 候选分支](https://github.com/witcher8848/wuxia_game/tree/codex/week1-foundation)，尚未合并到`main`；`week1-local-2026-09-15`标签保留当时里程碑。第二周为本地`c8c1e28`，第三周反馈收口为`cf83a35`，第四周Day 22为`f21e504`。当前在`codex/week4-complete`继续调查闭环；本轮只有本地Git提交，未推送、发布或触发远端CI。

## 第四周当前进度

[第四周每日任务](./武侠RPG_第四周每日任务.md)已拆为Day 22～28。Day 22～27工程已接入：调查规则、双语对白、双入口、质证／校勘、《命卷》、原件二次确认，以及寻找转为保护的真实遭遇。住所情报提供首轮敌方行动推演，码头情报改变部署，两者可叠加；无情报也能获胜。胜利经会话校验后只结算一次，失败／重试不推进时段，退出恢复出发前。跨进程恢复与同槽坏档回退已验。详见[第四周工程记录](./10_week4_review.md)。

Day 28尚待本轮双入口人工体验、实际时长与首月决策门确认，不把自动测试计为试玩。请填写[第四周试玩表](./docs/week4_playtest.md)，不重复第三周反馈。候选生成：`python3 tools/build_week4_candidate.py`；输出`builds/week4/`，包含Windows EXE、PCK和依赖本机固定引擎的`Play-on-Mac.command`，独立用户目录`ProjectWumingInvestigationPrototype`。Windows真机仍未验。

## 第三周当前入口

[第三周每日任务](./武侠RPG_第三周每日任务.md)的Day 15～20工程已实现：10×8棋盘、稳定顺序、四向移动、普攻／武学、五状态、刀役／弓役AI、条件绝技、胜败／撤离和完整重试。Demo仍是两个我方，规则容量支持四人，不等于已做四人内容和平衡。

macOS双击[Battle.command](./Battle.command)。↑↓选择指令，方向键选格，E／Enter预览后再次确认；Esc返回，F查看单位，F1规则，F2切换目标，R确认重试。这一入口仍是独立战斗实验场，不写探索存档。第四周用`Run.command`进入探索，经船夫对话进入剧情遭遇；该遭遇不能用F2更换目标，胜利确认后会写回任务／时段。第三周试玩说明与已收到的意见见[第三周试玩记录](./docs/week3_playtest.md)。

技能栏可预览类别、效果、伤害及棋盘范围；不可执行项置灰，但允许停留查看条件和恢复办法，确认不会进入施放。绝技显示具体触发条件、进度与每战次数。Esc返回保留原选项，再次进入同一技能记住目标格。移动时叠加敌方移动范围（紫框，非攻击范围），我方仍为青色。画面表现和数值平衡后续细化。当前为本地源码反馈改进，旧Windows候选不包含；截图与复测见[技能栏反馈处理](./docs/week3_skill_feedback.md)。

验证：`./tools/check_project.sh`包含旧骨架及完整战斗规则、边界和键盘流程。实际渲染用`python3 tools/run_checked.py combat_visual ./tools/godot.sh --path . --script res://game/tests/test_combat_ui.gd -- --capture-combat`。独立Windows评审候选用`python3 tools/build_battle_candidate.py`生成，版本`0.3.0-week3-prototype`，独立用户目录；正常探索发行入口／版本不变，开发场景仍排除。逐项结果及人工验收缺口见[第三周评审](./09_week3_review.md)。

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
| 《命卷》 | 探索中 J／Tab；Q／R切页，↑↓浏览，证据页E校勘 | 复用既有动作映射，实体设备未验 |

当前按 2026-09-16 的决定先以键盘开发和验收。表中的键盘与手柄绑定同一套游戏动作，不需要手柄模拟键盘软件；现有手柄映射和接入接口保留，不为此重写玩法。2026-09-22 反馈版将步速调整为 100、冲刺 180 逻辑像素／秒，冲刺配更快步频和小范围尘点；用户确认不增加精力消耗。新版操作仍需本人复测。

靠近并面向 NPC、文书或出口时按 E；普通阅读面板可用 E／Esc 关闭。住所文书、码头船夫与街口告示已接入对白：↑↓／W S选择，E／Enter确认，Esc离开；长文用PageUp／PageDown滚动。出示证物不标正确答案，错误尝试不扣时间／关系；校勘先选一条，再选关联候选。面板期间锁定探索移动及保存，取消回到来源对白。《命卷》人物／路线页尚未开放，不将页签当作内容完成。实体手柄验收移至第 19 周输入完善阶段，或首次对外提供手柄支持之前；自动注入事件仍单独记为模拟验证。

场景与角色仍用程序绘制占位形状，不是正式像素资产；[美术规范](./05_art_bible.md)中的明亮县城图是已认可的概念参考，不是实机截图。第二周的角色碰撞、镜头、交互和区域往返已实现，逐项状态见[任务板](./docs/week2_task_board.md)。第四周调查后到码头选择“商议前往河西罪坟”，进入同一场实际战斗；解救后出现迁坟旧账线索，本周样本到此。没有后续地区或恋爱内容。[人工试玩记录](./docs/week2_playtest.md)保留第二周的体验验收表。

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
