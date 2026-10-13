# 主角 imagegen 行走试验：先验证动作可控性

日期：2026-10-10。用户目标：“更接近，进一步推进”。状态：继续推进中的隔离动作试验，完整行走循环尚未通过，未接入游戏。

本记录保留最初四次调用与当时的失败边界。后续已执行临时裤腿诊断／恢复色并形成四原图显示候选，见[单帧推进及2026-10-11复核](./protagonist_imagegen_walk_single_progress_20261010.md)；后续证据不反向改写本阶段未通过的条带结果。

## 决策与范围

用户认可的是首图长相／少年气质方向；尚未回复32×48／48×72／64×96的后续试验选择。自动续行本目标时，主代理明确按推荐48×72显示框暂做隔离行走试验，不把未回答当成批准变更正式生产规格。现有32×48图集、角色源、碰撞、数值和存档均保持不变。

最终人物图全部由内置 imagegen 生成／编辑，没有程序重画像素、裁切写回、缩小保存或手工修补。只有额外的骨架引导图由Godot线／圆／文字绘制，用作姿态输入，不是角色外观底稿或运行时美术。未使用CLI、外部API或密钥；具体底层图像模型版本未另核实。

## 实际结果与失败边界

1. 首轮四帧条带保住了人物外观，但0／2近似重复同一开步，1／3像同一侧腿抬起，近侧手一直在后。等宽分区还切到0／2的前脚尖，被切碎片出现在1／3左下。素材不通过。
2. 条带v2让后半周期近侧手前摆、远侧手后摆，有真实进展；腿仍近似同相，脚尖跨格未解决。素材仍不通过。
3. 改成单帧姿态试验后，人物身份基本保持，但近侧臂前摆未兑现，裸颈略拉长；同色宽松裤与髋部遮挡不足以证明近／远腿交换。未认作合格反相帧。
4. 加入骨架姿态输入后，[引导版单帧](./protagonist_imagegen_walk_right_pose2_guided_20261010.png)近侧臂前摆明确兑现，远侧臂后摆，脸、肩领和文袋基本保持，大片光晕明显减弱。两脚前后分开符合引导，但近／远腿的连续归属仍不能仅凭同色裤腿可靠确认。它证明了姿态引导对手臂有帮助，不等于完整步态／循环完成。

主代理与独立 `hero_simple_visual_review` 都实际查看了原图；技术子代理及主代理另看真实Godot接触表。不用“提示词要求了”充当输出已满足的证据；不把工程PASS当成美术PASS。连续8FPS播放的自然度尚未通过目视验收，目前可证明的是播放时序／交互测试和逐帧视觉。

## 原样归档

原始生成目录：`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/`。仓库副本均与原图哈希一致，没有覆盖旧版。

| 仓库副本 | 原始文件 | SHA-256 |
|---|---|---|
| [首轮条带](./protagonist_imagegen_walk_right_20261010.png) | `exec-4351ff4b-c273-4bfb-9f65-58b3f3963cb3.png` | `66a2beb0d5024eea7ca983a94529df9e6b2441f761adde117102a367c3fbb4fa` |
| [条带v2](./protagonist_imagegen_walk_right_20261010_v2.png) | `exec-74786361-e102-43df-b47c-6e1d90e63370.png` | `375b47d7c7d1b9a3915ae4ce18ccd4d98b3fc51eb92f414cec8abc589a1c1a4d` |
| [单帧试验](./protagonist_imagegen_walk_right_pose2_trial_20261010.png) | `exec-cb933f06-5091-4ec3-b34f-a0b29b022183.png` | `b69e429c0ec41ffb43b7aee862a228cc3681fb91af78629b4bd3fe6d87691b4d` |
| [骨架引导单帧](./protagonist_imagegen_walk_right_pose2_guided_20261010.png) | `exec-8bc56232-c661-44e9-a4f0-45b8db107c7b.png` | `a387e5b041279834b690164097951ec40e926a9265582816f85fb8a52a0b2b9e` |

原文件RGBA读取（仅分析，不改图）：

| 阶段 | 实际尺寸 | alpha范围 | alpha=0 | alpha=1～254 | alpha=255 |
|---|---|---|---:|---:|---:|
| 首轮条带 | 1774×887 | 0～255 | 833,035 | 738,944 | 1,559 |
| 条带v2 | 1774×887 | 0～255 | 855,365 | 716,855 | 1,318 |
| 单帧试验 | 1024×1536 | 0～254 | 1,030,272 | 542,592 | 0 |
| 引导单帧 | 1145×1374 | 0～255 | 1,175,944 | 395,762 | 1,524 |

