# 第五周评审：主角测试素材与动画管线

2026-10-07。第四周已本地提交`355ada7`，本周在`codex/week5-character-pipeline`开发，未推送或发布。原始目标见[六个月计划](./武侠RPG_六个月开发排期.md)，逐日任务见[第五周计划](./武侠RPG_第五周每日任务.md)。本周对象是一名测试角色，不把首月遗留体验门当成通过。

## 工程交付

- 固定像素规格与11色色板、32×48／脚底(16,44)、四向文袋侧别；[源与导出方式](./assets/source/characters/README.md)。源按鞋裤、衣、臂／武器、头、文袋分层，可重复生成PNG和JSON。共57帧槽，待机／恢复允许重复，不是57张独立绘画。
- 四向行走、短拳、直刺、横斩、守势／护剑、受击、单向倒地。冲刺复用步帧，不耗精力。探索复用同一视觉对象，保留整数显示／小数物理、碰撞、180／300速度、暂停／失焦处理。
- 战斗实际确认的移动／行动驱动视觉；预览取消不发动动作。移动逐格插值、拳剑分型、受伤和倒地、重试恢复。表现层不改战果、属性、范围、存档；快速连续确认可以截断前一视觉动作。
- [Character.command](./Character.command)独立样本：四向、1×／2×／3×、所有动作、暂停／步频切换。[Run.command](./Run.command)可从新游戏观察主角在实际流程中的效果。预览里的攻击循环只为检视，实际战斗为单次。

## 验证记录

| 范围 | 证据与结果 |
|---|---|
| 源／导出一致 | `character_source`192项通过：57帧槽逐帧像素比对、11色、二值透明、无mipmap／有损压缩、时序、文袋侧别、待机复用 |
| 运行时 | `character_pipeline`143项通过：四向帧推进、单次动作／倒地持续、预览键盘／暂停、真实伤害／失败／重试、动画不改战斗状态 |
| 图形化样本 | `week5_character_render`167项通过；Mac Apple M4 Compatibility实绘，包括1×／2×／3×、所有动作、实际战斗倒地截图；不是人工认可 |
| 战斗接线与排版 | `week5_combat_render`433项通过：真实键盘确认、取消不触发动作、全战斗胜利／重试与菜单边界；曾发现底部文字越界，已恢复合法布局 |
| 开场与探索实绘 | `week5_exploration_render`234项通过，中英、两条首站、码头质证与目标指引；实际角色已替换，不使用旧占位截图 |

实绘截取：[1×](./docs/week5_evidence/week5_walk_1x.png)、[2×](./docs/week5_evidence/week5_walk_2x.png)、[3×](./docs/week5_evidence/week5_walk_3x.png)、[直刺](./docs/week5_evidence/week5_thrust.png)、[横斩](./docs/week5_evidence/week5_slash.png)、[护剑](./docs/week5_evidence/week5_guard.png)、[受击](./docs/week5_evidence/week5_hit.png)、[倒地](./docs/week5_evidence/week5_down.png)、[探索](./docs/week5_evidence/exploration.png)、[战斗](./docs/week5_evidence/battle.png)。已目视检查轮廓、字号、边界与脚底；也修正了最初样本中手臂连接不清的问题。

一次附加图形化引导测试在命卷后达到180秒超时，原因未确认，没有标为通过；添加阶段日志和60秒测试看门狗后，单独重跑与最终再跑均234项通过。原超时日志`builds/qa/onboarding_character_visual.log`保留；不是因此声称修好了某个已定位的游戏卡死。

`./tools/check_project.sh`全量通过，末尾`PROJECT_CHECK_PASS`，日志`builds/qa/week5_project_check.log`。包含以上源／运行时测试，以及探索控制器85、实际脚本步行196、战斗UI346、技能预览559、剧情遭遇622、新手流程212、第四周反馈198、跨进程存读130／23等既有回归。不是只跑新样本自测。

## 最终独立候选与提交

实现提交`418e721`（`feat: add week five protagonist art and animation pipeline`）。从干净工作树运行`python3 tools/build_week5_candidate.py`，得到：

`builds/week5/0.5.0-week5-prototype_418e721_20261007T135109Z/`

