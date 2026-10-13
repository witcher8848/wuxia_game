# 正面／朝下八战斗姿态 imagegen 候选（2026-10-11）

> 2026-10-12补充实际合成：主代理用Godot原样整图最近邻显示，亮／暗底各17,338个alpha0抽样位置均不改变背景，零误差；6,050个近不透明抽样均显示人物。实际[亮](./hero_combat_composite_20261012/light_640x360.png)／[暗](./hero_combat_composite_20261012/dark_640x360.png)图已查看，没有预览的大范围柔光。保持原图不加工；不将整图显示通过转移为独立取格通过。

## 结论与范围

**不通过完整 2 列 4 行等分可独立取帧 sheet 要求。** 八个人物朝向、右手持剑及左髋文袋基本符合本轮方向要求，刺出与横斩末势可区分；但模型没有按每格高 65–70% 缩小人物，多个全身轮廓跨越行界、鞋底基线不完全一致。可保留为正面动作探索原图，不作为正式动画帧表或第五周完成证据。

仅调用一次内置 `image_gen`，无重试、无后续迭代。产物按原始字节保存，未裁切、缩小写回、清 alpha、修补人物、镜像或合成。只新增本候选 PNG 与本记录，未修改代码、正式资源、AI 主登记，未接入 runtime、未 build、未打包、未提交。

使用 imagegen skill 的参考角色身份保持、实际透明背景与非破坏保存流程，完整读取 SKILL.md、prompting.md、sample-prompts.md；实际查看了两个输入和保存后的输出。

## 输入与输出来源

1. 身份／正面脸／服装／比例／像素风格参考：
   - `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_turnaround_20261010_v2.png`
   - SHA-256：`3ada25005b38414efb54531491c092ca26de69e233d8579e48c4b0c9c5c3df7c`
   - 1,092,188 bytes。
2. 仅动作类型与普通剑设计参考，不作为方向、姿态或身份依据：
   - `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_combat_right_sheet_20261011_v2.png`
   - SHA-256：`e98e0c870eb1c01542121f82fa9fb2527318bf145c3b64efe046bb121ff50175`
   - 1,198,923 bytes。

工具设置：`transparent_background=true`，`referenced_image_paths` 恰为上述两个完整原图路径，未使用 recent-image 自动上下文选择。通过实际 prompt 请求 PORTRAIT 1024×1536，而不是假设内置工具提供尺寸或目标保存路径参数。

- 原始生成路径：`/Users/witcher/.codex/generated_images/01a12b2d-02c3-7b11-b2b2-6107ce8c028f/exec-4ec74717-d3de-491b-8d90-90d3fdbc2030.png`
- 原样归档路径：`/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_combat_down_sheet_20261011.png`
- 原始／归档 SHA-256 均为：`db2547046794b50902d9e6abe5c26f50c81f0673445eb9a80aa5dba53616d91b`
- 两处字节数均为 1,896,541。使用不覆盖字节复制，原始输出仍保留。

## 实际提交的完整 prompt

