# 朝左八基础战斗姿态：2026-10-11 单次内置 ImageGen 候选

> 2026-10-12显示纠错：下方历史“实际柔光”判断仅来自原图预览，后来证明不足。Godot亮／暗底每次17,048个alpha0抽样位置均保留背景、零误差，6,252个近不透明人物位置可见；主代理实际看过[亮](./hero_combat_composite_20261012/light_640x360.png)／[暗](./hero_combat_composite_20261012/dark_640x360.png)截图，没有预览的大范围柔光。保留旧经过，不再把隐藏RGB当可见halo；跨格与持剑侧别疑点仍不因此通过。

## 状态与范围

- 状态：**原图已存档，未接入；八格完整通过结论不成立。**
- 本次只生成一次，没有迭代，没有二次调用；采用内置 `image_gen`，未使用 CLI/API fallback。
- 请求用途是补充 LEFT 基础战斗视觉候选，不是默认激活、不代表人类已认可新的显示尺寸合同。
- 用户此前认可的主角身份、脸型、头身与服装继续作为不重做的身份基准。
- 本记录仅覆盖该单次生成与只读逐格复审；没有修改代码、正式角色资源或主评审记录，没有 commit/build/export。
- 使用 imagegen 技能：已完整读取 `SKILL.md` 及必需的 `references/prompting.md`、`references/sample-prompts.md`；这些指导用于区分身份参考与动作参考、保持不变量并保存原图。单次限额优先于技能通常可迭代的流程，生成后停止。

## 输入、输出与原样性

| 角色 | 文件 | SHA-256 |
| --- | --- | --- |
| 输入 1：仅左脸、头身、发型与服装 identity；不继承旧左向袋遮挡错误 | [四向 v2](protagonist_imagegen_turnaround_20261010_v2.png) | `3ada25005b38414efb54531491c092ca26de69e233d8579e48c4b0c9c5c3df7c` |
| 输入 2：仅八动作类别；不镜像，不继承宽布局、手侧或跨格 | [朝右战斗 v2](protagonist_imagegen_combat_right_sheet_20261011_v2.png) | `e98e0c870eb1c01542121f82fa9fb2527318bf145c3b64efe046bb121ff50175` |
| 原始工具输出 | `/Users/witcher/.codex/generated_images/01a12b2d-2d11-7c03-8a02-18550eb8f924/exec-95787ff2-ac82-4149-8dc2-ba54b5031b43.png` | `61908b4f2353ea1e3dd0f5b244daef0dda26075b68605069986b102b647e7147` |
| 项目内原样副本 | [朝左战斗原图](protagonist_imagegen_combat_left_sheet_20261011.png) | `61908b4f2353ea1e3dd0f5b244daef0dda26075b68605069986b102b647e7147` |

原始输出保留在内置工具默认目录；用不覆盖的 `cp -n` 复制至项目。来源与副本 SHA-256 相同，没有裁切、缩放、抠图、调色、描边、Alpha 修补、重编码或拼图。复审用 `view_image(detail=original)` 实际查看项目内 PNG；像素统计仅只读解码。

输出实际为 **1024 × 1536、8-bit RGBA PNG**。请求两列四行，按等分应为每格 **512 × 384**，竖界 x=512，横界 y=384/768/1152。

## 工具参数与实际发送的完整 Prompt

- 工具：内置 `image_gen.imagegen`
- 调用次数：1
- `transparent_background`：`true`
- `referenced_image_paths`（按此顺序）：
  1. `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_turnaround_20261010_v2.png`
  2. `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_combat_right_sheet_20261011_v2.png`
- 请求尺寸仅写入 Prompt；没有 CLI 尺寸参数或后处理，实际原图尺寸如上。

以下为本次真正发送的 Prompt，完整原样保留，不用事后修正 Prompt 掩盖输出缺陷：

