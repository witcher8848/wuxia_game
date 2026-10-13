# 左向 contact2 v2：反向姿态几何单次重绘（2026-10-12）

## 结果与范围

**本 v2 实际目视通过定向 contact2 姿态：近臂向左前摆、近腿向右后撤抬跟、远腿向左前踏落地，近侧唯一文袋可见。** 四向身份保持，完整单体可用 GPU region；后续正式资源接入由 root 负责，本任务没有改任何代码或 manifest。

本 v2 策略只调用 1 次内置 ImageGen。历史失败版另有自己的单次记录，仍保留，不把此前失败隐藏或覆盖。这里采用已生成的 RIGHT contact2 为**唯一腿/臂几何参考**，旧 left v2 仅作为脸、发型与衣服身份参考。不是程序镜像、粘贴、裁切或调色。

已完整读取 imagegen 技能主文件及 `references/prompting.md`、`references/sample-prompts.md`；先实际查看两输入，生成后再次 `view_image(detail=original)` 查看保存原图。技能用于标清输入角色、锁定身份不变量、保留原始文件；单次限制优先于常规迭代流程。

## 输入、输出、旧失败版

| 角色 | 文件 | SHA-256 |
| --- | --- | --- |
| 输入 1：唯一腿/臂相位几何；内置工具直接反向重绘 | [RIGHT contact2](hero_walk_right_contact2_20261012.png) | `64e6c083ab605328fd6223ec873356be16d3131b6b6f71a7b294beabfb17d17a` |
| 输入 2：仅 LEFT 脸/发型/服装身份；忽略其腿臂相位 | [旧 left v2](protagonist_imagegen_walk_left_sheet_20261011_v2.png) | `ec5a362ac2a56ab1f8a35329f72d50a5b7c786cc7eed6e95bf475140beb02575` |
| 工具原始输出 | `/Users/witcher/.codex/generated_images/01a12b2d-2d11-7c03-8a02-18550eb8f924/exec-33e20c34-102f-41c5-be91-6640edf2b116.png` | `cdbc17a2f773732672e10284f245d50bf088300efddaff65646dfffd20835f39` |
| 项目内原样 sibling | [LEFT contact2 v2 原 PNG](hero_walk_left_contact2_20261012_v2.png) | `cdbc17a2f773732672e10284f245d50bf088300efddaff65646dfffd20835f39` |
| 历史失败 v1：未用作本次输入、未覆盖 | [失败原图](hero_walk_left_contact2_20261012.png) | `1600b389f946adb24329601640057e75a48e4ce5289ab3ad171305ac9faecd0b` |

实际输出 **1024×1536 RGBA PNG**，恰一人完整头脚。使用 `cp -n` 非覆盖复制，内置工具原始输出保留。源/副本哈希相同；失败版与两输入哈希亦复核未变。没有任何程序位图镜像、crop/resize/save、拼图、抠图、描边、重编码或 Alpha processing。

## 工具参数与完整实际 Prompt

- 内置 `image_gen.imagegen`，本 v2 调用次数 1；未用 CLI/API fallback。
- `transparent_background=true`。
- `referenced_image_paths` 顺序：
  1. `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/hero_walk_right_contact2_20261012.png`
  2. `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_walk_left_sheet_20261011_v2.png`

真正发送的完整 Prompt 如下，不以事后修订覆盖历史：

