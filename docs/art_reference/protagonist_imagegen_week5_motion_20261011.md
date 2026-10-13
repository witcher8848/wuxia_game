# 第五周 imagegen 动作素材补齐记录

> 后续复核纠错：本页调用1／2中的“朝左文袋远侧、朝右近侧”描述是错误的，按正面袋在画面右／背面袋在画面左这一既定位置，正确关系是**朝左近侧可见、朝右远侧遮挡**。保留真实旧提示词，不倒改调用历史；新批次纠正配件侧别，不重新设计已认可的脸／比例。

2026-10-11。延续用户“继续，不需要调整；完成第五周任务”，保留已认可的少年外观。使用内置 imagegen，不使用程序重绘人物。

目前正式游戏仍使用旧的原生32×48角色。本记录的动作补齐先作为独立候选；原图在游戏约48×72显示的新合同已提出，等待用户确认。不能把外观认可当作尺寸、色板或透明度规则变更的批准。

## 调用1：朝左四帧行走

输入1为已认可身份参考：`protagonist_imagegen_turnaround_20261010_v2.png`，SHA-256 `3ada25005b38414efb54531491c092ca26de69e233d8579e48c4b0c9c5c3df7c`。生成前已经实际查看；只参考身份与朝左侧面，不镜像朝右文袋。

调用方式：内置 `image_gen.imagegen`，`transparent_background=true`。输出原样保存，不裁切、缩小、清边或改写alpha。实际结果与审核随后追加；提示中的要求不等于实际满足。

完整提示词：

```text
Use case: identity-preserve
Asset type: one four-frame walking sprite sheet for an existing pixel-style wuxia RPG protagonist.
Input images: Image 1 is the approved character identity and four-view reference. Use its SECOND figure, which faces screen LEFT, as the orientation reference. Do not redesign him.
Primary request: Generate exactly FOUR complete full-body poses of this SAME boy, all facing screen LEFT in strict side profile, arranged left-to-right in four equal-width cells on ONE wide transparent sheet. These are consecutive phases of one restrained four-frame walking cycle: 0 contact with near leg forward and far leg back; 1 passing with near leg supporting and far knee passing; 2 opposite contact with far leg forward and near leg back; 3 opposite passing with far leg supporting and near knee passing. Arms swing opposite the legs. Small natural step, not running or jumping.
Identity invariants: Preserve the reference's youthful face, small dark eye, compact head-to-body proportion, black fringe/topknot and blue ribbon, blue-gray short cross-collar tunic, off-white collar and cuffs, dark sash, purple-gray loose trousers, blue ankle wraps and dark cloth boots with light soles. The brown document satchel stays on his ANATOMICAL LEFT hip: when he faces screen LEFT it is on the far side and is mostly occluded by his torso. Do not mirror a visible right-facing satchel onto the foreground.
Layout: Four equal cells, same camera, identical scale, head height and common floor baseline. Generous clear transparent separation between figures and margins around every boot, hand and ribbon. No figure or halo may cross a cell boundary. Full bodies and both feet visible; foot phases must genuinely differ. Keep the character centered in each cell without moving his torso sideways between phases. Crisp restrained pixel clusters matching the reference, not a smooth painterly portrait.
Background: genuinely transparent alpha, no floor or cast shadow, no glow, no blurred outline, no checkerboard drawn into the image.
Constraints: Exactly four figures, all face LEFT. No other direction, no sword, no extra accessory, no numbers, no labels, no watermark. Do not alter the accepted face or costume. Output the sprite sheet only.
```

### 实际结果（候选，未接入）

- 原始结果：`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/exec-cbcf8c84-7f76-42e8-8ee6-3d79d92abba1.png`。
- [仓库原样副本](./protagonist_imagegen_walk_left_sheet_20261011.png)：1774×887 RGBA，SHA-256 `89446bcb972f69ed00d63003b3253c706a1180b966c6ed13594b49d9bcaedff4`。源与副本哈希相同，没有程序重绘、裁切或缩小写回。
- 主代理实际看图：四张朝左姿态完整，束发／蓝衣／短布衣身份基本保持，文袋没有镜像到前景。头高与鞋底大致一致；但第0／2及1／3张疑似重复同一腿相，手臂反向摆动不足，**不判完整四帧行走循环通过**。
- 独立`week5_scope_audit`实际以原图分辨率对照四向v2复审：0与2均是左侧鞋在前落地、后脚伸展；1与3均是前脚支撑、后脚屈起，未清楚交换近远腿／支撑腿。近侧大袖手始终在髋后、远臂在身前，缺少反向交替。文袋只有少量身后棕边，没有被放成近侧大袋，但遮挡过多不能验证袋形连续性。结论与主代理一致：身份保持，循环不通过，不建议接入。
- PIL只读统计：alpha范围0～255；透明939,218像素、部分透明632,738像素、不透明1,582像素。仍不满足旧二值透明／有限色板合同；原图不做阈值清边。
- 按整图四等分候选区域为`[0,0,444,887]`、`[444,0,443,887]`、`[887,0,443,887]`、`[1330,0,444,887]`。各区域内alpha>127边界为`(44,37,426,842)`、`(81,37,392,839)`、`(40,37,428,842)`、`(83,37,393,839)`；这是只读显示定位数据，不是裁切后的新PNG或正式脚底锚点。