```text
Use case: stylized-concept
Asset type: original transparent wuxia RPG character sprite-sheet candidate, LEFT-facing combat, not a runtime activation.
Primary request: Generate exactly ONE portrait image, requested canvas 1024 x 1536, 2 columns by 4 rows, exactly eight separate full-body combat poses of the SAME approved youthful Chinese wuxia protagonist. Every head and body faces screen LEFT in a genuine left side profile. Use the approved identity without redesigning the face or body.

Input images:
Image 1, protagonist_imagegen_turnaround_20261010_v2.png: identity and costume reference ONLY. Match its SECOND figure (the left-facing head): same recognizable face, dark swept hair and topknot, white topknot band, blue rear ribbon, compact head-to-body proportions, blue short cross-collar tunic, white inner collar and cuffs, white waist tie, charcoal trousers, blue leg wraps, black cloth shoes with white soles. Preserve this identity and palette. Do NOT copy the erroneous occlusion of its left-facing pouch.
Image 2, protagonist_imagegen_combat_right_sheet_20261011_v2.png: action-category reference ONLY (fist windup/extension, sword thrust preparation/extension, overhead slash preparation/downward follow-through, guard, hit recoil). Do NOT mirror this bitmap, do NOT copy its right-facing orientation, its old wide layout, its cross-cell sword, or its anatomical hand/pouch placement.

Scene/backdrop: genuinely transparent RGBA background, no floor, no environment, no cast ground shadow, no glow or aura, no checkerboard painted into the image.
Style/medium: the same crisp, dark-outlined, compact pixel-styled illustrated character as the references; restrained flat cel shading. No restyling into realistic anatomy or smooth 3D.

Layout: portrait 2:3 canvas with an invisible exact 2-column, 4-row grid. Each cell is 512 x 384 if the requested 1024 x 1536 is delivered. Column boundaries x=0,512,1024; row boundaries y=0,384,768,1152,1536. No drawn grid lines. One and only one complete character per cell, eight in reading order.
Keep the body, including topknot and shoes, at about 65-70 percent of its cell height in every cell. All heads, bodies and shoes share the same physical scale and proportions across all eight poses. Give weapons MORE space, not larger characters. Keep each complete figure, weapon, hand, ribbon, pouch and foot inside its own cell with clear transparent padding, at least about 24 pixels from every cell boundary. No weapon crosses into another cell or touches the canvas edge.
Use a shared local shoe-sole baseline about y=340 within each row (global baselines approximately 340,724,1108,1492). Keep the character's body slightly right of the center of each cell to reserve empty space to its LEFT for the fist and sword tips. Maintain stable shoe and foot proportions. Fit the overhead sword within that cell's top margin without shrinking or enlarging only that body's anatomy.

Anatomical side contract, crucial: the character is facing screen LEFT. His anatomical LEFT hip and LEFT arm are the NEAR side, toward the viewer. The brown document pouch stays attached to that LEFT hip and is naturally visible on the near side, recognizable pouch body and flap rather than only a disappearing brown sliver. It must not migrate to the other hip or change size between poses. His anatomical RIGHT arm and RIGHT hand are on the FAR side. The sword is held by that RIGHT hand in every sword pose. Do not horizontally mirror a right-facing drawing and thereby swap handedness or pouch side. Draw a plausible continuous right shoulder -> upper arm -> elbow -> forearm -> hand gripping the sword hilt; no disembodied hand, disconnected forearm, duplicated arm or fake grip. The near left hand is empty and balances or guards naturally, without taking the sword.

Eight cells, reading order:
Row 0 left / cell 0: bare-fist windup, no sword anywhere. Genuine left profile, fighting stance, the far RIGHT fist drawn back near the torso to prepare a punch, near LEFT empty hand guarding, left-hip pouch visible.
Row 0 right / cell 1: bare-fist extension, no sword anywhere. Same stance and scale, far RIGHT fist thrust clearly toward screen LEFT with the elbow extending; near LEFT hand remains a separate guard. A visibly different action from cell 0.
Row 1 left / cell 2: thrust preparation. Far RIGHT hand grips a short straight single sword, elbow bent with hilt near the waist, blade pointing screen LEFT. Near LEFT empty hand is distinguishable and not on the hilt.
Row 1 right / cell 3: thrust extension. Far RIGHT hand and arm extend the short straight sword horizontally toward screen LEFT. Maintain visible arm-to-grip continuity, blade tip completely within this cell. Distinct from the bent-elbow preparation.
Row 2 left / cell 4: overhead slash windup. Far RIGHT hand raises that same short straight sword above/behind the head, right elbow bent, ready to cut toward screen LEFT. All of the sword remains in the cell. Near LEFT hand guards.
Row 2 right / cell 5: downward slash follow-through. Far RIGHT hand finishes a visibly DOWNWARD diagonal cut, with blade now directed down and toward screen LEFT around waist/thigh height, not a duplicate horizontal thrust. Keep the entire blade well inside this cell; near LEFT hand balances.
Row 3 left / cell 6: sword guard. Far RIGHT hand grips the same sword held diagonally upward between the body and screen LEFT. Near LEFT hand remains separately visible and empty. Stable braced feet, readable defensive silhouette.
Row 3 right / cell 7: hit recoil. Same left-facing identity, face may close its eyes in pain, body leans back toward screen RIGHT from an impact arriving from screen LEFT. Far RIGHT hand retains the same sword, lowered safely within the cell; near LEFT hand reacts separately. A clearly different action from guard, no falling pose.

Constraints: exactly eight full characters; all eight face screen LEFT, no right-facing or frontal substitute; identity, costume, hair and head/body proportions unchanged; consistent near-left hip pouch and far-right sword hand; complete limbs and sword within each cell; consistent scale and sole baseline. No text, numbers, labels, title, border, guide lines, watermark, props beyond the specified pouch and one sword in cells 2-7, ground shadows, glow, extra figures or motion trails.
Output intent: one original transparent portrait sheet only, for human review. Do not provide a collage of references.
```

## Alpha 与背景事实（不是新显示合同审批）