- 版本`0.5.0-week5-prototype`，元数据`dirty=false`，源快照SHA-256为`608a94d57f1f2c04dd47b7a579a72fa0ba3942f5f6ff0406a16967eed5c004fb`。
- PCK SHA-256：`9bde575acc4ed749b2d4f43666a4aa3e461dde82507aa2da493d4b501dcf78f7`。`SHA256SUMS.txt`全部18个文件校验通过；含Windows EXE／PCK、许可证、试玩表、元数据、包内日志及两个Mac启动脚本。
- `PACK_AUDIT_PASS resources=110 required=34`，实际PNG与JSON存在，开发源／参考／测试文件均未进包；主入口保持真实游戏。包内角色144、剧情623、引导213、第四周反馈199、跨进程存读131／24均零失败。
- Mac实际包内渲染168项通过，使用`--require-pack`确认无源码覆盖；3×样本截图与源码版逐字节一致。`character_lab.tscn`以包内独立场景实际启动并正常退出，无脚本错误。没有执行Windows EXE的真机测试。
- `Play-on-Mac.command`玩实际游戏，`Character-on-Mac.command`看角色；二者调用本机固定Godot，不是独立分发的Mac App。候选使用`ProjectWumingCharacterPrototype`独立存档目录，不覆盖旧版。

这次Day29～35的工程交付与候选验证完成；以下人设认可和体验遗留继续保留，不据此宣称整周人工验收或首月门通过。此后的交付记录提交仅改文档，不更换上述候选的运行时代码／素材。

## 人工评审与边界

[试玩意见表](./docs/week5_playtest.md)可直接写意见。人设比例、好看与否、攻击打击感仍待用户认可；目前是最小像素动作族，没有新地图、其他角色正式美术、每武学独有动作或完整特效。身法暂复用落点守势，不声称拥有独立闪避动画。守势／吐纳复用护剑姿态，后续可拆，但不据此新增战斗规则。

探索场景仍沿用灰盒背景／交互物绘制，不声称全场景已具备正式多层遮挡美术；战斗人物按格子纵向排序。代码源支持逐层编辑但不是图形编辑器工程，正式量产前可迁移格式。

第四周待复测：码头第二入口、修订后的动机／命卷／质证引导、情报收益与快读体验。用户最近反馈仍指出动机和操作用途不清，不能用自动测试替代这项确认。首月体验门、新玩家样本、Windows真机、实体手柄仍未通过。当前只推进已授权的测试素材，不启动正式美术量产。

## 来源

imagegen内置工具生成的[四向参考与提示规格](./docs/art_reference/protagonist_week5_prompt.md)仅供内部讨论。运行时像素源由Codex按既有规范编写，不读取生成图、不使用其他游戏图像；源码和生成内容已分别登记。无配音／音乐／新字体引入，无商店上传。

## 2026-10-08脸部反馈修订

用户指出实际像素主角脸太黑、与生成参考差距大，并初步肯定首版新外观候选后继续要求完成第五周。本轮将反馈落实到原生32×48测试素材；[生成候选及修订记录](./docs/art_reference/protagonist_front_pixel_trial_20261008.md)继续作为内部参考。没有把高清候选缩小或取色，也没有更改11色色板、脚底(16,44)、57帧槽、播放时序、碰撞和移动／战斗数值。

### 实际改动

- 正／侧／背面头部改为独立几何模板，正面脸颊与额头扩大亮肤色色块、下颌用暖影收边；侧脸有独立鼻眼与发际，不再在正脸上盖深色矩形。背面保持后脑，镜像只用于侧头与方向衣物，文袋和持剑手仍按解剖侧别处理。
- 重做交领、衣襟折叠、宽袖与松裤；四向步帧的脚部区域交替改变，一只脚抬高一像素、一只脚保持row43，倒地也贴同一落地线。仍是最小测试动作族，不宣称人物外观已定稿。
- 样本预览新增←／→暂停逐帧；能回绕末帧、四向同步前后检查，空格继续播放。旧入口和1／2／3倍率保留。

### 验证与实际截图