既有正式PNG／JSON未替换；没有因此声称四向动作、完整第五周或新规格已验收。

## 调用2：朝左后两步相定向修订（新版本，不覆盖旧图）

延续第五周补动作，仍不更改已认可长相／比例。输入1为调用1朝左失败条带，SHA-256 `89446bcb972f69ed00d63003b3253c706a1180b966c6ed13594b49d9bcaedff4`；输入2为四向v2身份参考，SHA-256 `3ada25005b38414efb54531491c092ca26de69e233d8579e48c4b0c9c5c3df7c`。两张已实际查看。内置imagegen、transparent_background=true；不使用CLI或程序修改人物像素，实际结果随后追加。

```text
Use case: identity-preserve
Asset type: targeted pose correction of an existing four-frame LEFT-facing walking sprite sheet.
Input images: Image 1 is the edit target, with four figures numbered here only by position 0,1,2,3 from left to right. Image 2 is ONLY the approved identity/costume reference, especially its second, left-facing figure. Do not redesign his face or proportions.
Primary request: Keep figures 0 and 1 and the four equal-cell layout unchanged. Replace ONLY the limb poses of figures 2 and 3, so they are the OPPOSITE half of the walking cycle rather than duplicates of 0 and 1.
Figure 2: Still strictly faces screen LEFT. Its foreground/near trouser leg must extend BACK toward screen RIGHT, with the trailing heel raised. Its background/far leg must extend FORWARD toward screen LEFT and plant the leading shoe at the floor baseline. The foreground/near arm must swing FORWARD toward screen LEFT: a continuous shoulder, elbow, off-white cuff and hand visibly reach in front of the white waist sash. Its background/far arm swings BACK toward screen RIGHT. This is the opposite contact pose to figure 0, NOT another copy of figure 0.
Figure 3: Still strictly faces screen LEFT. The background/far leg is planted nearly beneath the hips at the common floor baseline. The foreground/near knee is lifted and passes FORWARD toward screen LEFT, with its shoe suspended off the floor under the knee. The near arm relaxes from the forward swing toward the body while the far arm passes oppositely. This is the opposite passing/support-leg pose to figure 1, NOT another trailing bent leg behind him.
Invariants: Keep every figure's youthful face, small dark eye, head/fringe/topknot, blue ribbon, compact head-body ratio, blue-gray short tunic, off-white cuffs and collar, dark belt, purple-gray loose trousers, blue ankle wraps, dark cloth boots with light soles, pixel-cluster style, scale and torso center unchanged. Keep the satchel on the ANATOMICAL LEFT hip, on the FAR side for this left-facing view; mostly occluded, not a big pouch mirrored into the foreground. Do not use differently colored diagnostic limbs.
Composition: Same wide sheet, four complete full bodies in four equal-width cells, identical head height and common floor baseline. No shoe, hand or ribbon crosses any cell boundary. No new figure, direction, sword, accessory, label, number, shadow, glow, watermark, ground or painted checkerboard.
Background: preserve genuine transparency. Output only the corrected four-frame sheet; do not add borders or text.
```

### 调用2实际结果（候选，未接入）

- 原始路径：`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/exec-e8d531a5-9d22-4fc6-af76-7aaffd38b3a0.png`。
- [原样副本v2](./protagonist_imagegen_walk_left_sheet_20261011_v2.png)：1774×887 RGBA，SHA-256 `ec5a362ac2a56ab1f8a35329f72d50a5b7c786cc7eed6e95bf475140beb02575`。没有覆盖调用1，也没有裁切／缩小／阈值清边或程序重绘。
- 只读alpha统计：范围0～255；透明925,653、部分透明646,385、不透明1,500像素，不满足旧二值透明合同。
- 主代理实际看图：第2格近臂确实前摆，第3格出现前抬膝，较调用1有真实姿态变化；第2格前伸腿仍像近腿，没有清楚换成远腿，因此不判完整四相循环通过。第2／3格露出棕袋，但输入提示曾错误要求左向远侧；是否符合正确近侧遮挡由后续独立复审核验，不能把错误提示当规范。
- “保持第0／1格不变”是提示要求，不是像素一致性证明；目前仅观察到身份大致保持，不声称逐像素不变。

