# 左向相反接触帧 contact2：单次原图记录（2026-10-12）

## 结论与停点

**单次输出已原样存档，但未可靠兑现指定的相反接触/摆臂，不应宣称成功替换 left[2]。**

实际查看的近侧大袖臂仍向 screen-RIGHT 后摆，另一较远袖臂向 screen-LEFT 前伸；没有实现“近侧左臂沿肩—肘—白袖口连续前摆”。前景裤腿轮廓仍像接到左前落地鞋，无法可靠证明“近侧左腿后撤、远侧右腿前踏”已经交换。不能只因后鞋抬跟或 Prompt 写了 opposite-contact 就标 PASS。

只调用一次内置 ImageGen；到此停止，没有二次生成、编程加工或无限迭代。root 决定是否保留为其他姿态参考；本任务没有接入 manifest，没有改 old left 的 0/1/3、任何正式 PNG、renderer、主记录或构建包。

## 输入与输出溯源

已完整读取 imagegen 技能主文件及 `references/prompting.md`、`references/sample-prompts.md`，先实际 `view_image(detail=original)` 两输入。技能用于区分“身份参考”与“姿态指令”、锁定不变量并保存原图；一调用限制优先于通常允许的迭代。

| 角色 | 文件 | SHA-256 |
| --- | --- | --- |
| 身份/左脸/衣装参考，不继承第 2 格腿相 | [旧 left v2](protagonist_imagegen_walk_left_sheet_20261011_v2.png) | `ec5a362ac2a56ab1f8a35329f72d50a5b7c786cc7eed6e95bf475140beb02575` |
| 辅助身份参考，不继承错误袋遮挡 | [四向 v3](protagonist_imagegen_turnaround_20261011_v3.png) | `fdb71157e5dae68a1badfa3103a8ded1805742a6ed45e2db76e8d30bb0b5c67f` |
| 内置工具原始输出 | `/Users/witcher/.codex/generated_images/01a12b2d-2d11-7c03-8a02-18550eb8f924/exec-1719fa6c-64ad-4309-908d-5f17215267aa.png` | `1600b389f946adb24329601640057e75a48e4ce5289ab3ad171305ac9faecd0b` |
| 项目内原样副本 | [contact2 单体原 PNG](hero_walk_left_contact2_20261012.png) | `1600b389f946adb24329601640057e75a48e4ce5289ab3ad171305ac9faecd0b` |

原始输出实际 **1024×1536、RGBA**，恰一名完整主角。采用 `cp -n` 不覆盖复制，源文件保留在内置工具默认目录；双方 SHA-256 相同。没有裁切、缩放、拼图、抠图、调色、描边、重编码、Alpha 二值化或任何 PNG processing。

## 工具参数与完整实际 Prompt

- 工具：内置 `image_gen.imagegen`，未使用 CLI/API fallback。
- 调用次数：1。
- `transparent_background=true`。
- `referenced_image_paths` 顺序：
  1. `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_walk_left_sheet_20261011_v2.png`
  2. `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_turnaround_20261011_v3.png`

以下是真正发送的完整 Prompt，不用事后修正掩盖输出缺陷：

