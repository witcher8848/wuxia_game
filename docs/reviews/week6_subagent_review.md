# 第六周独立子代理审查

审查日期：2026-10-16。审查者：`/root/week6_review`。提交基线 `041038d`，工作分支 `codex/weeks3-7-review`；测试运行于本轮共享修订工作树，不将其结果冒充基线原字节或冻结候选包的结果。

## 结论

已完成第六周排期及已填写用户反馈对应的代码、生产数据和针对性运行审查。未确认需要新增修复的 P0、P1、P2。此结论仅限下列审查范围，不表示游戏没有任何缺陷，也不表示战术取舍、难度、视觉或操作手感已获用户认可。

同轮其他子代理已修复的 `ACT_BREATH` 免费自用兜底不变量属于战斗公共配置边界，本报告不重复登记为独立新问题、不覆盖其改动。本代理仅新增本报告，没有改游戏代码、原图、已填写反馈或冻结包，也没有执行 GPU 渲染、导出构建、提交或推送。

## 已读需求与证据口径

- 完整阅读 `武侠RPG_第六周每日任务.md`、`12_week6_review.md`、用户原件 `docs/week6_playtest.md`、`docs/week6_feedback_followup.md`。
- 第六周的交付是六种真正武学、三敌行为、整备与被动、预览、两种可配置演武及真实剧情接线，不扩成新战斗系统、完整职业流派或新主线。
- 保留“原空武学档不自动迁移；明确应用整备后才注入新战术表”的兼容边界。旧数据表与新反馈表分别检查，不以旧基线通过替代新战术通过。
- 现场 `shasum -a 256 docs/week6_playtest.md` 仍为 `581f4e4b5cc0ff3ef41f91f67b5da9751ffad4e6d57240a3861b75ba3bd409ee`，未代填用户的“待填写”。

## 逐项审查

| 范围 | 代码与数据依据 | 实际核对及结果 |
|---|---|---|
| 六武学身份与槽位 | `martial_loadout.gd:6`、`:30`、`:49`；`battle_skills_tactics.json` | 六种种子对应四外功、一身法、一被动内功；外功最多三槽，重复、错类、基础行动、绝技及仅识招均不能装备。没有用辅助按钮或敌招凑数。 |
| 草稿／确认／取消 | `martial_preparation_panel.gd:56`、`:74`、`:83`；`game_session.gd:266` | 面板拥有分离草稿，提交时 Session 再查当前掌握阶段。确认只改 `martial_states`；取消不改，应用不等于写磁盘。真实 Main 键盘门通过。 |
| 内功实际作用 | `martial_loadout.gd:78`、`:83`；`combat_encounter.gd:102` | 配内功的上限／普攻恢复／吐纳恢复为 5／1／2，卸下为 3／0／1；资源归一化先于上限校验；被动不出现在可施放列表，预览和实际执行使用同一规则。 |
| 旧档和坏配置 | `martial_loadout.gd:58`；Session／跨进程门 | 空 schema1 只读投影为测试种子，查看不写回；非空坏数据不被默认值清洗。坏槽、坏引用、备份恢复和独立冷重启通过。 |
| 三敌与数据 AI | `battle_ai_profiles.gd:9`；`battle_ai.gd:29`、`:173`；战术原型和 profile JSON | profile 校验引用、队伍、目标、招式和有限值；计划只读确定性，按合法移动与行动真实执行。刀役按起始近目标近压，捕手追携卷者，弓役保持射距；不是按敌人 ID 写死。 |
| 低血／无路／死目标 | `battle_ai.gd:118`、`:146`、`:173` | 低血守势交替、障碍绕行、死亡目标后续选择和完全受阻时免费自用行动均有针对性测试；未发现当前三敌配置的死循环。 |
| 状态、群攻与预览 | `battle_actions.gd`；`battle_effects.gd`；`battle_skill_preview.gd`；`battle_text.gd:106` | 伤害、代受、内力上限、恢复、冷却轮、位移和状态期限均从同一域结果派生。横截按方向而非强制中格敌人；实际代受者去重，取消预览不消耗。 |
| 禁用条件与光标 | `battle_screen.gd:103`、`:151`、`:171`、`:328` | 置灰行可聚焦查看原因而不能施放；返回保留选项与目标；二次确认携带 revision，旧预览不能执行。真实键盘及 UI 布局断言通过。 |
| 两目标配置与主角身份 | `combat_v1_trial.gd:246`、`:272`、`:334`；`combat_v1_trial.json` | 配置决定目标、部署及携卷者；按 `CHAR_PROTAGONIST` 注入而非我方数组下标。59 个坏配置及两种合法我方顺序／两目标通过。 |
| 保护三整轮 | `combat_encounter.gd:177` | 被保护者倒地优先失败，胜利要求完整三轮而不是刚进入第三轮；清敌不提前结束。生产演武清场和保护真实操作均胜利。 |
| 锁、重试和退出 | `game_session.gd:237`、`:257`、`:284`、`:301`；试炼 controller | 战中整备、探索写入、保存和并发遭遇被拒绝；重试恢复战前配置，试炼不产生永久奖励／气血／时间改变；返回整备和退出须确认。 |
| 正常剧情接线 | `story_encounter_rules.gd:45`；`test_week6_feedback_session.gd` | 实际 Main 中按 M 应用，再经实际码头对白出发，不伪造 Combat 结果。已配与旧空档分别使用对应表，卸内功的实际循环正确，原剧情的结算和情报收益保留。 |