```text
Use case: precise-object-edit
Asset type: ONE transparent full-body wuxia RPG LEFT-contact walking sprite.
Primary request: Redraw Image 1 facing SCREEN LEFT instead of screen right, preserving its clear arm/leg PHASE GEOMETRY after the facing reversal. Use Image 1 as the ONLY pose/limb geometry source. This must be one full-body original illustration, not a sheet. Restore the single document pouch to the newly NEAR anatomical LEFT hip. Preserve approved character identity using Image 2's LEFT profile.

Input 1, hero_walk_right_contact2_20261012.png: EDIT TARGET and SOLE reference for the step, thigh overlaps, arm swing, planted versus heel-raised shoe geometry. This is already the correct contact2 phase: foreground/near arm forward, foreground/near leg trailing, opposite far leg leading. Redraw this SAME clear silhouette and limb arrangement toward LEFT. Do not invent another default walk pose.
Input 2, protagonist_imagegen_walk_left_sheet_20261011_v2.png: LEFT FACE/HAIR/OUTFIT identity reference ONLY. Take its recognizable left-profile face, dark topknot hair with white band and blue ribbon, blue short tunic, off-white collar and cuffs, white waist tie, charcoal trousers, blue shin wraps, black shoes with off-white soles. Ignore ALL its arm and leg poses. Do not inherit its frame-0/2 near-leg-forward mistake or its pouch being hidden.

Required redraw of Input 1's pose to LEFT:
- Face and torso are genuinely side-profile toward SCREEN LEFT.
- The large, foreground NEAR shoulder/sleeve is anatomically LEFT. Its continuous upper arm -> elbow -> off-white cuff -> forearm -> empty hand swings FORWARD toward screen LEFT, matching the orientation-reversed outline of Input 1's foreground arm. This is a relaxed walk swing, not a punch. The far arm is independently attached and swings BACK toward SCREEN RIGHT.
- The foreground NEAR/anatomical LEFT thigh and trouser leg TRAIL toward SCREEN RIGHT. Reproduce Input 1's near-thigh overlap, knee shape and continuous hip-to-shin connection in the opposite horizontal facing. Its rear/right shoe has heel raised and toe touching the floor.
- The background FAR/anatomical RIGHT thigh and leg LEAD toward SCREEN LEFT, continuing from the far hip through knee and shin to the front/left shoe planted flat. Retain the clear foreground/background overlap from Input 1; do not silently attach the leading shoe to the near thigh. Do not swap only shoes while keeping the old thigh phase.
- Use only ONE brown document pouch, now on anatomical LEFT/NEAR hip, visible beside the tunic with its flap and normal partial natural occlusion. Repaint the strap/pouch appropriately for this left-facing anatomy. Do not retain a far-side hidden bag, add a second bag or change the arm phase to reveal it.

Style and invariants: same compact approved head/body proportions, recognizable LEFT face and hair from Input 2, same short blue costume, natural palette and outlined pixel-styled cel shading; no new diagnostic limb colors, new face, adult/tall proportions or running pose. A calm small walking contact step, stable torso, complete topknot/ribbon, two complete arms, two complete legs, complete shoes. Keep Input 1's portrait full-body composition and ample transparent margins.

Backdrop: genuinely transparent RGBA, preserve generated soft edge alpha. No floor, cast shadow, added glow, scenery, weapons, extra props, text, numbers, frame labels, grid, border, watermark or second figure.
Only the image generator is to redraw the new left-facing figure; no external/programmatic bitmap mirroring or modification. Output ONE new original transparent PNG. This one-call sibling candidate will not overwrite either reference or the previously failed LEFT contact2.
```

## 实际目视复审

判定来自保存后原图，不来自 Prompt 的要求。

| 项目 | 实际观察 |
| --- | --- |
| 左向与身份 | 脸与躯干朝 screen-LEFT；大眼左 profile、深色发髻白带蓝 ribbon、蓝短衣白领袖、绑腿白底黑鞋保持原角色，没有重做脸/高瘦比例 |
| 近侧左臂 | 大前景肩袖连续接肘与白 cuff，前臂/空手明确伸向 screen-LEFT。与失败 v1 的大袖臂向右后垂不同 |
| 远侧右臂 | 较远袖独立连接向 screen-RIGHT 后摆手，未与近臂融合或画成漂浮手 |
| 接触腿相 | 保留 RIGHT contact2 朝向反转的髋/大腿重叠与膝脚轮廓：近侧腿向 screen-RIGHT 后撤，后鞋鞋跟高、鞋尖在低位；远侧腿向 screen-LEFT 前踏，前鞋平底落地，不是仅交换鞋形 |
| 肢体连续与步幅 | 双腿从髋经膝/绑腿连续到对应鞋，双臂完整；短步、躯干稳，非跑步/跳跃/大劈叉 |
| 唯一文袋 | 棕袋身/盖在近侧左髋可见并自然部分遮挡；只有一个袋，不继承 RIGHT 远侧隐藏袋或加第二袋 |
| 完整性 | 单体完整发髻/手脚，画布边未裁切，无额外人物/武器/文字/诊断颜色 |

本次定向静帧可交付用于替换 left[2]；这不代替正式 8fps 0/1/2/3 循环播放对重心、脚底锚点和节奏的检查。old left 0/1/3 保留原源图，本任务不创建整张新 sheet、不编辑正式资源。

## 只读 GPU 区域与 Alpha

用既有只读工具 `--source walk_left_contact2_v2 docs/art_reference/hero_walk_left_contact2_20261012_v2.png 1 1` 测量（stdout；没有改分析脚本或旧 snapshot）：

- Alpha >127 / 8 连通恰 1 个完整主体，**430689** 像素。
- 最小完整 bbox **[134,93,724,1374]**。
- 推荐原始 2px 边缘 GPU region **[132,91,728,1378]**。
- 矩形内邻人 >127 像素 **0**、自身 >127 像素裁切 **0**，未触画布边。
- 总 1,572,864 像素；Alpha=0 **1106519**，Alpha=1..254 **466345**，Alpha=255 **0**。保留原始 Alpha，未二值化。
- Alpha=0 隐藏 RGB 不视为游戏可见 halo，不用透明预览底色伪证柔光。几何测量也没有被当作腿臂动作的替代审查。

生成已停止；只新增本 PNG 与本 MD，失败版保留。没有改代码、manifest、主记录、正式 PNG，没有 commit/build/export。

