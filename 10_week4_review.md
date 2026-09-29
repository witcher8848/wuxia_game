# 第四周工程记录：调查闭环（进行中）

更新：2026-09-29。第三周反馈已提交为`cf83a35`，当前在`codex/week4-complete`接续。目标仍是[第四周计划](./武侠RPG_第四周每日任务.md)的完整闭环，不因对白阶段可运行就宣称整周完成。

## Day 23：对白与探索入口

- 复用住所文书`DOC_HOME_NOTE`与码头船夫`NPC_DOCK_WORKER`。两处共享索引整理／接受寻找任务的起点；这是祠堂脱身后的灰盒，不新增可玩祠堂开篇，不改变索引来自女囚的设定。
- [对白JSON](./game/content/dialogue/investigation.json)和[双语CSV](./game/content/localization/investigation.csv)包含说话人、正文、2～4项选项、有限条件及已登记命令；静态可达性、断链、未知入口／命令、缺失任一语言及未登记字段均拒绝。ContentDB失败保留旧的全部注册表。
- [对白面板](./game/presentation/investigation/dialogue_panel.gd)用↑↓／W S浏览、E／Enter确认、Esc离开，PageUp／PageDown滚动长文。灰色项可停留查看原因但不能执行。返回记住之前选项；确认时从当前GameSession重新验证，过期或重复领取无效。
- 只打开／阅读／取消不领取证据，不推进时段或关系；仍保留原探索的“已查看对象”标记。面板独占输入，关闭重置移动状态，不穿透暂停或背景交互。
- 住所已经能取得空白亡籍、重看记下的批注；交出原件后知识仍可读、重复领取不能拿回原件由服务测试验证。**原件交付UI尚未接入**，不是当前可玩的选项。

## 验证与实际边界

[对白测试](./game/tests/test_dialogue.gd)验证数据故障、事务加载、只读视图、前置／重复指令、真实探索E入口、分支／回焦、长文滚动、中英文选项完整宽度与面板边界。UI夹具显式摆放主角以定位对象，不冒充全程走路或人工实玩。原探索全程键盘通行另由既有测试覆盖。

- 实际图形：`week4_dialogue_visual.log`，Apple M4／OpenGL Compatibility，305项通过（其中5项为保存截图）；不与无头300项重复累计。
- 已目视检查[起点](./docs/week4_evidence/dialogue_intro.png)、[文书](./docs/week4_evidence/dialogue_record.png)、[已领取选项](./docs/week4_evidence/dialogue_recorded.png)、[英文](./docs/week4_evidence/dialogue_en.png)；截图为640×360实际Godot视口，不是生成式图像。
- 正常Windows Release预设PCK：`builds/qa/week4-dialogue-pack.rXEh23/ProjectWuming.pck`。`week4_dialogue_pack_audit.log`为86资源／24必需，通过开发文件排除和双语／对白资源检查。
- [包内探针](./tools/probe_dialogue_pack.gd)：`week4_dialogue_pack_probe.log`，10项通过；从真实PCK加载探索，用模拟键盘完成索引→接受目标→取得文书→关闭。不是Windows真机，不是调查战斗闭环。
- 首次CSV导入因新翻译资源尚未生成而报缺失，修正导入元数据并重新导入后正常；UI测试曾误用不存在的`set_facing`夹具方法，改用实际属性并重跑。包检查初次从源码目录调用被防混用检查拒绝，随后显式使用独立包目录验证。没有跳过错误输出或用源码冒充包内结果。

完整回归得到`PROJECT_CHECK_PASS`：既有3658项＋对白300项，共3958项。随后对白测试额外增加独立保存目录的无文件断言，避免未来输入锁回归影响玩家档位；最终对白单独重跑301项通过，29份文档校验和`git diff --check`通过。测试新增这一断言后没有冒称又重跑了整套3959项。上述日志位于本地`builds/qa/`，不提交缓存／PCK／玩家存档。

## Day 24与Day 25交付部分：质证、校勘、命卷和原件

2026-09-29接续，实现已定的第一调查链，不增加正式地图／新角色。码头占位对象显示名改为船夫，住所文书显示名相应调整，稳定ID不变。

