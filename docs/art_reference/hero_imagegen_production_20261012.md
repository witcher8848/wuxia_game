# 主角imagegen生产接入（2026-10-12）

用户最新目标：“做的很好，继续完善，按照这个标准推进，完成第五周任务。暂时不用再问我了，先按照你的想法推进。”据此采用已展示和推荐的原图／原alpha、主体约48×72显示；不再等待规格选择，不重做已认可的脸／服装。武器／倒地绘制范围可更宽；保持640×360、32×32格、20×12碰撞、180／300速度、原规则及存档。

旧32×48源／图集作为历史可重现fixture保留，不冒充新生产角色。新资源原PNG逐字节复制到runtime，GPU仅选矩形显示区域并等比显示；不写裁切PNG、不清alpha、不补人物像素。仍做四向walk4和基础动作57逻辑槽，明确恢复姿态复用。

## 补图1：正面拳／刺四姿态单行

原因：旧2×4前六问题帧的最小完整矩形混入邻人；换为单行从根源消除纵向邻帧，避免mask／修图。
输入：四向v3 `fdb71157e5dae68a1badfa3103a8ded1805742a6ed45e2db76e8d30bb0b5c67f`，旧正面八姿态 `db2547046794b50902d9e6abe5c26f50c81f0673445eb9a80aa5dba53616d91b`。主代理已实际查看。内置imagegen，transparent_background=true；实际结果随后追加。

```text
Use case: identity-preserve
Asset type: four FRONT-facing basic-combat sprite poses for the existing accepted wuxia boy.
Input images: Image 1 is the approved identity, face, costume, head/body ratio and pixel-style reference, use its FRONT figure. Image 2 is ONLY the four action examples from its TOP TWO ROWS, not a layout to copy.
Primary request: Output exactly FOUR complete FRONT-facing figures in ONE HORIZONTAL ROW on a wide genuinely transparent canvas. Left to right: 0 right-fist preparation, 1 right-fist punch toward the viewer, 2 right-hand sword thrust preparation, 3 right-hand sword thrust toward the viewer. Do NOT add any second row, slash, guard, hit or idle pose.
Pose details: 0 right fist chambered near right ribs, left guard, no sword. 1 same right fist extended toward viewer, naturally foreshortened, left guard, no sword. 2 right hand draws one plain iron straight jian beside his anatomical right hip, elbow bent, blade directed forward toward viewer/down, ready for a thrust, NOT swinging horizontally across the abdomen. 3 same right arm clearly extends forward, sword and point foreshortened toward viewer/down, visibly different from the preparation.
Orientation and asymmetry: All four show FRONT face with both eyes and frontal shoulders. His anatomical RIGHT hand starts at image LEFT; the document pouch is always at anatomical LEFT hip / image RIGHT, strap from image-left shoulder. Never swap sword hand or pouch hip. Same face, eyes, black fringe/topknot and blue tie, blue-gray short cross-collar tunic, white collar/cuffs/waist ties, dark loose trousers, blue leg wraps and dark boots with light soles as Image 1. No character redesign.
Layout: ONE row of FOUR separate full-body figures. Same scale and shoe baseline. Each complete body, hands and complete sword point must fit within its own virtual quarter, with generous transparent gaps. Keep poses compact and reserve empty margins. No weapons or feet crossing a neighbor; no vertical neighbor at all. No drawn grid, label, border or numbers.
Style/background: Preserve grouped stepped pixel-style rendering and original costume colors. Genuine transparent alpha, no ground, cast shadow, aura, effects, labels or watermark. Output only the four-figure single-row sheet.
```

### 补图1实际结果

原始`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/exec-edd4e727-dc09-4f75-af40-fa40eb23f58c.png`，原样副本[正面拳／刺四格](./hero_front_fist_thrust_20261012.png)，2172×724，SHA `22a8cbd0d55dd426d147b7f0d644f5f4f783b7638275771ead7980dc971a1377`。主代理实际看图，正面拳收／伸、剑下收／前刺不同，身份保持；独立8连通只读测量恰4完整主体、无邻人、未触画布，带2px原边缘的GPU区域为[56,8,463,699]、[600,8,466,699]、[1166,8,455,699]、[1688,8,459,699]。旧污染0..3可以换源，不制作裁切PNG。

## 补图2：左向刺蓄／斩蓄单行

输入旧左向八姿态 `61908b4f2353ea1e3dd0f5b244daef0dda26075b68605069986b102b647e7147` 与四向v3 `fdb71157e5dae68a1badfa3103a8ded1805742a6ed45e2db76e8d30bb0b5c67f`；已实际查看。内置imagegen，transparent_background=true，实际结果另记。

