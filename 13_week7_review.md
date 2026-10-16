# 第七周评审：时辰、日程与人情原型

开工：2026-10-15；收口：2026-10-16。第六周反馈已提交 `ce221c2`；第七周在 `codex/week7-world-state` 完成原型工程交付。未推送GitHub、未发布Steam、未改写以前的冻结包或用户反馈。

## 原排期逐项交付

| 第七周要求 | 实际实现与入口 | 验证依据 |
|---|---|---|
| 世界状态 | 现有GameState分区持久保存时段、NPC安全落点、帮忙日期、关系与乡里声望 | Session真实服务／实际文件、语义坏档拒绝、备份恢复及独立进程读档 |
| 时间推进 | 探索H进入时辰面板；等候／帮忙先预览、默认取消、再次选择才执行 | Main真实键盘输入；取消不改状态，旧／伪／重复token、战斗期间操作拒绝 |
| NPC日程 | 摊主与船夫各三落点、八槽完整日程；确认后瞬时换位，不做实时寻路 | 2NPC×8槽投影与实际物理／射线；旧位置无幽灵碰撞，旧档与玩家重叠时最近安全恢复 |
| 关系 | 每NPC每天一次帮忙、耗1槽、信任+1；初识／相熟／信赖／戒备阶段 | 帮忙前后真实对白变化；普通交谈不刷值；命卷只显示已结识人物和关系阶段 |
| 声望 | 帮忙同时增加乡里声望+1，影响其他熟人的说法 | REP_TOWN持久化、负／零／正阶段对白、人物页及冷重启投影一致 |
| 对话随状态改变 | 两NPC各八段时段对白，叠加关系与声望说法；船夫旧调查选项保留 | Main实际NPC交互、双语实绘、旧调查／剧情／战斗回归 |

信任／声望各限制在-100～100；显示关系阶段，不把隐藏数值或完整日程暴露在人物页。帮忙预览明确写出数值效果和上限，旧空容器在查看时不自动补写。

## 可玩入口与操作

用 [Run.command](./Run.command) 启动当前源码，或运行 `./tools/run.sh --dev`。旧第六周PCK不含本周内容；本周交付为源码开发原型，没有另行生成或验证第七周独立发行包。

- 正常探索H：查看时辰；E预览等候。预览默认取消，↓后E才确认推进一槽。
- 摊主／船夫面前E交谈，再H打开人情／帮忙。帮忙后若对方已换位，面板只提示去向变化，不继续远程播放新对白；重新靠近才能交谈。
- J／Tab打开命卷，Q／R切到人物。正常三页，开篇教程仍只讲任务／证据两页，路线页禁用。
- 普通走路、跨图、交谈、读命卷及取消免费。面板内不接受探索移动或F5；退出后F5／手动槽才保存，不自动存档。
- 罪坟胜利仍只结算一次。若船夫随时段去了新位置，回到探索而非远程续聊；重新找到他仍可听战后对白。撤回／重试不推进时段。

试玩意见写在 [第七周试玩表](./docs/week7_playtest.md)，不需要重填之前的战斗／美术表。

## 架构与兼容

| 层 | 职责与边界 |
|---|---|
| `world_state.json` | 日程、落点、时段对白稳定key；所有落点不能堵建筑、文书、出口或出生点 |
| `WorldRules` | 无场景依赖的校验／纯投影／候选事务；先确定安全落点，再一次提交；查询不改存档 |
| `ContentDB` | 全部内容共同验证后才发布；世界数据与双语文本缺失时拒绝reload，旧可用registry保留 |
| `GameSession` | 唯一执行权：战斗锁、当前地图／距离／墙体校验、临时token、全状态快照比对、再次重算候选 |
| 画面层 | `state_replaced`统一重投影NPC视觉、碰撞、射线与HUD；不每帧重算日程，不决定关系奖励 |
| 存档 | 仍为schema1，复用现有严格SaveService、独立槽和备份；token不落盘、不在重启后复活 |

世界字段位于已有分区：`time_state`；`character_states[NPC_ID].last_help_day/location`；`relationships[NPC_ID].trust`；`world_flags.REP_TOWN`。不新增必须存在的顶层字段。location保存选定的day／slot／anchor，避免推进时NPC压住玩家，也保证读档复现同一安全位置。旧空容器只读兼容；坏的非空字段拒绝，不静默清洗。