## 调用3：四向参考的配件侧别纠正

只更正侧面文袋遮挡，不重新设计脸、服装、比例或站姿。输入1为四向v2，SHA-256 `3ada25005b38414efb54531491c092ca26de69e233d8579e48c4b0c9c5c3df7c`，主代理已实际查看。内置imagegen，transparent_background=true；实际结果随后记录，不覆盖已认可v2，也不自动接入。

```text
Use case: precise-object-edit
Asset type: four-view pixel-style wuxia protagonist consistency reference.
Input images: Image 1 is the edit target and accepted identity anchor. Its figures from left to right are front, facing screen LEFT, back, facing screen RIGHT.
Primary request: Correct ONLY the document satchel and shoulder strap occlusion in the TWO SIDE PROFILES (second and fourth figures). The satchel is always on the boy's ANATOMICAL LEFT HIP. Facing screen LEFT, his anatomical left side is near the camera: show that same small brown satchel at the near hip, partly covered naturally by the near forearm. Facing screen RIGHT, his anatomical left side is far from the camera: hide the pouch behind the torso; show at most a narrow far-side brown edge, never a large foreground pouch. The front view already correctly has the pouch at image RIGHT and the back view at image LEFT; keep those two views unchanged.
Invariants: Keep all faces, small eyes, fringe/topknot, blue ribbon, youthful head/body proportions, body poses, blue-gray tunic, off-white cuffs/collar, dark sash, purple-gray trousers, blue leg wraps, boots/light soles and four-view spacing unchanged. Do not change arms, legs, facial features or scale. Same crisp restrained pixel-cluster rendering. This is accessory occlusion correction, not a character redesign.
Background: genuine transparent alpha, no drawn checkerboard, no cast shadow, no blur or glow. No sword, text, number, border, logo or extra figure. Output the corrected four-view sheet only.
```

### 调用3实际结果与尺寸展示

- 原始路径：`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/exec-1e627763-300d-4c54-8709-67b13321c039.png`。
- [原样四向v3](./protagonist_imagegen_turnaround_20261011_v3.png)：1774×887 RGBA，源与副本 SHA-256 均为 `fdb71157e5dae68a1badfa3103a8ded1805742a6ed45e2db76e8d30bb0b5c67f`；alpha=0为874,166、1～254为697,646、255为1,726。旧v2保留。
- 主代理与只读 `week5_build_audit` 均实际查看：右向前景大袋确已隐藏，纠错局部有效；左向仍只有手臂后窄棕边，近侧袋主体／挂接不清楚，因此仅确认右向遮挡改善，不宣称四向配件全部通过。脸／比例／衣服身份目视延续，不声称非目标像素精确不变。
- 独立尺寸预览增加显式 `--variant=sidefix`；默认仍读旧v2，旧截图不覆盖。两份只读运行各17项零失败；真实 Mac Apple M4 Compatibility 捕获27项零失败，只做GPU原图区域等比显示，没有保存加工后的角色素材。
- 主代理实际查看新 [亮底](./hero_imagegen_size_20261011_sidefix/size_light_640x360.png)／[暗底](./hero_imagegen_size_20261011_sidefix/size_dark_640x360.png)640×360截图，32×48／48×72／64×96三组框均显示完整四向，文字未越界。显示测试不是用户批准新合同，也不是探索／战斗已替换。
- 重现：`./tools/godot.sh --path . --script res://tools/preview_hero_imagegen_size_20261010.gd -- --variant=sidefix`。可按1／2换底色、Esc退出；加 `--capture`取得截图，加 `--verify-only`只读检查。

## 并行生成批次与覆盖状态

本页调用2／3和下述并行图合计7次内置imagegen，全部原图原样保存，登记为AI-ART-033；调用1另属AI-ART-032。未使用第三方图片、CLI或外部API密钥。各子记录包含实际完整提示词／输入哈希／原始输出，不把要求当结果。