仍不是原生48×72、二值透明或有限色板的生产精灵；请求透明背景不等于实际已满足生产透明度。

## 真实显示与验证

独立工具：[preview_hero_imagegen_walk_20261010.gd](../../tools/preview_hero_imagegen_walk_20261010.gd)。读取原条带完整四分区，以48×72显示框等比最近邻显示；4帧8FPS，Space暂停、左右暂停逐帧、1／2切亮暗底、Esc退出。未修改分区来掩盖跨格，未创建裁切后的角色资源。

首轮证据：[亮底接触表](./hero_imagegen_walk_20261010/contact_sheet_light.png)、[暗底接触表](./hero_imagegen_walk_20261010/contact_sheet_dark.png)，同目录另8张逐帧截图。
v2证据：[亮底接触表](./hero_imagegen_walk_20261010/v2/contact_sheet_light.png)、[暗底接触表](./hero_imagegen_walk_20261010/v2/contact_sheet_dark.png)，v2目录另8张逐帧截图。

v2分隔线两侧共5列的alpha>127像素数，主代理读取原图与工具读取一致：x443为296、x887为0、x1330为293。首轮相应是224／0／186。工具明确输出 `SOURCE_CONTENT_WARNING`，不把边界检查只限于坐标合法当成素材完整。

技术子代理验证两版只读各23项0失败、真实capture各70项0失败；主代理独立重跑v2同样通过并实际看接触表。测试覆盖4帧8FPS与0.5秒循环、按键、暂停／逐帧、640×360真实渲染截图、源／现有角色／碰撞控制器哈希不变，不覆盖近远腿解剖归属、动画自然度、原生像素网格或用户审美认可。headless capture明确退出2，不写假图。

```bash
# v1交互，追加 -- --variant=v2 可观察定向修订版
./tools/godot.sh --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://tools/preview_hero_imagegen_walk_20261010.gd

# v2实际渲染证据
./tools/godot.sh --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://tools/preview_hero_imagegen_walk_20261010.gd -- --capture --variant=v2

# v2只读验证
./tools/godot.sh --headless --path . --script res://tools/preview_hero_imagegen_walk_20261010.gd -- --verify-only --variant=v2
```

## 骨架输入来源

[姿态引导图](./hero_imagegen_walk_20261010/pose_guide_opposite_contact.png)由本项目[独立Godot脚本](../../tools/render_hero_walk_pose_guide_20261010.gd)真实渲染为600×600。没有输入任何人物位图，只绘制线、圆和标签；不是对现有图像的程序编辑。

蓝色近侧／角色左臂前摆、左腿后伸；灰色远侧相反。两脚指向画面右且共用y526基线，头和躯干直立。图中颜色仅编码肢体归属，不是要求更改主角衣色。图片SHA-256：`1e66e8a2df35f6cefba5927b709d457c23c13ae1d9c7bd2a9d49afe4ec949e18`。

```bash
./tools/godot.sh --path . --rendering-method gl_compatibility --script res://tools/render_hero_walk_pose_guide_20261010.gd -- --capture
```

只在独立窗口设置600×600，不修改project.godot或游戏视口；headless拒绝捕获。

## 后续未完成项

先验证近远腿连续归属，再形成真正的四阶段循环；当前不能直接批量扩展四向16帧并称动画完成。可考虑仅临时区分近／远腿颜色的诊断图，确认连接／遮挡后恢复衣色并重新核对，但尚未执行。不擅自用程序补脚、补手或恢复原生像素。正式生产尺寸与新外观仍需用户确认；后续还要通过真实尺寸、动画稳定性、遮挡及素材来源／生产合同验收。

## 四次调用的完整实际提示词

全部为内置 `image_gen.imagegen`，`transparent_background: true`，使用下面列出的本项目图像 `referenced_image_paths`，未传 `num_last_images_to_include`。第四次的第二输入是本项目骨架图，不是第三方图片。实际提示词如下。

### 1. 首轮朝右四帧

实际输入均位于 `docs/art_reference/`：`protagonist_imagegen_turnaround_20261010_v2.png`。