```text
Use case: stylized-concept
Asset type: transparent game character sprite-sheet candidate, eight FRONT/DOWN basic combat poses
Input images: Image 1 is the ONLY authority for the approved boy's face, identity, proportions, hair, outfit, colors and pixel-art style; use its FRONT figure. Image 2 is ONLY a reference for the eight action TYPES and the plain sword design, NOT a direction, camera, pose template, body proportions or face to copy. Do not copy Image 2's side-facing people. Neither original is an edit target.
Primary request: Generate one PORTRAIT sheet with exactly TWO equal-width columns and FOUR equal-height rows, eight full-body figures total, preferred canvas 1024 by 1536 pixels. Every one of the eight figures is the SAME approved boy facing FRONT, toward the viewer / screen DOWN. Show both eyes and both sides of his front-facing face in all poses; shoulders and pelvis stay frontal. No side views, no right-facing profiles, no back views.
Scene/backdrop: genuinely transparent RGBA cutouts, with NO floor, ground, cast/contact shadows, glow, aura, dust, swoosh, drawn grid, labels or numbers.
Layout: an invisible 2-column by 4-row grid, one figure wholly confined to each equal cell. Read each row left then right:
Row 1 LEFT: unarmed right-fist punch wind-up, right fist chambered at waist and left fist guarding; no sword.
Row 1 RIGHT: unarmed right-fist punch extended forward toward viewer / image DOWN, foreshortened right forearm and enlarged near fist; left fist guards; no sword.
Row 2 LEFT: straight-sword thrust preparation, right hand draws the sword handle back beside his own right waist (image LEFT), blade aimed forward/down toward viewer along its length, not swept sideways.
Row 2 RIGHT: thrust fully extended straight toward viewer / image DOWN, right hand pushed forward from image LEFT, blade strongly foreshortened with a visible complete point nearer the lower center. This must read as a forward stab, not a horizontal cut or a sideways sword pointing right.
Row 3 LEFT: horizontal sword-slash wind-up, right hand raised/chambered toward his own right side (image LEFT), visible complete blade pulled back to begin a lateral arc across the FRONT of the body.
Row 3 RIGHT: horizontal sword-slash end pose, same right hand has swept across the front of his body, visible full blade now extending laterally toward image RIGHT at chest/waist height. This is a lateral cut, visibly distinct from the foreshortened forward thrust above.
Row 4 LEFT: sword guard, right hand from image LEFT holds one complete sword upright/diagonal before the frontal chest; left hand may support the grip. Front face remains readable.
Row 4 RIGHT: standing hit/recoil, front-facing boy recoils backward slightly with eyes wincing, sword lowered in his anatomical RIGHT hand (image LEFT), left hip pouch still image RIGHT. No blood, wounds, torn clothing or collapsed defeat pose.
Handedness and pouch invariants: the boy's anatomical RIGHT hand begins on image LEFT and is the primary hand for every sword grip, punch and slash, even when that right arm crosses the body. The anatomical LEFT-hip brown document pouch is on image RIGHT in EVERY cell, its strap travels from anatomical right shoulder (image LEFT) to anatomical left hip (image RIGHT). Never switch hand or hip, never mirror. For equipment side, use Image 1's front/back convention rather than its inconsistent side figures.
Identity/style invariants: preserve Image 1's already approved youthful face and head-to-body ratio, short neck, black fringe/topknot with blue tie, warm skin, blue-gray cross-collar tunic, white collar/cuffs and waist ties, dark loose trousers, blue leg wraps, complete dark cloth shoes and single brown pouch. Do not redesign his face, grow him taller/older or change to a new art style. Match crisp stepped pixel outlines and restrained shading.
Sizing and framing: all eight bodies have the same scale and proportions. Body alone (topknot to shoe sole) occupies only 65 to 70 percent of each cell height, with a consistent shoe-sole baseline within each row and generous transparent weapon margin. Use the broad cell width for full swords. Every head, hand, shoe and ENTIRE sword including tip and pommel stays well inside its OWN cell with transparent padding; do not clip or cross any row/column border. Allow foreshortening for front punches and stabs rather than turning the boy sideways.
Text: none.
Avoid: right-facing profile copied from action reference, other directions, unequal layout, extra or missing figures, extra arms or weapons, inconsistent face/body proportions, sword in anatomical left hand, pouch on image LEFT, overlong sword crossing cell boundaries, blade hidden off-canvas, same pose reused for stab and slash, opaque or fake checkerboard background, halos, shadows, ground, effects, letters, numbers, watermarks.
```

## PNG 与布局只读核查

Pillow 仅读取像素进行统计，没有生成、裁切、处理或保存人物图片。

| 项目 | 实际值 |
| --- | --- |
| 原图尺寸／模式 | 1024 × 1536 / RGBA |
| 总像素 | 1,572,864 |
| alpha 范围 | 0–254 |
| alpha = 0 | 1,108,599 |
| 1 ≤ alpha ≤ 254 | 464,265 |
| alpha = 255 | 0 |
| 外沿最大 alpha | 1 |
| 外沿非零采样数 | 51 / 5120（四边各扫描一次，角重复） |
| 四角 alpha（左上、右上、左下、右下） | [0, 0, 1, 0] |
| 中间列界 x = 512 最大 alpha | 0 |
| 行界 y = 384 / 768 / 1152 最大 alpha | 253 / 253 / 253 |

实际 2×4 等格应为每格 512×384。按 alpha > 127 连通主体，只读计算得到八个主要完整人物轮廓；下表包围盒为全图坐标、左上包含右下排除，含随人物相连的武器，因此其高度不是单独 body 的精确高度。未把连通区域写成图片。