| 当前候选 | 实际覆盖与限制 | 记录 |
|---|---|---|
| 朝左v2 | 手臂反摆／抬膝有改善；0／2近远腿交换不明、露袋面积跳变，循环未通过 | 本页调用2 |
| 朝下／正面四格 | 0／2支撑不同；第3格主体下缘高23源像素、反摆不明，未通过循环 | [两次纵向生成](./protagonist_imagegen_walk_vertical_20261011.md) |
| 朝上／背面四格 | 0／1／3同侧支撑，1／3不是相反passing，循环不通过 | 同上 |
| 朝右战斗八姿态v1／v2 | 拳、直刺、横斩、护剑、受击可辨；v2袋遮挡／斩末势改善，但格5剑尖仍跨格，不能按等分复用整套 | [两次战斗生成](./protagonist_imagegen_combat_right_20261011.md) |
| 四向配件参考v3 | 只确认右向袋遮挡改善；左向近侧袋仍未清晰验证 | 本页调用3 |
| 最终倒地1帧 | 真侧卧闭眼、头左脚右、双鞋完整、无血伤／武器／投影；主代理看图确认是倒地候选，不是站立hit替身 | [单次倒地生成](./defeat_20261011.md) |

没有取得四向16步相和57逻辑槽的合格新美术，也没有把静态姿态或旧图集工程测试代替这些缺口。正式图集／JSON／源哈希、20×12碰撞、180／300速度、32×32格与存档保持；未接入／新构建／提交／推送。当前批次到此冻结，不为修脸继续自动生成。

新合同待用户确认的完整含义：保留生成PNG和原alpha，只在GPU显示，角色主体约48×72，武器及倒地绘制包围范围可更宽；不是原生32×48／11色／二值透明生产精灵。物理／规则仍不变。确认前继续将它作为隔离候选，不静默放宽旧测试。

历史记录的侧面约定更正适用于AI-ART-027～032及旧行走候选；旧提示词和旧复审保留作为实际经过，不能继续拿“左远右近”作为新资产验收依据。

### 最终只读交叉复审

`week5_build_audit`实际查看本批行走、四向v3、战斗v1／v2与倒地：左向反摆有改善但接触腿互换不明、袋露出跳变；正／背支撑相位不足；v3只确认右向遮挡纠正；战斗v2格5剑尖约伸至x940，越过x887且扩大矩形会混入邻格脚，不能以扩大区域掩盖。倒地闭眼侧卧与身份完整，但垫头／屈腿偏安静睡卧，败倒含义应由战斗上下文建立，不把静态原图当倒下过程已验收。不建议再重做已认可脸／比例。

### 本批冻结后的工程检查

2026-10-11主代理再次完整运行`./tools/check_project.sh`，退出0并输出`PROJECT_CHECK_PASS`，不是只运行新工具。源220／旧运行时159／工程帧表renderer542，探索、技能预览、战斗命令、剧情与跨进程存读均零失败；31项帧表与13项包外资料单元测试通过。测试日志位于`builds/qa/`；renderer542使用旧图集工程fixture，不是新动作美术通过。根文档与内容检查`REPO_VALIDATION_PASS documents=36`、`git diff --check`通过。

七张本批PNG摘要由主代理再次独立核对，均与子记录一致。旧正式源／PNG／JSON再次核对仍为`b9a67f25008e390b0fa281fa3566a2e29afb2010a185ac6e0b55001d29136a9b`／`e13be6ae0ed90c069bcd195d396b3557b13ac8cfbea97fb95c9dd05f632c0358`／`d600fddcbe1def27e727ef0ebaa41e39535018e0f4ac281a1a73a3dbf55d8146`。未生成新的正式角色包，没有以绿色回归掩盖新图缺陷。

## 2026-10-12：四向战斗补缺、透明合成纠错与接入门审计

上一批之后又完成5次内置imagegen：正／左／背八姿态各一次、朝右宽格重排一次、仅背景抽离试验一次。五份PNG已原样归档，登记AI-ART-034；不程序裁图、清alpha、量化或写回人物，不重新设计脸。子代理中断不是调用仍在运行：`week5_build_audit`／`week5_scope_audit`已errored，`week5_renderer_arch`已完成；已结束生成没有重启。

| 本批 | 原样输出与当前证据 |
|---|---|
| 正面／朝下 | [实际提示词／哈希／逐格审核](./combat_down_20261011.md)，八动作出现，右手画面左、袋画面右；多处跨行、刺蓄透视不够清楚 |
| 朝左 | [实际提示词／哈希／逐格审核](./combat_left_20261011.md)，八动作与近側文袋可见；刺剑跨列、举剑跨行，远侧持剑手及部分身向仍需校核 |
| 朝右v3／抽离试验 | [两次实际提示／哈希／结果](./combat_right_relayout_20261011.md)，横向空间改善、八动作区别保留；等高行取帧仍裁鞋，抽离试验内部RGB大幅重渲染，不作为严格只改背景 |
| 朝上／背面 | [恢复的来源／工具提示字段／审核](./combat_up_20261011.md)，背面八姿态真实生成，袋左剑右；刺出像前举，部分行边不安全。副本hash与原档相同；只读线程恢复`imageGeneration.revisedPrompt`，明确不声称独立核对原始入参 |