```text
Use case: identity-preserve
Asset type: four-frame side-view walking animation reference strip for the original pixel-style wuxia RPG protagonist; an isolated animation candidate, not the final production atlas.
Input images: Image 1 is the character identity and costume reference. Use ONLY the rightmost, image-RIGHT-facing profile as the visual anchor for all four frames.
Primary request: Create exactly FOUR consecutive walking poses in a single horizontal row of FOUR equal-width transparent cells. EVERY pose faces image-RIGHT. This is a walk cycle, NOT another four-direction turnaround. The young man walks in place; his head and torso stay at the same cell-relative center, scale and height, with only a very small natural vertical bob.
Pose order, left to right: 0 near/anatomical-left leg forward and far/right leg back, arms counter-swing; 1 passing pose with the far foot lifting forward under the body; 2 far/right leg forward and near/left leg back, opposite arm swing; 3 the other passing pose with the near foot lifting forward. Show actual alternating steps, not four copies of idle or four versions of the same stride. Keep the grounded foot at a common baseline in each cell; leave enough transparent room for the stride and all hair and both feet.
Preserve: exactly the same youthful facial identity, small restrained eyes and calm expression, head size, black fringe/topknot, short neck, blue-gray cross-collar tunic, off-white collar/cuffs, sash, loose dark trousers and cloth boots. The ONE document satchel remains on anatomical LEFT hip, visible on the near side in this right-facing view, with strap from right shoulder. It can move subtly with the gait but must not disappear or switch sides. No costume redesign between frames.
Style: attractive coherent coarse square pixel clusters and stepped hard edges, grouped simple shading like the reference. No new fabric noise, no smooth painted anatomy.
Composition: four separate full-body poses, evenly centered in equal cells, identical scale and camera. No labels, numbers, borders, contact-sheet decorations, additional figures or directions.
Backdrop: genuinely transparent, without ground, shadows, checkerboard drawing, matte, aura or halos.
Avoid: teleporting head/body, changing face/hair/clothes across frames, foot sliding poses, mirrored entire character, weapons, armor, giant anime eyes, realistic textures, blur, anti-aliasing, text, logos or watermark.
Output intent: faithful enlarged pixel-style walk poses that can be previewed at a provisional 48x72 display size. Do not claim or force an exact native 48x72 bitmap grid.
```

### 2. 条带定向修订 v2

实际输入均位于 `docs/art_reference/`：`protagonist_imagegen_walk_right_20261010.png`。

```text
Use case: precise-object-edit
Asset type: corrected four-frame RIGHT-facing pixel-style walk-cycle reference strip.
Input images: Image 1 is the edit target. Preserve this same character's face, hair, blue-gray costume, body proportions and visible left-hip document bag.
Primary request: Correct the walk-cycle phases and cell-safe layout; do not redesign the hero or turn him in a different direction.
The current first and third poses repeat the SAME stride and all near arms stay behind. Keep the first half-cycle's identity and gait, but make the second half-cycle unmistakably the OPPOSITE stride:
- Frame 0, first cell: near/LEFT leg extends forward toward image-right, far/RIGHT leg back, near/LEFT arm back.
- Frame 1, second cell: near/LEFT leg supports the body, far/RIGHT leg bends and passes forward.
- Frame 2, third cell: near/LEFT leg extends BACK toward image-left, far/RIGHT leg extends FORWARD toward image-right; near/LEFT arm swings FORWARD and far/RIGHT arm swings back. The near/front visible sleeve and hand must now be in front of the chest/bag, not behind it. Distinguish the near boot from the darker far boot by occlusion and shading, not by changing clothes.
- Frame 3, fourth cell: far/RIGHT leg supports the body, near/LEFT leg bends and passes forward; near arm remains in the forward half of its swing. This must NOT repeat frame 1's lifted leg.
Use a modest natural walking stride, not an exaggerated high-knee march. Keep the head facing right, same calm expression and small eyes, fixed cell-relative head/waist center and nearly constant height.
Cell safety: exactly four equal-width cells in a single row, with every figure centered in its own cell. Leave a CLEAR transparent gutter of at least 10% of a cell width on BOTH sides of EACH complete pose, including toe tips and hands. Shorten the stride if needed. No body part may cross a quarter-width cell boundary. All grounded feet share the same baseline; both feet and topknot stay fully inside each cell.
Invariants: no added elements, no wardrobe or bag-side change, no new face, no changed pixel style or extra detail; all FOUR figures face image-right. Bag stays anatomical-left/near hip across all phases.
Background: genuine transparent background, no shadow, floor, glow, checkerboard drawing, borders, labels, text or watermark.
Output intent: the same faithful pixel-style character, now with a readable alternating four-phase gait and safe cell margins; not a final native production atlas.
```