| 范围 | 新版结果与证据 |
|---|---|
| 像素源／PNG | `CHARACTER_SOURCE: 220 checks, 0 failures`；原有源／导出／11色／二值透明契约保留，另检验头部亮肤色面积和连通性、两侧皮肤一致性、脚部交替和落地线；日志`builds/qa/character_source.log` |
| 运行时与逐帧预览 | `CHARACTER_PIPELINE: 150 checks, 0 failures`；逐帧暂停／回绕、同步方向以及原有动作／受伤／倒地／重试通过；日志`builds/qa/character_pipeline.log` |
| 实际角色渲染 | Mac Apple M4 Compatibility，182项零失败，另捕获四向全部4个行走相位；`builds/qa/week5_refined_character_render.log` |
| 实际战斗键盘流程 | 433项零失败，真实命令、取消、胜利／重试和界面边界；`builds/qa/week5_refined_combat_render.log` |
| 实际开场／探索渲染 | 中英、住所／码头入口与质证教学234项零失败；`builds/qa/week5_refined_onboarding_render.log` |
| 完整回归 | `./tools/check_project.sh`输出`PROJECT_CHECK_PASS`；状态、探索／碰撞、技能预览、剧情闭环和跨进程存读全部通过，各子步骤日志在`builds/qa/`；不是只跑源生成自测 |

已实际查看[1×](./docs/week5_evidence/refinement_20261008/week5_walk_1x.png)、[3×](./docs/week5_evidence/refinement_20261008/week5_walk_3x.png)、[直刺](./docs/week5_evidence/refinement_20261008/week5_thrust.png)、[横斩](./docs/week5_evidence/refinement_20261008/week5_slash.png)、[护剑](./docs/week5_evidence/refinement_20261008/week5_guard.png)、[倒地](./docs/week5_evidence/refinement_20261008/week5_down.png)、[探索](./docs/week5_evidence/refinement_20261008/exploration.png)、[战斗](./docs/week5_evidence/refinement_20261008/battle.png)。正面和侧面有更大的连续亮肤色色块，袖裤与朝向清楚；预览文字在640×360内，地面锚点稳定。图像审阅属于主代理检查，不代替用户对气质／动作自然程度的判断。

新版PNG SHA-256：`e13be6ae0ed90c069bcd195d396b3557b13ac8cfbea97fb95c9dd05f632c0358`；JSON仍为`d600fddcbe1def27e727ef0ebaa41e39535018e0f4ac281a1a73a3dbf55d8146`，固定导出契约未改变。

### 更新的独立候选

美术／逐帧实现本地提交`e946a41`，试玩包链接修订本地提交`243ebb9`。由干净工作树构建的**本轮推荐包**为：

`builds/week5/0.5.0-week5-prototype_243ebb9_20261008T154756Z/`

- 版本`0.5.0-week5-prototype`，`dirty=false`，提交完整值`243ebb9d3eb402f25f18277f649db94ff331e80e`；源快照SHA-256：`bc022b58c926be4856cf9388b79cdedfb56214808836d4007dabaf36f1618122`。
- PCK SHA-256：`8467e7a29a6e9293023e1dded21407ed616b42929e8e6caa6fe46bfc4cae2d62`；SHA256SUMS列出的22个文件全部通过校验。包内运行时审计`PACK_AUDIT_PASS resources=110 required=34`，开发源与生成参考未进入PCK；四张实绘参考作为包外`review/`资料随试玩表提供。
- 实际包内角色151、剧情623、引导213、第四周反馈199、跨进程存读131／24项全部零失败。Mac Apple M4实际包内渲染183项通过，`--require-pack`确认没有源码覆盖，16张角色截图经`cmp`与源码实绘逐字节一致；日志`builds/qa/week5_refined_final_pack_render.log`，截图在`builds/qa/week5_refined_final_pack_visual/`。
- 实际启动包内`character_lab.tscn`并于12帧后正常退出，无脚本错误；日志`builds/qa/week5_refined_lab_entry.log`。可执行的`Character-on-Mac.command`看样本、`Play-on-Mac.command`玩流程；使用本机固定Godot，不是独立Mac App。存档目录仍为`ProjectWumingCharacterPrototype`。
- 发现初次修订包的`PLAYTEST.md`链接仍指向仓库里的评审／截图，已修正构建器：附带四张实际截图，构建信息链接改为本包文件；`PLAYTEST_LINKS_PASS files=5`，全部链接在候选目录内可解析。首次中间包`..._e946a41_20261008T154300Z`保留，但不作为最终推荐。两次PCK字节有差异，因此最终包单独执行了渲染验证，没有用中间包结果替代。