| 行／列／预期动作 | 主体包围盒 | 高度 / 格高 | 取等格时的问题 |
| --- | --- | --- | --- |
| 1左 拳蓄 | [145,13,400,406] | 393 / 384 = 102.34% | 鞋跨入第2行 |
| 1右 拳伸 | [621,14,874,415] | 401 / 384 = 104.43% | 鞋跨入第2行 |
| 2左 直刺蓄 | [142,398,420,777] | 379 / 384 = 98.70% | 鞋跨入第3行 |
| 2右 刺出 | [607,400,884,783] | 383 / 384 = 99.74% | 鞋跨入第3行 |
| 3左 横斩蓄 | [141,782,433,1150] | 368 / 384 = 95.83% | 自身在第3行内，但受相邻行跨界污染 |
| 3右 横斩末 | [581,788,986,1149] | 361 / 384 = 94.01% | 自身在第3行内，但受相邻行跨界污染 |
| 4左 护剑 | [154,1135,392,1521] | 386 / 384 = 100.52% | 束髻跨入第3行 |
| 4右 受击 | [618,1150,893,1521] | 371 / 384 = 96.61% | 束髻轻微跨入第3行 |

前两行没有武器高举，因此完整 body 明显接近／超过格高，不满足 65–70%；不是“由于武器计入而误判”。鞋底下缘在每行左右分别约为 406/415、777/783、1150/1149、1521/1521，前两行相差 9、6 像素，不是严格同一基线。

透明说明：PNG 存在真实 alpha，不能因为预览里可见灰色光晕便声称背景不透明。预览的灰色区域多处实际位于完全透明 RGB 中，例如 (100,200)=[25,24,26,0]、(160,200)=[61,59,63,0]、(400,200)=[55,51,52,0]。alpha 为 0 的隐藏 RGB 不应在正确 RGBA 合成中显现；本轮未以加工 PNG 的方式清除它。仍存在 alpha=1 的弱周边像素，如 (300,350)=[35,33,45,1]，外沿 51 个非零采样也均最多 1。此处只报告真实数据，未完成运行时合成／缩放的光晕验证，不声称像素级无残留。

## 逐动作实际目测审核

| 位置 | 审核 |
| --- | --- |
| 第1行左 拳蓄 | 正面，两眼可见；画面左的右拳收在腰附近，左拳护前；无剑，袋在画面右。 |
| 第1行右 拳伸 | 正面右拳朝观者伸出并放大，非侧向出拳；左拳护前，袋在画面右。 |
| 第2行左 直刺蓄 | 右手在画面左持剑；刀身较长、向画面右下横跨腹部，准备直刺的前向透视不够清楚，不能仅凭排序把它判为成功直刺蓄势。 |
| 第2行右 刺出 | 右手在画面左前伸，剑刃明显缩短透视、剑尖向画面下；与横向斩末势不同。 |
| 第3行左 横斩蓄 | 右手在画面左高举，整剑在头上横向蓄势；人物脸与身仍正面。 |
| 第3行右 横斩末 | 右手从画面左肩跨过身体，剑横向延伸画面右；剑尖完整且未越过中列/画布，但人物下方及上方格界受其他帧跨界影响。 |
| 第4行左 护剑 | 正面，右手从画面左握剑，左手辅助，剑在胸前朝上斜持，脸可读；不是右向站姿。 |
| 第4行右 受击 | 仍正面，身体倾斜、表情痛缩，右手在画面左低持剑；无血伤，不冒充倒地。 |

共同可见项：八人都朝观者／画面下，没有偷换为动作参考的右向侧面；棕色文袋均在画面右，剑主握手和出拳均符合解剖右手从画面左起始的约定。黑发束髻、蓝灰短衣、白领袖腰带、深裤与布鞋保持可识别身份，未设计新的脸或衣着。是否完全满足用户认可的脸比例仍由用户复审；不能把 identity prompt 当作事实验证。

完整原图上八人、双脚与剑尖可见，无文字数字、格线、地面、血伤或额外人物。宽列改善横斩剑尖的横向空间，但没有解决纵向人物过大和行界混入问题。不能通过扩张 region、缩小写回或掩盖邻帧来把失败 sheet 宣称通过。

## 正式资源保护

以下只读核查仍与任务前一致：

- `assets/source/characters/hero_pixel_source.gd`：`b9a67f25008e390b0fa281fa3566a2e29afb2010a185ac6e0b55001d29136a9b`
- `assets/runtime/characters/chr_protagonist_atlas.png`：`e13be6ae0ed90c069bcd195d396b3557b13ac8cfbea97fb95c9dd05f632c0358`
- `assets/runtime/characters/chr_protagonist_atlas.json`：`d600fddcbe1def27e727ef0ebaa41e39535018e0f4ac281a1a73a3dbf55d8146`

本次单调用已结束，停止于失败候选如实归档节点，没有提出已完成第五周或正式美术验收。