```text
Use case: stylized-concept
Asset type: ONE original transparent full-body wuxia RPG walking sprite, LEFT opposite-contact phase, replacement for left walk frame 2 only.
Primary request: Generate exactly one full-body side-profile walking figure facing screen LEFT, using the SAME approved protagonist identity and body proportions. This is a small calm WALK contact step, not running. The pose must clearly reverse the near/far leg contact relationship compared with frame 0 in Image 1. Do not generate a sheet or more than one figure.

Input images:
Image 1, protagonist_imagegen_walk_left_sheet_20261011_v2.png: identity, LEFT face, hair, head/body proportion and costume reference ONLY. Keep that exact recognizable left-facing face, dark hair/topknot with white band and blue rear ribbon, blue short cross-collar tunic, off-white inner collar/cuffs, white waist tie, charcoal loose trousers, blue leg wraps, black cloth shoes with off-white soles. Do NOT copy its frame 2 legs, which still visually repeat the near-forward contact. The old first, second and fourth figures will be retained separately, so do not redraw that four-figure sheet.
Image 2, protagonist_imagegen_turnaround_20261011_v3.png: auxiliary identity/costume reference only, especially its second LEFT-facing head. Do NOT use its left-facing pouch occlusion as an anatomical instruction and do not copy the opposite right-facing figure.

Scene/backdrop: genuinely transparent RGBA, no floor, no environment or ground shadow, no added aura/glow, no text. Preserve original generated alpha rather than imitating a checkerboard.
Style/medium: same compact dark-outlined pixel-styled/cel-shaded illustrated character as the inputs; same face, head size relative to torso, short clothing, palette and shoe proportions. Do not redesign or stretch the character.
Composition: SINGLE complete character, head to both complete shoes, centered on a portrait canvas with generous transparent margins. A small ordinary walking stride and stable vertical torso, not a deep lunge, sprint, jump or huge split stance.

Critical anatomical and action contract:
The figure faces SCREEN LEFT. His anatomical LEFT side is NEAR the viewer, and his anatomical RIGHT side is FAR from the viewer. Show the near/far overlap clearly through normal outlines and existing subtle garment shading, NOT through temporary diagnostic colors.
- NEAR / anatomical LEFT trouser leg trails BACK toward SCREEN RIGHT. Its foreground thigh runs from the near LEFT hip diagonally back/right into its own knee, blue-wrapped lower leg and rear/right shoe. That rear shoe's TOE lightly contacts the common floor line behind the body while its HEEL is visibly raised. It is the trailing leg, NOT the forward planted leftmost boot.
- FAR / anatomical RIGHT trouser leg leads FORWARD toward SCREEN LEFT. Its thigh emerges from the far RIGHT hip behind the foreground thigh, continues visibly and plausibly through its own knee and blue-wrapped shin, and ends in the front/left black shoe planted on the floor. The leading leftmost shoe is the FAR RIGHT leg, not the NEAR LEFT leg. Both leg-to-hip chains must remain anatomically continuous, not disconnected or silently crossing into the other leg.
- NEAR / anatomical LEFT arm swings FORWARD toward SCREEN LEFT, opposite its trailing near-left leg. Make a continuous near shoulder -> upper arm -> elbow -> off-white cuff -> forearm -> empty hand. Modest relaxed elbow bend, not a punch or detached hand.
- FAR / anatomical RIGHT arm swings BACK toward SCREEN RIGHT, behind the torso. It has a separately attached sleeve/elbow and empty hand; do not merge it into the near forearm or pouch.
- The brown document pouch is attached to the NEAR anatomical LEFT hip, recognizably visible with its body/flap, naturally partly covered by the moving limb or tunic, not teleported to the far hip and not reduced to a completely hidden brown sliver. Keep the cross-body strap anatomically consistent. Do not mirror a right-facing sprite and thereby swap arm/pouch sides.

Must keep: approved LEFT profile face, hair/ribbon, identity, head-to-body proportions, blue short tunic/collar/cuffs, charcoal trousers, leg wraps, shoes and normal natural palette. Exactly two continuous arms and two continuous legs, full head/feet in image.
Avoid: repeating near-left-leg-forward contact from the old sheet, swapping only footwear while keeping the same thigh/knee phase, pasted/disconnected rear leg, any weapon, new accessory, right-facing or frontal pose, running proportions, temporary red/green diagnostic limb colors, numbers, labels, text, watermark, grid, border, multiple figures or sheet.
Output: ONE original transparent PNG, review candidate only. Other old walk frames 0/1/3 remain untouched; there will be no follow-up generation for this request.
```

## 真实视觉复审

生成后再次实际 `view_image(detail=original)` 查看项目内 PNG：

| 检查项 | 实际事实 |
| --- | --- |
| 身份/方向 | 单人朝 screen-LEFT，左脸、发髻白带蓝 ribbon、蓝短衣白领袖、绑腿白底黑鞋仍是原主角；不建议重做已认可脸或比例 |
| 完整肢体与帧布局 | 恰一个完整头脚，无邻人、无格线文字/诊断颜色；不是新四格 sheet；步幅仍属小步，非奔跑/大劈叉 |
| 文袋 | 棕色袋身/袋盖在可见近侧髋，较旧左向窄边更清楚，有衣袖/手臂自然遮挡；这一点不能证明腿臂同时正确 |
| 近侧臂 | 大前景肩袖接到 screen-RIGHT 侧下垂手，仍是后摆；screen-LEFT 前伸手接到另一袖臂，**未实现指定近侧臂前摆连续链** |
| 接触鞋 | 左前鞋落地，右后鞋确有抬跟/斜底姿态；但是这只证明鞋的位置，不证明 anatomical near/far 腿交换 |
| 腿到髋的关系 | 左前大裤腿轮廓看似仍覆盖另一腿；不能可靠认证左前鞋属于远侧右腿、右后抬跟鞋属于近侧左腿。输出更像旧原相变体，不能写完整 opposite-contact PASS |
| 四相任务边界 | 新图不自动替换 left[2]；old 0/1/3 原图保持。生成没有再调用；root 自主评估采用范围 |

## 只读几何与 Alpha 事实

使用已有只读工具执行 `--source walk_left_contact2 docs/art_reference/hero_walk_left_contact2_20261012.png 1 1`（仅 stdout，不改工具/旧 snapshot）。

- Alpha >127 / 8 连通恰 1 个主体，共 **490365** 像素。
- 完整主体 bbox **[162,81,712,1419]**。
- 推荐带原始 2px 边缘 GPU region **[160,79,716,1423]**。
- 邻人 >127 像素 **0**；自身 >127 像素裁切 **0**；未触画布边。
- 原图总 1,572,864 像素；Alpha=0 为 **1042232**，Alpha=1..254 为 **530632**，Alpha=255 为 **0**。原始 Alpha 保留，不因没有 255 就拒绝新显示路线。
- Alpha=0 的隐藏 RGB 不当作游戏可见 halo，也不根据透明预览背景作光晕结论。

几何可取材不等于摆臂/接触相正确。本记录保留单次实际失败事实和可复用外观价值，不把它伪装成已补齐步相。没有 commit/build/export。