构建完整日志`builds/qa/week5_refined_bundle_build.log`。上述是本地Mac验证，没有执行Windows EXE真机测试，也未推送或商店发布。此后的文档记录提交不改变本候选的运行时代码或素材。

本周剩余的是新版外观／步态人工评审，以及先前明确保留的体验／硬件检查。已经处理的脸部反馈不要求重写；[试玩表](./docs/week5_playtest.md)只需填写修订后意见。未获得用户确认前，不启动第六周任务或地图／NPC量产，不声称第五周人工验收或首月体验门通过。

## 2026-10-08交付规格复核

继续目标时重新对照六个月计划、Day29～35和美术规范，而不是仅以既有绿色测试判定完成。发现并修正两处表现层差异：共享角色阴影由14×5改为以脚底为中心的16×6固定整数像素椭圆；战斗中的主角排序改用正在插值移动的实际显示脚底，不再按提前更新的目标格排序。其他人物仍按格子脚底排序。同层顺序保持稳定，不修改逻辑位置、伤害、行动顺序、碰撞或存档。

针对性验证增加6项阴影几何检查及3项真实战斗对象的排序检查，分别验证移到另一角色脚底上／下方时的前后遮挡，并确认表现测试不改变战斗快照。源码运行时159项零失败，Mac实绘191项、实际战斗433项、开场探索234项零失败；日志分别为`builds/qa/week5_geometry_pipeline.log`、`week5_geometry_render.log`、`week5_geometry_combat_render.log`、`week5_geometry_onboarding_render.log`。完整`./tools/check_project.sh`已再次结束并输出`PROJECT_CHECK_PASS`，子日志在`builds/qa/`。本轮更新的18张截图沿用`docs/week5_evidence/refinement_20261008/`，不是旧包的验证截图。

### 逐日验收审计

| 要求 | 当前权威证据 | 状态 |
|---|---|---|
| Day29：网格、锚点、方向、色板、源格式及参考隔离 | `05_art_bible.md`、像素源README、`hero_pixel_source.gd`及参考来源登记；固定640×360、32×48、脚底(16,44)、11色 | 工程完成；正式人设未定稿 |
| Day30：四向4帧、待机复用、文袋侧别、可重复导出 | `test_character_source.gd`逐帧比较源与运行时PNG／JSON，检查透明度、色板、帧序与侧别；220项通过 | 工程完成 |
| Day31：真实探索运动、冲刺、停步、暂停／失焦、碰撞与整数显示 | `test_exploration_controller.gd`85项实际物理／输入／失焦注入检查；实际探索截图；仍为180／300速度、20×12碰撞 | 工程完成；人的手感判断未验 |
| Day32：拳、直刺、横斩、护剑、受击、倒地共57槽 | 源与元数据、逐帧像素比较、样本所有动作截图；恢复姿态明确允许复用 | 工程完成；自然程度未验 |
| Day33：探索／战斗复用、真实命令、取消、伤亡／重试、不改规则 | 共享`hero_visual.gd`；运行时159项与实际战斗433项；新增可见脚底排序与固定阴影契约 | 工程完成 |
| Day34：1×／2×／3×、手动逐帧、最近邻导入与完整回归 | `character_lab`与191项实际渲染；源测试校验导入参数；全量项目检查 | 工程完成 |
| Day35：评审、候选、来源、交接与风格认可 | 本评审、可编辑试玩表、AI／素材登记；独立候选及包内验证记录 | 工程交付待本轮新包记录；用户认可仍缺失 |

用户对新版外观／步态的确认尚未收到，不能把程序验证或本代理查看截图替代为认可。第五周全验收仍不成立。第四周引导复测、首月体验门、Windows与实体手柄分别保留为旧遗留，不借本次工程完成清除；也不据此推进尚未授权的第六周战斗V1任务（六个月排期的第六周并不是地图／NPC量产）。