旧注册表可以不声明world_path，保持原静态地图行为；本周新增耗时动作在该旧内容中不可用。旧严格剧情结算、imagegen原PNG与帧清单不改。

## 验证记录

运行入口已加入 `tools/check_project.sh`。各层证据分别验证，域测试不冒充实机／冷重启，源码测试不冒充包内测试。

| 检查 | 本轮结果 | 日志／入口 |
|---|---|---|
| 世界纯规则 | 334项通过 | `builds/qa/world_rules.log`；`test_world_rules.gd` |
| ContentDB原子注册／双语key | 40项通过 | `builds/qa/week7_content.log`；`test_week7_content.gd` |
| 实际NPC物理／射线／人物页 | 284项通过 | `builds/qa/week7_npc_ui.log`；`test_week7_npc_ui.gd` |
| Session／实际存档服务 | 386项通过 | `builds/qa/week7_world_session.log`；`test_week7_world_session.gd` |
| Main真实键盘／双语界面 | headless 74项通过；Mac原生渲染110项通过／18张实绘 | `builds/qa/week7_world_ui.log`、`week7_visual_final.log` |
| 世界独立冷重启 | writer PID25282：360项、reader PID25289：38项通过；writer退出后才启动reader | `python3 -B tools/check_world_persistence.py`；`builds/qa/week7_world_persistence_write.log`／`read.log` |
| 编排协议 | 10项单测通过；拒绝假／重复／错误标记、超时和写进程失败 | `tools/tests/test_world_persistence.py`；假runner仅验证编排，不算实际运行证据 |
| 完整新旧回归 | 最终PROJECT_CHECK_PASS，包含本周五组门禁、10项编排单测，以及故事／武学／世界三类独立冷重启 | `builds/qa/week7_final_project_check.log` |

旧回归维护仅三处：时间fixture通过Session正式替换以刷新日程；人物页由占位改为第三个可用页；剧情胜利后先恢复探索、靠近换位船夫再验证原战后节点。没有删掉原撤回、调查或胜利结算验证，也未放宽数值阈值来制造通过。

## Mac实际渲染

这些是640×360原生逻辑视口的实际截图，不是概念图或用户审美认可。中英文均验证了时辰、预览、换位、帮忙结果和人物页。

- [时辰面板](./docs/week7_evidence/week7_zh_CN_clock.png)、[等候确认](./docs/week7_evidence/week7_zh_CN_wait_confirm.png)、[推进后街巷](./docs/week7_evidence/week7_zh_CN_relocated.png)。
- [帮忙确认](./docs/week7_evidence/week7_zh_CN_help_confirm.png)、[换位后不远程续聊](./docs/week7_evidence/week7_zh_CN_help_result.png)、[命卷人物](./docs/week7_evidence/week7_zh_CN_people.png)。
- [帮忙前的对白](./docs/week7_evidence/week7_zh_CN_vendor_before.png)、[重新靠近后的新对白](./docs/week7_evidence/week7_zh_CN_vendor_after.png)、[船夫日常与旧调查并存](./docs/week7_evidence/week7_en_boatman_topic.png)。
- [英文帮忙确认](./docs/week7_evidence/week7_en_help_confirm.png)、[英文人物页](./docs/week7_evidence/week7_en_people.png)。

## 保留边界与后续

**现有每日8技术槽用于日程循环，不是“三日共八个剧情时段”的正式章程。** 不宣称已实现封城、清籍截止、公共事件优先级、分支机会变化或自动存档；正式剧情时间轴仍须在后续内容周接入。本周不新增地图、恋爱角色、门派剧情或第八周分支任务。

人物偏小／看不清的反馈已记录：当前全屏只放大已有像素，不补回细节。本周原画、探索尺寸和第六周战斗尺度不改，后续单独比较局部缩放、轮廓／对比与详情头像方案。

人工体验、Windows和实体手柄仍未验；Mac键盘与工程回归不代签这些项目。下一步是试玩本周原型并决定是否调整“耗时与人情”的手感，不自动扩到第八周内容。
