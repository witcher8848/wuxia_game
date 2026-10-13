# 朝右基础战斗宽格重排候选（2026-10-11）

本批继续第五周缺失动作，沿用已认可长相，不改默认游戏。内置imagegen仅一次调用；改为2列4行宽格，目标是让完整剑身留在单格内，不是靠裁剑或扩大分区混入邻人。输出和实际审核随后记录，不能把提示要求当通过。

输入1：`protagonist_imagegen_combat_right_sheet_20261011_v2.png`，SHA-256 `e98e0c870eb1c01542121f82fa9fb2527318bf145c3b64efe046bb121ff50175`，动作／身份参考，不照搬跨格布局。
输入2：`protagonist_imagegen_turnaround_20261011_v3.png`，SHA-256 `fdb71157e5dae68a1badfa3103a8ded1805742a6ed45e2db76e8d30bb0b5c67f`，脸／比例／服装与朝右袋遮挡参考。两张主代理已实际view_image查看。

工具：内置`image_gen.imagegen`，`transparent_background=true`；唯一图像参数为上述两个`referenced_image_paths`，无CLI／外部API／密钥，没有程序改图。

## 完整实际提示词

```text
Use case: identity-preserve
Asset type: eight basic-combat sprite poses for an existing pixel-style wuxia protagonist.
Input images: Image 1 is the existing RIGHT-facing eight-pose sheet, used for the exact character identity and action poses, NOT for its failed layout. Image 2 is the approved four-view face/costume reference; its rightmost figure confirms the RIGHT profile and mostly hidden far-side satchel.
Primary request: Re-layout these same EIGHT distinct full-body RIGHT-facing action poses onto a NEW PORTRAIT transparent canvas in TWO columns and FOUR rows. Read left to right, top to bottom: row 0 punch preparation / punch extension; row 1 sword-thrust preparation / horizontal thrust extension; row 2 sword-slash wind-up / downward follow-through after a horizontal cut; row 3 sword guard / hit recoil. All eight face screen RIGHT. Preserve the existing action differences, especially the bent-elbow lower slash end, not eight idle copies.
Framing: Prefer portrait 1024x1536, so each virtual cell is WIDER than it is tall. Each whole figure has the same body scale and fills only 65-70% of its cell height, leaving real transparent margins. Place torsos slightly left of cell center, so the entire extended fist and sword fit. Complete blades including sharp tips, both shoes, cuffs and hair must stay INSIDE their own cell, with at least 8% empty padding at every edge. No figure, sword or hand may overlap a neighboring cell or touch the canvas edge. Keep a common shoe baseline within each row; no drawn grid or border.
Identity invariants: Preserve the accepted boy's face and small eyes, compact head/body proportions, black fringe/topknot, blue hair tie, blue-gray cross-collar short tunic, white collar/cuffs and ties, dark loose trousers, blue ankle wraps, and dark cloth boots with light soles. Same stepped grouped pixel-style shading, no face or costume redesign.
Anatomy: For every RIGHT profile the anatomical RIGHT arm is the near-side sword/punch arm; show a connected shoulder, elbow, grip. The single brown document pouch stays on the anatomical LEFT hip, on the FAR side: mostly hidden behind the body, at most a small brown edge, never a big near-side pouch. Keep the sword in that same right hand; punch poses have no sword. One plain iron straight jian per sword pose, no ornate or glowing blade.
Background: genuine transparent alpha. No ground, shadow, glow, blur, fake checkerboard, labels, numbers, text, weapon trails, particles, blood, extra people or watermark. Output ONLY the portrait 2-column 4-row eight-pose sheet. Do not copy the old 4-column layout.
```

## 本次原样输出与初审

