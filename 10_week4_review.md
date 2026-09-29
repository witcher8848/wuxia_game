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

## 后续仍须完成

1. Day 24～25：铁牌与证言、出示证物、二项校勘、《命卷》当前案／证据页、两入口汇流、原件交付二次确认及任务转换。
2. Day 26～27：事实实际改变同一场战斗；无情报仍可取胜；一次性结算、失败／重试快照、跨进程存读与坏档／不串槽验证。
3. Day 28：当前可玩候选、完整图形回归、两入口真实试玩与首月决策门。第三周反馈不能替代这一尚未交付的闭环体验；时长不补造。外部新玩家、Windows真机与独立备份继续按原项跟踪。

未推送、合并或发布；对白中文／英文是依据既有剧情生成的原型文本，尚未经过人工逐行文案与翻译审核，不是正式定稿。