### 3. 单帧反相姿态试验

实际输入均位于 `docs/art_reference/`：`protagonist_imagegen_turnaround_20261010_v2.png`。

```text
Use case: identity-preserve
Asset type: ONE single full-body key pose for a right-facing pixel-style wuxia hero walk-cycle experiment.
Input images: Image 1 is the identity/costume reference. Match its rightmost RIGHT-facing profile. Do not reproduce the four-view sheet.
Primary request: Draw exactly ONE character, facing image-RIGHT, in the opposite contact step of a natural walk. The near/anatomical LEFT arm swings FORWARD in front of his chest. The near/anatomical LEFT leg stretches BACKWARD toward image-left, its foot and shin visible behind him. The far/anatomical RIGHT leg extends FORWARD toward image-right and is the grounded leading foot. This front/right boot is on the farther side and slightly darker; the trailing left boot belongs to the nearer side and retains the clearer blue wrap highlight. Keep the two legs anatomically connected and visibly distinguished by overlap, not two copies of the same leading leg. Arms counter-swing, a modest walking stride, no high-knee running or jumping.
Preserve: the same youthful face, calm alert expression, small eyes, black fringe and tied topknot, short neck, head/body proportions, blue-gray cross-collar cloth tunic, off-white collar/cuffs, waist sash, loose dark trousers and cloth boots. One plain document satchel on anatomical LEFT/near hip, strap from RIGHT shoulder; do not switch bag side. The face, costume and simple grouped pixel rendering must match the reference, not a newly redesigned hero.
Framing: one full-body profile centered in a portrait canvas, topknot and both feet fully inside, 10% transparent margins. Upright head/torso, similar standing height to the reference, no large lean or body rotation.
Style: crisp coarse square pixel clusters and stepped silhouette, attractive readable sprite appearance, limited grouped shading. No extra detail.
Backdrop: genuine transparent background; no ground, shadow, glow, checkerboard drawing, matte, labels, text or watermark.
Output intent: a single opposite-stride reference pose for an isolated animation test, not a native production sprite. Exactly ONE figure, not a strip or comparison.
```

### 4. 骨架引导反相姿态

实际输入均位于 `docs/art_reference/`：`protagonist_imagegen_turnaround_20261010_v2.png + hero_imagegen_walk_20261010/pose_guide_opposite_contact.png`。

```text
Use case: identity-preserve
Asset type: one single opposite-contact walk key pose for a pixel-style wuxia RPG hero.
Input images: Image 1 is the ONLY identity, costume and pixel-art style reference: use its rightmost right-facing profile. Image 2 is a POSE-ONLY skeleton guide, NOT a style/color/character reference. Its blue lines mean near/anatomical-left limbs, and gray lines mean far/anatomical-right limbs.
Primary request: Draw exactly ONE full-body right-facing figure of the same young man from Image 1, adopting the limb geometry and overlap of Image 2. The NEAR visible arm runs diagonally DOWN-FORWARD toward image-right, in front of the torso; its elbow is only gently bent, not a boxing pose. The NEAR leg runs DOWN-BACKWARD toward image-left. The FAR arm runs backward and the FAR leg runs forward toward image-right. This must be the opposite walking contact step from the usual near-arm-back/near-leg-forward pose. Use the skeleton to establish these positions before rendering the existing clothing over it.
Preserve: Image 1's recognizable youthful face, calm expression and small dark eyes, topknot/fringe, short neck, head/body proportions, blue-gray cross-collar tunic, off-white collar/cuffs, sash, loose dark trousers and boots. Keep ONE document satchel at anatomical LEFT/near hip; the near arm can overlap in front of the bag but must not move it to the far side. Clothing colors come ONLY from Image 1; do not color the body blue/gray to imitate the guide.
Framing: one complete character centered with generous real transparent margins, both feet on the same baseline, modest natural stride, upright head/torso. Do not copy the guide's text, lines, labels, circles or ground baseline into the output. Do not make a four-view sheet or add other figures.
Style: same attractive coarse grouped pixel language and stepped silhouette as Image 1. No smooth illustration, fabric noise, enlarged eyes, long neck or new costume details.
Backdrop: genuinely transparent; no environment, shadow, glow, aura, checkerboard drawing, text, labels or watermark.
Output intent: a faithful opposite-stride key pose for an isolated animation experiment, not an exact native production sprite.
```
