# 上行步行最后一相：单次 ImageGen 生产候选（2026-10-12）

## 状态

**第四格实际完成支撑侧交换，四人均可独立矩形取材；等待 root 决定采用。** 本记录不把 Prompt 当作 PASS，不自动改正式角色、renderer 或 manifest。仅一次内置 ImageGen 编辑，没有二次调用或无限迭代。

imagegen 技能主文件、`references/prompting.md`、`references/sample-prompts.md` 已完整读取；采用内置编辑流程并先实际 `view_image` 两输入，以“仅最后一格”为不变量。用户限制的一调用优先于技能通常允许的迭代。没有 CLI/API fallback，没有编程加工 PNG。

## 输入与输出溯源

| 角色 | 文件 | SHA-256 |
| --- | --- | --- |
| 编辑目标：旧四格上行走图 | [旧 up 四格](protagonist_imagegen_walk_up_sheet_20261011.png) | `342a699e4db7f9d9c93678ff1094627a1323d18cd50df2bc0d81b3117d34df0c` |
| 身份/衣装参考：仅第三人背面 | [四向 v3](protagonist_imagegen_turnaround_20261011_v3.png) | `fdb71157e5dae68a1badfa3103a8ded1805742a6ed45e2db76e8d30bb0b5c67f` |
| 内置工具原始输出 | `/Users/witcher/.codex/generated_images/01a12b2d-2d11-7c03-8a02-18550eb8f924/exec-3f0c0c73-30a0-4c91-b59f-e71e85068eb7.png` | `5b5d3b46fa6358d05388c0efef090544d49bde2a62dc80080a14484761aaf611` |
| 项目内原样副本 | [新 up 原 PNG](hero_walk_up_20261012.png) | `5b5d3b46fa6358d05388c0efef090544d49bde2a62dc80080a14484761aaf611` |

实际原图 **1774×887、RGBA**，保持一行四人。使用 `cp -n` 不覆盖复制，原始输出仍保留；双方 SHA-256 相同，证明无裁切、缩放、拼图、抠图、重编码或 Alpha 改动。

## 单次实际完整 Prompt 与参数

工具为内置 `image_gen.imagegen`，`transparent_background=true`。按顺序提供：

1. `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_walk_up_sheet_20261011.png`
2. `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_turnaround_20261011_v3.png`

真正发送的完整 Prompt 如下，未经事后改写：

```text
Use case: precise-object-edit
Asset type: transparent wuxia RPG back-view walking sprite sheet, one horizontal row of four frames.
Primary request: Edit Image 1 with exactly ONE localized pose correction: change only the FOURTH, far-right figure (zero-based frame 3). Keep the first three figures, frames 0/1/2, in their current poses with the same identity, costume, proportions, placement, scale, hair, ribbon, pouch and shoe shapes. Do not redesign them or substitute a new walk sequence.

Input images:
Image 1, protagonist_imagegen_walk_up_sheet_20261011.png: EDIT TARGET. It already contains exactly four back-view walking figures in one horizontal row. The last figure repeats the same screen-right lifted foot as frame 1; fix that fourth figure only.
Image 2, protagonist_imagegen_turnaround_20261011_v3.png: identity/costume reference only. Use its THIRD figure, the BACK view, only to confirm the established rear hair, topknot/ribbon, blue short tunic, white cuff/collar accents, charcoal trousers, blue leg wraps, black cloth shoes with white soles, and the brown pouch on SCREEN-LEFT. Do not copy its frontal or side face and do not alter the first three target figures.

Scene/backdrop: preserve genuine transparent RGBA background and original soft edge alpha, no environment, no floor, no cast ground shadow, no added glow or painted checkerboard. Preserve the same horizontal canvas/aspect ratio and exactly one row, four independent full-body figures with space between them.

THE ONLY POSE CHANGE, FOURTH FIGURE:
This person is seen strictly from BEHIND, walking away / screen UP. SCREEN-LEFT and SCREEN-RIGHT below are literal image sides, not ambiguous anatomical labels.
1. SCREEN-RIGHT leg is the straight, fully grounded SUPPORT leg. Its black shoe stays planted on the common floor/sole baseline of the other grounded shoes. Show the blue wrapped right ankle visibly upright above the planted shoe. Do NOT lift this screen-right foot again.
2. SCREEN-LEFT leg is the raised PASSING leg: bend its knee UP and FORWARD, toward the direction of travel away from the viewer. Lift the screen-left black shoe clearly off the ground so its entire shoe is above the supporting screen-right ankle. The raised shoe/sole belongs unambiguously to the LEFT leg and appears on the LEFT side of this rear-view body.
3. This is the OPPOSITE support/lift state to target frame 1: frame 1 has screen-left support and screen-right lift; the edited frame 3 MUST instead have screen-right support and screen-left lift. Do not reproduce frame 1 with only a different ribbon, shoe tilt or arm.
4. Reverse the arm swing accordingly: SCREEN-LEFT arm swings back toward the viewer and is lowered/visible beside the left hip; SCREEN-RIGHT arm swings forward away from the viewer with a bent elbow and naturally foreshortened hand. Keep exactly two attached arms and two correctly attached legs.
5. Brown document pouch remains attached on SCREEN-LEFT hip, naturally visible and consistent size; do not move it to screen-right or mirror the shoulder strap.
6. Keep the same compact established body proportions, head size, short blue costume, ribbon length, ankle wraps, shoe size and complete full-body framing as frames 0/1/2. Use the same grounded sole line, not a higher or lower floating floor. Leave enough transparent room around all shoes and limbs.

Invariants: frames 0/1/2 unchanged in identity, pose and layout; fourth figure rear view only, no eyes/nose/mouth/face on the back of the head; no head turning into profile; no horizontal mirroring of the whole sheet; no change of direction or costume; no extra figure, props, weapon, lettering, title, frame numbers, grid lines, border or watermark. Exactly four figures in one horizontal row, each complete and separate.
Output: one new original PNG of the localized fourth-frame correction only, preserving transparent alpha. This is a one-call review candidate, not automatic runtime adoption.
```