### 实际RGBA合成（工程证据，不是动作验收）

此前依据原图预览判断“大范围灰蓝／暖柔光”不充分。四张主候选的很多空白RGB有色但alpha=0，应完全透明。新增`tools/preview_hero_combat_composite_20261012.gd`仅读取完整原图、最近邻整图显示与截图，不制作新角色PNG，默认角色不变。

主代理运行只读26项与真实Mac Apple M4 Compatibility捕获58项均零失败。亮／暗底每次alpha0抽样为down17,338／left17,048／right17,147／up17,802，**全部背景误差0**；近不透明人物位置全部可见。已实际查看[亮底](./hero_combat_composite_20261012/light_640x360.png)／[暗底](./hero_combat_composite_20261012/dark_640x360.png)，没有之前预览的大范围柔光。该结论只适用于本四张原图整图1:8显示，不转移为所有旧图、所有倍率或所有低alpha边缘都通过；不继续重复背景抽离。

重现：`./tools/godot.sh --path . --script res://tools/preview_hero_combat_composite_20261012.gd`；1亮／2暗／Esc退出。加`--verify-only`只读，加`--capture`实际截图。整图保留所有人和鞋不等于安全单帧，不拿这一证据代替取帧／角色动画／正式接入。

### 完成门审计（以新外观而非旧工程为范围）

| 第五周要求 | 当前权威证据 | 判定 |
|---|---|---|
| Day29固定生产规格／来源隔离 | 原计划仍为原生32×48／11色／二值alpha；新图为1024×1536等原图，正式配置尚未获批准变更 | 未完成新合同，不能静默放宽 |
| Day30四向16行走相位／文袋一致／可导出 | 本页及各行走审核仍有重复步相／侧别，旧导出器只覆盖旧角色 | 新外观未完成 |
| Day31真实探索行走／冲刺／停步／暂停等 | `hero_visual.gd`默认仍是旧DATA_PATH、旧PNG哈希未变；新代码只有可选帧表能力 | 新外观未接入、未实景验证 |
| Day32四向基础动作及倒地共57槽 | 四向各8战斗候选与倒地1帧已存在，但分格和部分动作尚有缺陷，无合格新57槽表 | 只有候选覆盖，未完成 |
| Day33共享实际战斗／命令／伤亡反馈 | 旧共享与规则回归通过；新原图未在实际战斗激活 | 未完成新外观复用 |
| Day34正式取帧1×／2×／3×／手动预览／导入回归 | 既有renderer fixture与本次完整原图合成通过，不能替代新正式帧表和真实动作预览 | 证据不足 |
| Day35新独立候选／来源／交接 | 本批来源已记录，旧包只含旧人物；没有新角色包或包内验证 | 未完成 |

剩余动作制作、正确取帧、共享接入、实景回归和新包均保留为完整目标，不将本次RGBA检查或四张参考图重定义成第五周完成。

### 同一权限阻塞的连续核验

主代理只读核验了根线程真实turn状态（不是把子代理turn算入）：`01a12b2b-9b8f-7a62-8342-63e7440ee42e`已请求生产规格选择，`01a12b42-1dba-72a3-8a8f-e3a8899724e6`再次明确未收到批准，`01a12b63-459a-7460-8330-d74c57b3fdf3`仍未收到批准后因用量失败，本轮`01a12dc3-7f3b-76c0-992f-c4cf07cdfcd1`同一选择仍无人工回答。已有至少三个连续目标turn的同一条件；自动目标续行不批准规格变更。

安全候选保存、来源恢复、实际透明合成和误判纠正已经完成。现在不能把原图缩小／加工后冒称原生32×48，也不能直接切换未获批准的新显示合同；继续追加基于该待选路线的参考变体不能代替这一授权。待用户选择：推荐保留原PNG与原alpha、角色主体约48×72显示（武器／倒地绘制范围可更宽），替代旧原生网格／11色色板／二值alpha限制，碰撞20×12、速度180／300、32×32格、规则与存档不变。或明确保留原生32×48，另定符合该路线且不程序重画的制作方式。未选择前不激活、不构建新的正式角色包，不宣称完成。

本轮最后检查：根文档／内容检查36份通过，44项帧表／评审资料单测通过；最新评审图谱18份文档、155本地链接、106文件自包含验证通过；`git diff --check`与再跑原图合成只读26项通过。三正式文件完整hash仍保持。以上只证明保存和检查如实完成，不是新角色接入或第五周通过。