上表路径除特别说明外相对 `game/domain/battle/` 或 `game/presentation/battle/`；服务路径为 `game/core/services/`。行号是审查时共享修订工作树位置，后续修订可能移动。

## 本轮实际运行

以下均使用本机固定 `./tools/godot.sh`，输出 Godot `4.7.2.stable.official.ed1daf0bf`，headless 源码模式 `packed=false`。没有设置截图参数，`captures=0` 不被当作像素外观证据。

共同命令形式：

```sh
python3 tools/run_checked.py review_w6_<名称> ./tools/godot.sh --headless --path /Users/witcher/Documents/ChatGPT/wuxia_game --script res://game/tests/test_<名称>.gd
```

| `<名称>` | 当前实际结果 | 独立本轮日志 |
|---|---|---|
| `martial_loadout` | 353 checks，0 failures | `builds/qa/review_w6_martial_loadout.log` |
| `week6_ai` | 826 checks，0 failures | `builds/qa/review_w6_week6_ai.log` |
| `battle_tactics` | 372 checks，0 failures | `builds/qa/review_w6_battle_tactics.log` |
| `tactics_encounter` | 359 checks，0 failures，4 configurations | `builds/qa/review_w6_tactics_encounter.log` |
| `week6_battle_preview` | 315 checks，0 failures，captures=0 | `builds/qa/review_w6_week6_battle_preview.log` |
| `week6_preparation` | 133 checks，0 failures，captures=0 | `builds/qa/review_w6_week6_preparation.log` |
| `week6_martial_session` | 133 checks，0 failures | `builds/qa/review_w6_week6_martial_session.log` |
| `week6_trial` | 356 checks，0 failures，captures=0 | `builds/qa/review_w6_week6_trial.log` |
| `week6_feedback_session` | 108 checks，0 failures | `builds/qa/review_w6_week6_feedback_session.log` |
| `week6_feedback_ui` | 246 checks，0 failures，captures=0 | `builds/qa/review_w6_week6_feedback_ui.log` |
| `story_encounter` | 636 checks，0 failures | `builds/qa/review_w6_story_encounter.log` |

测试计数照本轮实际输出，不挪用历史报告里的计数。`run_checked.py` 同时检查退出码和脚本错误输出，以上全部退出 0。

另执行：

```sh
python3 tools/check_martial_persistence.py
```

实际独立 fixture：`user://tests/martial_persistence_47328_1792154665368117000`。writer PID `47329`，15 checks／0 failures，退出后才启动 reader PID `47336`，24 checks／0 failures；末尾为 `MARTIAL_PERSISTENCE_RESTART_PASS`。验证旧空档原字节、精确配装、同槽真实备份、坏引用拒绝及临时战斗 token 不跨进程存活。日志为 `builds/qa/week6_martial_persistence_write.log`、`week6_martial_persistence_read.log`；这些非冻结 QA 日志可被之后完整回归刷新，fixture 和 PID 仅证明本次运行。

生产战术日志还实际记录：清场时刀役先追同伴、捕手追主角；保护时刀役追主角、捕手追携卷同伴。两轮实际施加破势／牵制。原始血量的四次配装样本与反馈说明中的结果一致：清场余血主角／同伴 15／5、16／3；保护 13／8、8／14，均胜利。此处是可复现战术样本，不是最优策略证明。

## 测试盲点、配置作者边界及后续建议

1. 自动策略样本不能证明“四外功择三”对所有玩家都有足够博弈；仍需用户实玩新版短反馈表，尤其比较主动恢复、护剑和控距的机会成本。不通过追加新系统、降低失败标准或代填认可来“完善”。
2. 本轮仅 headless 运行并审源，不重签历史 49 张 Mac 图。人物清晰度、全屏放大后的观感及下一轮原生表现，需要独立真渲染／人工意见；小逻辑视口不会因为全屏自动产生更多五官细节。
3. AI 支持的是当前注册的三类 profile 及合法技能元数据，不代表任意改名、任意技能组合都具有设计者期望的聪明程度。当前敌人都不是扇形攻击者；若将来给敌人横截等区域技，须新增 T 威胁图对整个受影响区域的验收，不能只验证方向格。
4. 配置任意扩充、正式武学传授、完整成长、额外敌种或门派职业不在本周承诺中；本轮没有以尚未设计的组合缺少测试为由虚构当前阻断缺陷。
5. 本轮没有执行新包构建或包内验证。旧冻结包的内容／来源记录保持原样；共享审查修订后的发行级候选需在最终源状态另行打包和验证，不能继承旧包的 green 标记。
6. Windows 真机、实体手柄、最终平衡、审美和新玩家认可仍未验。本轮 InputMap／键盘测试不能替代硬件验收。

结论供根代理整合第 3～7 周整体修订与最终回归使用，不单独签署商店可发行或人工试玩通过。