- 询问船夫登记`CL_BOATMAN_01`，检查船舷取得`EV_FERRY_TOKEN_01`。质证列2～4项已知相关材料，不显示正确答案；缺证、错证、重复、取消不生成事实、不扣时段或关系。第二次错误仍可退出补查。
- 正确质证保留原证言但改为“存疑”，铁牌核实，登记`FACT_WEST_GRAVES`与`FACT_FERRY_ROUTE`；再次对话承认已改口，不继续假装未知。住所校勘索引＋空白亡籍也登记同一定位事实，另保留`FACT_YAMEN_FORMATION`。两入口独立可推进，并可补查另一边。
- [InquiryRules](./game/domain/investigation/inquiry_rules.gd)验证有限候选／正确对／命令引用／双语键，视图不返回答案标识。第一项仅选择、第二项才请求候选状态，正反顺序相同；UI通过GameSession提交，不能直接写事实。
- J／Tab打开《命卷》，Q／R切换当前案／证据／人物／路线。前两页可用，后两页明确未开放。显示真实任务状态、下一目标、已获情报及证据认知／原件或记录归属／来源；长文键盘滚动，不覆盖选项。证据页可接二项校勘；取消返回原来源，不穿透暂停。
- 街口告示复用为清籍使团收证匣入口；只交当前样本空白亡籍。首次选择只预览接受方与影响，默认“保留原件”，明确再次确认才移交。暂存确认凭证不进存档，取消、替换状态／读档、新游戏、改动前置快照均使旧凭证失效。对白数据不能直接配置从PLAYER转出的原件命令来绕过确认。
- 不擅自生成官封翻案结局、时段或关系收益；实际战斗优势仍未接入，命卷明确显示接入中。任务五态已能呈现，实际“寻找→保护”触发须与遭遇接入，不冒称Day 25全项已完成。

本阶段验证：

| 项目 | 结果与边界 |
|---|---|
| 全量检查 | `PROJECT_CHECK_PASS`：既有3658＋对白503＋调查166＋交付53，共4380项；另有29份文档、导入及探索冒烟 |
| [调查测试](./game/tests/test_inquiry.gd) | 内容故障、失败原子性、双入口／补查、错配／重复、知识保留、真实探索打开及键盘交互；显式摆放玩家仅为UI夹具 |
| [交付测试](./game/tests/test_handover.gd) | 53项，无预览／取消／重复／旧凭证／跨新游戏／读档／非交付地点拒绝，原件改变但知识／时段／关系保留；真实UI二次确认 |
| 实际渲染 | `week4_inquiry_visual.log`175项（含9张截图），`week4_handover_visual.log`56项（含3张截图），均通过；不与无头检查重复累加 |
| 真实PCK | `builds/qa/week4-inquiry-pack.riWbXd/ProjectWuming.pck`；`week4_inquiry_pack_audit.log`92资源／27必需，排除开发资源；`week4_inquiry_pack_probe.log`18项，实际包内对白→校勘→交付确认→命卷归属通过。不是Windows真机或完整战斗候选 |

已目视检查[铁牌](./docs/week4_evidence/inquiry_token.png)、[错误质证](./docs/week4_evidence/inquiry_wrong.png)、[二项校勘](./docs/week4_evidence/inquiry_compare.png)、[当前案](./docs/week4_evidence/journal_case.png)、[证据](./docs/week4_evidence/journal_evidence.png)、[英文](./docs/week4_evidence/journal_en.png)、[交付预览](./docs/week4_evidence/handover_preview.png)与[交付后的命卷](./docs/week4_evidence/handover_journal.png)。调查面板增大阅读区域，保留四行候选；没有进行正式美术或数值细化。

## 后续仍须完成

1. Day 25余项：将寻找老妇转向保护／营救的任务变化接入真实遭遇，显示原因与替代目标，而不以changed表示失败。
2. Day 26～27：事实实际改变同一场战斗；无情报仍可取胜；一次性结算、失败／重试快照、跨进程存读与坏档／不串槽验证。
3. Day 28：当前可玩候选、完整图形回归、两入口真实试玩与首月决策门。第三周反馈不能替代这一尚未交付的闭环体验；时长不补造。外部新玩家、Windows真机与独立备份继续按原项跟踪。

未推送、合并或发布；对白中文／英文是依据既有剧情生成的原型文本，尚未经过人工逐行文案与翻译审核，不是正式定稿。
