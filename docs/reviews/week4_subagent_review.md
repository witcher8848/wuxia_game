# 第四周独立审查：调查、原件与剧情战斗

审查日期：2026-10-16。审查基线：`041038d`（第七周完成后的当前源码）；本轮检查第三至第七周集成后的第四周职责，不把旧候选包的历史结果冒充当前验证。

## 结论

发现并修复一项 P2 命令权限缺口。现有原始调查内容下，未发现已复现的 P0/P1；这不是对所有未来内容、平台或玩家体验的无条件保证。未改动原始试玩反馈、旧截图或冻结候选包，未提交、推送、构建或发布。

## W4-R1：调查入口可以执行专用权限步骤（P2）

### 修复前的可复现证据

`InquiryRules.configure` 原来只检查 `step_id` 已注册，`prepare` 会直接准备该步骤；`GameSession.resolve_inquiry` 随后安装候选状态。它没有沿用对白已具备的专用命令限制。

将 `INQ_INDEX.step_id` 分别改为下列已登记步骤，其他规范内容保持不变：

| 步骤 | 实际结果 | 违反的约束 |
|---|---|---|
| `STEP_HAND_OVER_BLANK` | ContentDB 加载成功，校勘成功，原件直接改由使团持有 | 未预览／再次确认便交出玩家原件 |
| `STEP_PREPARE_RESCUE` | 校勘成功，营救任务 active，但无战斗实例，`combat_active=false` | 制造无法保存的半结算状态，正常出发条件失效 |

这是需要错误内容变更才能触发的扩展性／权限问题，不是当前规范 JSON 下玩家必遇的故障。隔离复现脚本为 `builds/qa/week4_review_probe.gd`，修复前运行日志为 `builds/qa/week4_review_unsafe_commands.log`，均是本地诊断证据，不打进发行资源。

### 修复

- `InvestigationRules.public_step_allowed(step_id)` 成为只读、共享的普通调查权限判定：必须已注册；不得是两项受战斗实例保护的步骤；不得含任何 `PLAYER → 他人` 的原件转移。不按原件或步骤名称特判，扫描全部效果。普通接收原件仍允许。
- DialogueCatalog 与 InquiryRules 在配置时统一使用此判定。InquiryRules 执行时再次判定，防止其引用的规则对象重新配置后绕过初次校验；对白选项视图同样不会启用后来变成受保护的命令。
- GameSession 普通入口与专用交付提交由主代理同步修复；交付仍要求实际位置规则、预览凭证、未变化的状态快照和再次确认。专用提交还核对预览后内容重载的候选状态，只允许已告知的空白亡籍交给使团及一次性标记变化，拒绝暗改接受方或追加影响。
- 回归测试覆盖两项专属战斗步骤、现有交付步骤、任意命名且转移不位于首个效果的新步骤；覆盖 challenge／compare、失败配置保留全部旧注册表、重新配置规则后的执行拒绝，以及正常调查和专用交付继续有效。

## 验证记录

修复前当前源码的针对性回归均通过，说明原回归缺少上述坏内容权限覆盖，并不推翻已复现缺陷：

| 检查 | 结果 | 日志 |
|---|---|---|
| Inquiry | 166 项，0 失败 | `review_w4_test_inquiry.log` |
| Handover | 53 项，0 失败 | `review_w4_test_handover.log` |
| StoryEncounter | 636 项，0 失败 | `review_w4_test_story_encounter.log` |
| Onboarding | 212 项，0 失败 | `review_w4_test_onboarding.log` |
| Week4Feedback | 198 项，0 失败 | `review_w4_test_week4_feedback.log` |
| 独立写档／冷重启读档 | 135＋23 项，0 失败；writer PID 46262 退出后才启动 reader PID 46271 | `review_w4_story_restart.log` |

修复后的实际验证：

| 检查 | 结果 | 日志 |
|---|---|---|
| 原隔离复现脚本 | 两个坏绑定均加载拒绝，原件仍由玩家持有，无半结算，状态不变 | `week4_review_unsafe_commands_fixed.log` |
| InvestigationRules | 241 项，0 失败 | `review_w4_fixed_test_investigation_rules.log` |
| Inquiry | 208 项，0 失败 | `review_w4_fixed_test_inquiry.log` |
| Dialogue | 822 项，0 失败 | `review_w4_fixed_test_dialogue.log` |
| Handover（主代理整合验证） | 66 项，0 失败；直接／重命名转移拒绝、内容变更后旧凭证失效、接受方不符不发预览 | `review_handover_policy.log` |
| StoryEncounter | 636 项，0 失败 | `review_w4_fixed_test_story_encounter.log` |
| 独立写档／冷重启读档 | 135＋23 项，0 失败；writer PID 47114 退出后才启动 reader PID 47122 | `review_w4_fixed_story_restart.log` |
| 补丁空白／冲突检查 | `git diff --check` 通过 | 实际命令输出 |

以上日志均在 `builds/qa/`。命令统一使用 `python3 tools/run_checked.py <日志名> ./tools/godot.sh --headless --path . --script game/tests/<测试>.gd`；冷重启使用 `python3 tools/run_checked.py review_w4_fixed_story_restart python3 tools/check_story_persistence.py`。调查、对白、领域服务测试均已改为真实预览／确认交付，而非直接调用普通步骤绕过专用入口；纯领域候选测试仍保留，以区分领域能力和执行权限。总项目回归及其他周的验证由主代理另行汇总，不用这些专项结果代替全量通过。

## 验收逐项与边界

- 已审开篇动机、两条调查入口及不标谜底的方向提示；真实标题／序章键盘回归通过。没有把灰盒叙述说成正式刑场战斗或完整开场演出。
- 已审错误质证／错配／取消零时间与关系成本、证据认知和原件归属分离、知识保留、重复领取及一次性效果。
- 已审原件预览、默认保留、二次确认、取消、状态更换／新游戏／旧凭证失效；W4-R1 专项完善扩展内容和服务入口的相同权限边界。
- 已审住所事实解锁首轮真实 AI 副本推演、码头事实改变合法部署；四种情报组合都执行真实合法行动直到胜败，无情报仍可胜利。首次 F 展示、F1 暂停 AI 与保留光标／模式已有定向回归。
- 已审任务寻找→保护的原子转换、实际战果归属、胜利后确认才写回、重复结算拒绝、失败／重试／退出快照；未实现可受攻击的老妇或护送 AI，不冒称已实现。
- 已审战中禁存、结算收据、内容坏档同槽恢复、指定槽不借自动档，以及独立进程冷重启后继续调查。
- 已审第七周时段推进集成：结算后 NPC 换位，不能继续恢复远程船夫对白；靠近新位置可进入真实战后对白。

独立审查读取了：第四周每日排期、`10_week4_review.md`、`docs/week4_playtest.md`，InvestigationRules／InquiryRules／DialogueCatalog／StoryEncounterRules、ContentDB、GameSession、Main、Prologue／Dialogue／Activity／Journal／ObjectiveGuide、StoryBattleScreen、SaveService／SaveFileIO、调查与对白 JSON，以及对应规则、UI、交付、剧情、引导和冷重启测试。仅执行 headless 诊断；本次未新增 GPU／渲染或发行包验证。

## 不由本轮代签的项目

Day 28 第二入口人工复测、校勘／质证的实际战术价值和节奏认可、新玩家 P2、Windows 真机、实体手柄及独立备份继续按原记录待验。原用户填写不重写、不补造。完整三日剧情、后续迁坟旧账与正式地图是后续范围，不列为本周程序缺陷，也不提前制作来混淆验收。