只读 Pillow 解码得到：

| 项目 | 值 |
| --- | --- |
| 总像素 | 1,572,864 |
| Alpha 最小／最大 | 0 / 254 |
| Alpha = 0 | 1,089,142 |
| Alpha = 1..254 | 483,722 |
| Alpha = 255 | 0 |

原图确有透明像素，不是整张不透明背景；但实际查看可见每个人物周围大范围灰蓝及暖金柔光/渐变，不能宣称实现 Prompt 的“no glow or aura”。没有据此执行去光晕、二值 Alpha 或任何 PNG 加工。上述数字仅为原始输出事实，**不把尚未由人类选择的严格二值 Alpha／新尺寸合同当作许可或既定验收阈值**。

## 实际逐格复审

以下判断来自实际原图，不是因为 Prompt 写了某要求就认定已做到。坐标仅用于原始等分格合同，边缘位置为目视近似。

| 格号／位置 | 指定动作 | 实际可辨认之处 | 不足与可用边界 |
| --- | --- | --- | --- |
| 0／第 1 行左 | 拳蓄 | 双拳分开，前拳弯曲，与格 1 直拳有明确差异；脸、发髻与蓝短衣保留 | 躯干明显偏三分之四而非严格侧面。不能从此静帧认证“远侧右拳蓄、近侧左手护”的解剖连续性；主体填得过高，鞋底接近行边 |
| 1／第 1 行右 | 拳伸 | 向画面左方伸出长直拳，动作不等同格 0；文袋可见 | 真左 profile 与右远侧出拳不能认证。主体高度及底部留白不足，不可宣称满足 65–70% 格高与 24px 安全边距 |
| 2／第 2 行左 | 刺蓄 | 弯肘、低位水平持剑，剑尖向左；相对格 3 保持蓄势差异 | 握柄连到视觉前景、与近侧文袋同侧的粗大袖臂，不能认证为远侧右手；另一拳独立。剑在本格可见完整，但整张 Alpha/布局问题仍在 |
| 3／第 2 行右 | 刺出 | 向左伸臂直刺，比格 2 更明显伸展；武器类别一致 | 剑尖伸到约 x=499，越过该格左界 x=512。等分会截剑；不能把“保留完整原图”写成“每格完整”。身体也不是严格真侧面，持剑手侧未通过 |
| 4／第 3 行左 | 斩蓄 | 明确举剑过头，和刺的腰位准备不同；另一拳保持分离 | 握柄/上手顶部约 y=755，越过该格上界 y=768 进入上一行。大前景袖臂持剑，远侧右手契约未兑现；无法直接独立等分取格 |
| 5／第 3 行右 | 斩末 | 剑身朝左下，低位斜斩明显区别于格 3 水平刺出；可保留动作参考价值 | 持剑臂仍在视觉前景，近远侧解剖契约不成立或至少无法验证；空手贴近腕部/身体，动作手连续性需复审。不能因此声明该图全部是正确右手持剑 |
| 6／第 4 行左 | 护剑 | 剑斜向左上，稳定防御姿态；与受击格明显不同 | 两手似乎共同握住/贴住柄下方，未兑现“近侧左手空手、与右手独立可辨”。发髻顶部贴近/略越 y=1152 行界；不满足安全分格留白 |
| 7／第 4 行右 | 受击 | 闭眼痛苦表情，躯干向右后仰，剑降低，明显区别于格 6 护剑；完整头脚可见 | 头/胸转为斜面而非严格左 profile；握剑手仍位于近侧文袋前方，不能认证远侧右手。主体、鞋底留白与其他格不完全一致 |

### 全图结论

- 正向：八种基础动作类别均出现，蓄拳/伸拳、刺蓄/刺出、斩蓄/斩末、防御/受击可相互区分；蓝短衣、白领袖、发髻蓝带、绑腿白底黑鞋与文袋仍能识别为原主角。没有提出重做已认可脸或比例。
- 文袋：比此前朝左仅露窄棕边的版本更清晰，近侧可见袋身；但这不自动证明所有持剑手都为正确远侧右手。
- 侧向：头总体向左，躯干多为三分之四斜面；不能称八人全部真左 profile。握剑的近远手侧没有可靠满足输入契约，格 6 还有双手握柄嫌疑。
- 分格：格 3 横向跨列，格 4 纵向跨行，格 6 顶部贴近行界；主体大多填格高度远高于请求 65–70%，鞋底接近行边。整体不是安全的独立 2×4 取格 sheet。放宽 rectangle region 也不能被自动当成修复，因为会改变格合同且可能混入邻格人体或光晕。
- 背景：真实大范围半透明柔光与“no glow”相矛盾；仅记录，没有加工。
- 最终状态：**可保留八动作设计的原始视觉参考候选；不通过“八格完整、正确侧别、可直接取格接入”的结论。** 生成到此停止。没有创建正式 manifest、没有激活默认角色、没有改旧资源或构建包。