## 实际查看结果

生成后实际 `view_image(detail=original)` 查看项目内副本：

- 最后格不再抬 screen-RIGHT 鞋：右腿直立支撑，右鞋落在其他支撑鞋同一底线；左膝弯曲、左鞋明显离地并显示后向鞋底，形成与第 1 格相反的支撑/抬脚状态。
- 左臂后摆、下垂可见，右臂前摆缩短；文袋仍在 screen-LEFT。四人均为背面，没有在后脑画眼鼻或转成脸/侧脸，没有武器或新道具。
- 头身、蓝短衣、白袖、发髻蓝带、绑腿白底鞋身份目视保持。四个 >127 主体 bbox 均从 y=46 开始，支撑鞋底最大 y 的 exclusive-end 为 861/860/860/860，差异约 1px，未见变成两行或一人额外缩放。
- 这解决的是“最后格重复第 1 格右脚抬起”的定向缺陷；不以静帧替代实际 8fps 循环播放对速度/步相节奏的检验。

### 不可声称的像素不变量

前 0/1/2 格的身份与姿态目视保持，但内置生成对整张有重绘，**不能声称前三格原始像素完全不变**。只读 RGBA 比较（同尺寸；仅统计原/新 Alpha >127 并集）：

| 格 | 并集主体像素 | RGBA 有变化的像素 |
| --- | --- | --- |
| 0 | 152935 | 151455 |
| 1 | 148889 | 147255 |
| 2 | 152389 | 150739 |

此处“RGBA 变化”包含 Alpha/颜色细微重采样，不等于已重做身份。若采用时要求前三格严格保持原图像素，可在 manifest 中使用旧图 0/1/2 的 GPU region 加新图 3 的 GPU region；两张完整 PNG 都保持原样，**不要**为此裁切拼出新 PNG。最终选择由 root 负责，本任务不编辑 manifest。

## 四格只读测量

按现有只读工具执行 `--source walk_up_production docs/art_reference/hero_walk_up_20261012.png 4 1`。全部 Alpha >127 像素恰形成 4 个完整 8 连通主体，没有分离的剑/手/脚组件；每个最小完整 bbox 内邻人像素为 0，均未触画布边。推荐 GPU 矩形包含原始 2px 边缘：

| 格 | 完整主体 bbox [x,y,w,h] | 推荐 GPU region [x,y,w,h] | 邻人 >127 像素 |
| --- | --- | --- | --- |
| 0 | [73,46,304,815] | [71,44,308,819] | 0 |
| 1 | [524,46,317,814] | [522,44,321,818] | 0 |
| 2 | [956,46,312,814] | [954,44,316,818] | 0 |
| 3 | [1388,46,311,814] | [1386,44,315,818] | 0 |

增量结果保存在 [独立 regions JSON](hero_walk_up_regions_20261012.json)，没有覆盖或改动旧 `hero_source_regions_20261012.json`，也没有改分析脚本。

原始 Alpha 事实：总 1,573,538 像素；Alpha=0 为 915,679，1..254 为 656,553，255 为 1,306，>127 为 605,720。原始 Alpha 原样保留，不执行二值化。Alpha=0 的隐藏 RGB 不当作可见光晕；此记录不从透明预览背景推断 halo。

## 交付与停点

已完成原图副本、完整一调用溯源与四格只读测量。没有修改正式 PNG、正式 manifest、renderer、主记录、旧 snapshot 或脚本；未 commit/build/export。生成到此停止，root 决定采用与后续动画播放检查。