- 原始路径：`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/exec-39df2c32-8bb4-4087-9bad-9a9aca728ebb.png`。
- [v3原样副本](./protagonist_imagegen_combat_right_sheet_20261011_v3.png)：1024×1536 RGBA；原档／副本SHA-256均为`3dd041ecadc7bbf0f58d2ae74168d9d317e57d7145fede212ade92a17b5f2a60`。alpha范围0～254；全透明1,094,932、部分透明477,932、不透明0像素（254接近不透明，不以0个255宣称整角色明显透光）。
- 主代理实际看结果：八姿态按2列4行排列，拳收／伸、刺收／伸、高举斩／低位斩末、护剑／后仰受击均有区别，完整剑身和鞋未见画布裁切。远侧小棕边延续，脸与服装基本保持；线条较平滑、蓝暖周边柔光仍可见，不宣称像素风和边缘通过。
- 提示要求每人65～70%格高没有兑现。按384像素等高分行，首行鞋底已超过该边界；直接等分会裁鞋。可以另行只读测量不等高的GPU显示区域，但没有执行PNG裁切或写回，也没有正式57槽清单或接入。完整身形不裁画布不等于统一格通过。
- 本轮不因布局局部改善重做已认可脸；目标背景抽离的单独调用如执行，会另记真实提示和新结果，绝不程序扣图。生成模型版本未另核实。

## 第2次：仅背景抽离的定向试验

输入为本页v3（SHA `3dd041ecadc7bbf0f58d2ae74168d9d317e57d7145fede212ade92a17b5f2a60`），主代理先实际view_image查看。仍用内置imagegen和transparent_background=true，唯一referenced_image_paths为v3；不程序扣图、不修改原PNG。输出另存版本并复核，不把“保持不变”要求当结果。

```text
Use case: background-extraction
Input images: Image 1 is the EDIT TARGET, an eight-pose 2-column 4-row sheet of the same wuxia boy.
Primary request: Remove ONLY the diffuse blue, gray and brown haze/glow around the figures. Return the same eight complete figures and swords as clean cutouts on GENUINELY TRANSPARENT empty background. Every pixel outside a figure or sword silhouette should be transparent; no tinted aura, colored matte, cast shadow or fuzzy rim.
Keep unchanged: all eight poses, faces, eyes, black hair/blue tie, blue tunic, white cuffs, brown far-side pouch edges, sword shapes and tips, shoe positions, layout, canvas proportions, body scale and original costume colors. Do not redesign or shift/repaint the characters. Retain the dark stepped silhouette outline; do not erase skin, pale cuffs, sword highlights or soles as background.
No text, checkerboard, borders, numbers or extra marks. Output only the cleaned transparent sheet with the same 2 columns and 4 rows.
```

### 第2次实际结果与2026-10-12更正

- 原始路径：`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/exec-d13b8cae-9d2f-4701-924f-34c08a680d0c.png`。
- [原样抽离试验](./protagonist_imagegen_combat_right_edge_trial_20261011.png)：1024×1536 RGBA，原档／副本SHA均为`f8a05e157268981049bf6ab2752ffab130b3f2fe4718a333374c8148641a31f9`。alpha0为1,095,792、1～254为477,072、255为0；未覆盖v3。
- 输出布局、姿态身份基本延续，但RGBA改变1,482,847像素，双方alpha>127的内部RGB改变402,833像素；不是仅改背景或逐像素保留角色。因此保留试验，不因调用完成就视作正式清边素材。
- **更正初审柔光判断**：v3及试验在(100,200)、(400,200)、(500,200)、(500,500)、(100,700)均是带色RGB但alpha=0。实际Godot合成v3亮／暗底各17,147个alpha0抽样位置都不改变背景，零误差；各6,248个近不透明人物抽样均可见。主代理实际看图，没有之前预览的大范围柔光。原图预览里的隐藏RGB不应被误判成游戏可见halo，背景抽离并未证明必要。
- v3实际显示证据见[亮底](./hero_combat_composite_20261012/light_640x360.png)／[暗底](./hero_combat_composite_20261012/dark_640x360.png)。试验本身未作独立实际合成，因此不把v3检查转移成试验通过；两张旧记录和真实提示均保留。
- 仍需处理的是安全取帧、落脚与动作一致性，未解决等分首行裁鞋，不判整套通过。不继续追加相同清边生成；不程序加工原PNG，不修改正式角色。