```text
Use case: identity-preserve
Asset type: two LEFT-facing sword preparation sprites for the accepted wuxia boy.
Input images: Image 1 gives ONLY the two action poses to reproduce: its row-1 LEFT sword-thrust preparation and row-2 LEFT overhead-slash wind-up. Image 2 is the accepted face/hair/costume/head-to-body identity reference, use its left-facing boy. Do not copy either sheet layout.
Primary request: Output exactly TWO complete full-body LEFT-facing figures in ONE HORIZONTAL ROW, with wide genuinely transparent separation. Left figure: sword thrust preparation, right elbow bent with sword grip retracted by his right waist, plain iron jian aimed screen LEFT, left hand empty guarding. Right figure: overhead slash wind-up, same right hand raises the complete sword above/behind shoulder, left hand empty guarding. Both face screen LEFT, same body scale, common shoe baseline.
Identity invariants: Keep the accepted youthful face, eyes, fringe/topknot, blue ribbon, blue-gray short cross-collar tunic, off-white cuffs/collar and waist ties, dark loose trousers, blue leg wraps and cloth boots with light soles. No face, hairstyle or outfit redesign.
Asymmetry: single small brown pouch at anatomical LEFT hip, the near side in this left-facing view; visible but naturally partly covered by the empty left forearm. Right sword arm is the far-side arm; preserve its connected shoulder/elbow/grip even if torso turns slightly into a natural fighting stance. Do not mirror right-facing figures or swap sword to the pouch-side hand. One plain straight iron jian, no ornate weapon, no second sword.
Framing: Wide landscape, only ONE row and two full figures. Each body and COMPLETE sword/hand/hair/boot stays inside its own half with generous transparent padding, including overhead blade. Do not add a second row or any neighbor above/below. Same compact fighting proportions, not tall realistic anatomy. No grid, numbers, labels, shadow, ground, glow, effects or watermark. Match the reference's grouped stepped pixel-style colors. Actual transparent background. Output only the two-figure sheet.
```

补图2原始：`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/exec-423cbff6-8ad8-417d-ada6-c213e6c991c6.png`，原样[左向刺／斩蓄](./hero_left_thrust_windup_20261012.png)，SHA `3d56c94e91ebd081bf953d3f8bc529db4f701fb428e9f4d573a0f577e4565773`，1774×887。两主体独立、0邻人，2px原边缘GPU区域[161,194,707,657]／[1147,52,579,800]；主代理实际看图，剑柄手／上举斩和腰位刺不同、脸服装基本保持。斩蓄手臂右握与左空手分离，不能宣称只改布局或非目标像素完全保持。

并行补图：[正面斩蓄／护剑完整记录](./front_windup_guard_20261012.md)，原样1536×1024 SHA `8ba02b3c7d82e2a51b6e887cdcee05d2eded0a257faeeb71ac3a14d78987db6c`，两主体0邻人；推荐GPU区域[155,127,620,821]／[874,172,542,776]。三次补图解除此前八个战斗问题帧的邻人污染，不生成裁切PNG。

## 补图3：正面最后passing与落脚纠正

输入旧正面4步图 `44bcfc55bda0e80df1d33d907e9888920874487724c60fcdf1bce0c32fbd4188`，主代理已实际查看。内置imagegen，transparent_background=true；旧最后格鞋底较高且抬脚不明确，单独纠正，实际结果另记。

```text
Use case: identity-preserve
Asset type: targeted correction of the fourth FRONT-facing walking pose in this existing four-figure sheet.
Input images: Image 1 is the edit target, figures numbered by position 0,1,2,3 left to right. All face the viewer/screen DOWN.
Primary request: Keep figures 0,1,2 and the accepted face/costume unchanged. Change ONLY the walking limbs and grounded height of the final/rightmost figure 3 so it is the opposite passing phase to figure 1. Its SCREEN-LEFT / anatomical RIGHT leg must be straight, supporting the body, with the whole planted shoe sole at exactly the same floor level as the planted shoes in figures 0 and 2. Its SCREEN-RIGHT / anatomical LEFT knee must lift forward toward the viewer, with that left shoe CLEARLY above the planted shoe/floor, not lower or planted. Both legs connect naturally at the hips. The anatomical RIGHT / screen-left arm swings forward while the other moves back, opposite the lifted left leg.
Invariants: Same youthful face/eyes/fringe/topknot/blue tie, head-to-body ratio, blue-gray tunic, off-white cuffs/collar/waist ties, dark loose trousers, blue ankle wraps, cloth boots/light soles, and brown LEFT-hip pouch at screen RIGHT. Do not shift the head/torso center sideways, change scale or redesign any character. Only one horizontal row, four complete bodies, full feet and hands with transparent gaps.
Genuine transparent alpha background, no ground/shadow/glow/labels/extra pose/sword. Output only the corrected four-figure single-row sheet.
```

### 补图3实际取材

原始文件 `/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/exec-3485d0d1-3f46-4a50-b350-be8a863d2743.png` 已原样复制为[正面步态修订](./hero_walk_down_20261012.png)，SHA-256 `ba5c29790df4430e2159962d0a3d12ddc34974b8998f3b337f462e1942b2557b`。实际目视：最后姿态的画面左鞋落地、右膝抬起符合纠正目标；第三姿态却退回与第一姿态相同的支撑腿，不能整条采用。帧表因此保留原正面条带的0／1／2，只从新原图取第3格；是GPU区域选择，不写裁切PNG或修人物像素。

## 其余补图与最终取材

- [背面行走](./walk_up_production_20261012.md)：第3格修正为另一条腿前传，四格独立，保留背面身份与文袋左侧。
- [朝右条带](./walk_right_production_20261012.md)：文袋远侧遮挡改善，但第2格退回重复步相；只用0／1／3。[独立右contact2](./walk_right_contact2_20261012.md)提供反相的第2格。
- [首次左contact2](./walk_left_contact2_20261012.md)失败，不入帧表；[左contact2 v2](./walk_left_contact2_20261012_v2.md)用右contact2的腿臂几何重新生成左向原图，近侧空手前摆／腿后撤、远腿前踏与近侧文袋成立。没有程序镜像，旧左条带取0／1／3，第2格取v2原图。
- 旧八格图中只采用独立区域安全的姿态；不采用此前污染的正面0／1／2／3／4／6与左向2／4。四向攻击末段恢复复用各方向第一步，idle也复用第一步。实际57槽并不是57幅独立绘画。

## 已完成的共享默认接入与源码验证

新帧表 `assets/runtime/characters/chr_protagonist_imagegen_20261012.json` 已保存并成为 `hero_visual.gd` 的默认选择，SHA-256 `ed5a342f06b62191a718551521020c5159ffc2f5a5b97f9bf582bc5385098561`；57逻辑槽、29clips、15原PNG。每格记录原图路径／SHA、原图尺寸、GPU显示区域、等比显示尺寸及脚底锚点。约48×72为名义框，主体高约68显示像素，不假称原生48×72位图；武器与倒地允许更宽的矩形。

水平锚点按实际身体中轴取材，垂直按真实鞋底取材：不能每帧把水平中心锁到当前支撑鞋，否则左右换脚会造成全身左右跳。战斗下垂剑尖实际复核均高于鞋底，不用剑尖误作地面。锚点／缩放只存在于元数据，不修改角色PNG。旧源／图集／JSON哈希保持原值。

导入采用无损模式、最近邻、无mipmap、无预乘、禁止 `fix_alpha_border`；原图与runtime副本字节一致，完整原图RGBA与导入纹理RGBA一致。正常探索／战斗／角色样本同用新默认，不需要隐藏的opt-in参数。

- `python3 tools/build_hero_imagegen_manifest.py --verify`：57槽／15originals PASS；生成元数据可用bundled Pillow环境运行同脚本 `--emit`，只读测量、stdout输出，文本更新仍经代码评审。
- `test_character_imagegen_pipeline.gd`：新默认headless **1183项／0失败**；实际物理键盘移动、180／300速度、20×12碰撞、停步／暂停／失焦、四向播放、合法战斗guard／取消／hit／down／retry、规则快照不变、手动倍率／方向／逐帧均通过。
- Apple M4 Compatibility实际源码渲染 **1255项／0失败、14张截图**，日志 `builds/qa/week5_imagegen_source_render.log`；[本轮截图与意见入口](../week5_playtest.md)。主代理和独立代理逐张看图，未见邻人碎片、人物／武器／脚底裁切；左第2格体量与其他相位一致，非另一个角色。
- 完整 `./tools/check_project.sh` 退出0并输出 `PROJECT_CHECK_PASS`；旧源220、legacy播放159、renderer597和新生产1183项均通过，其余探索／技能预览／剧情／跨进程存读回归通过。源码验证不是包内验证，后者以第五周最终交付记录为准。

本轮9次内置生成的完整提示词分别保存在本页及上方逐项子记录，原PNG均保存到项目本地；AI-ART-035记录生产用途。没有手工／程序补画像素、外部API调用、远端提交／商店发布。最终人设喜好、动作节奏与其他硬件体验仍可后续反馈，不冒称用户签字。

## 2026-10-13独立包收尾

新包 `builds/week5/0.5.0-week5-prototype_imagegen_645127f_20261012T154536Z/` 已实际构建成功；其元数据15份原PNG／manifest／import身份与当前源码preflight完全一致。真正包内headless1092／0，Mac同PCK Compatibility实绘1164／0、14图，最终marker明确 `packed=true`。主代理逐张看包内图，人物、鞋与剑完整、没有旧角色替代或邻人碎片；原图字节仍保持。

PCK SHA-256 `714c927dd2dfdc3c0b86aa24fd2da486a46486b7ae9ed21e7a9886aedc937cbe`；真实dirty源快照、存档隔离、启动器、许可证、校验清单及逐日最终核对见[第五周评审](../../11_week5_review.md)。历史源／旧包／失败记录保留，未提交／推送／商店发布。
