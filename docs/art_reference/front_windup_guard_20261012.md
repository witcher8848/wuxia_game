# 正面斩蓄势／护剑 imagegen 补充候选（2026-10-12）

## 状态与范围

一次内置 `image_gen` 调用，无迭代、无重试。实际产物恰好两个人物同一水平行，左为正面举剑斩蓄势，右为正面胸前护剑。目测两个动作、正面朝向、持剑手与文袋侧别成立；可供主代理进一步选择独立原图 region 与接入审核，**不等于已完成 runtime 或完整第五周验收**。

本次任务用于补充旧正面 2×4 sheet 中取矩形会混入相邻行的斩蓄势与护剑。新产物不是重新制作人物脸，也不是新整套八动作。主代理允许合理非等分 region，因此不能只因左剑尖稍过严格中线就宣称不可用；也不能据此忽略实际人物间距与完整剑脚检查。

完整读取 imagegen SKILL.md、prompting.md 与 sample-prompts.md；实际查看两个输入与归档输出。skill 影响本轮采用角色身份参考、真实透明设置与非破坏原样保存，未自动执行其通用迭代步骤，因为本轮明确只授权一次调用。

## 输入、设置与原始来源

输入顺序与角色：

1. 已认可人物身份、正面脸、比例、衣服与像素风格：
   - `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_turnaround_20261011_v3.png`
   - SHA-256：`fdb71157e5dae68a1badfa3103a8ded1805742a6ed45e2db76e8d30bb0b5c67f`
   - 字节数 1,124,087。
2. 仅正面斩蓄势、护剑动作与剑设计参考，不复用八人／多行布局：
   - `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_combat_down_sheet_20261011.png`
   - SHA-256：`db2547046794b50902d9e6abe5c26f50c81f0673445eb9a80aa5dba53616d91b`
   - 字节数 1,896,541。

内置工具参数 `transparent_background=true`，`referenced_image_paths` 仅为上述两个完整原图。1536×1024 宽画布是实际 prompt 中的偏好请求，不是虚构的内置工具尺寸参数。

- 原始生成路径：`/Users/witcher/.codex/generated_images/01a12b2d-02c3-7b11-b2b2-6107ce8c028f/exec-ef0ce748-a46d-4466-87ef-83be4aa66773.png`
- 项目原样复制路径：`/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/hero_front_windup_guard_20261012.png`
- 原始／归档 SHA-256 均为：`8ba02b3c7d82e2a51b6e887cdcee05d2eded0a257faeeb71ac3a14d78987db6c`
- 原始／归档字节数均为 1,510,631；原始输出仍保留。
- 不覆盖既有文件的字节复制。未裁图、缩放写回、去除 alpha、修补、重绘、镜像、加地面、加光晕或导出新人物 PNG。

## 实际提交完整 prompt

```text
Use case: stylized-concept
Asset type: two transparent full-body front-facing game-character combat poses
Input images: Image 1 (four-view turnaround v3) is the authority for the approved boy's identity, FRONT face, hair, proportions, outfit, colors and pixel-art style. Image 2 (front combat sheet) only supplies the slash wind-up and sword-guard action ideas and plain sword design; do not reproduce its eight-figure or multi-row layout. Neither source image is to be modified.
Primary request: One WIDE LANDSCAPE image, preferred 1536 x 1024 pixels, containing exactly TWO complete figures SIDE BY SIDE IN ONE HORIZONTAL ROW. Left figure is a frontal sword-slash WIND-UP; right figure is a frontal sword GUARD. Do not put them in two rows, do not add other poses.
Scene/backdrop: actual transparent RGBA background. No ground, floor, drop/contact shadow, glow, halo, aura, label, number, grid, watermark or effect.
Identity invariants: Both are the exact same approved youthful wuxia boy, not a new face design. Preserve the reference front face shape and head/body ratio, short neck, black fringe and topknot with blue tie, warm skin, blue-gray cross-collar tunic, white collar/cuffs and waist ties, dark loose trousers, blue leg wraps, both complete dark cloth shoes and one brown document pouch. Keep the crisp stepped pixel illustration and restrained colors. Do not make him taller, older or more chibi.
Direction and equipment invariants: BOTH figures face directly toward the viewer / screen DOWN, both eyes visible, face, chest and pelvis frontal, never side-facing. Anatomical RIGHT arm starts on image LEFT of EACH body; this right hand is the main sword-grip hand in BOTH poses. Anatomical LEFT-hip document pouch stays on image RIGHT of EACH body, its strap from anatomical right shoulder to anatomical left hip. No mirroring or swapping hand/hip.
LEFT pose: right arm from image LEFT raised above his own right shoulder, right hand grips a plain sword ready for a lateral slash, complete blade drawn across the space above his head with its tip fully visible. Left fist guards in front. This is the raised-sword preparation, not the completed cut.
RIGHT pose: right arm from image LEFT holds the sword in front of his chest in an upright or upward diagonal guard, complete blade and tip visible; left hand may support below the right-hand grip. Front face remains clear and unobstructed.
Framing: Use equal body scale, same proportions and approximately the same shoe-sole baseline. Each body's topknot-to-shoe height is only 70–80% of the canvas height; do NOT enlarge the bodies to fill the canvas. Allow extra headroom for the raised sword. Keep each entire figure AND entire sword inside its own half, with broad transparent margins and a generous clear transparent central gap. No limbs or sword tips overlap, cross the gap, touch the canvas or clip. Full head, both hands, both legs and both shoe tips visible.
Text: none.
Avoid: two-row layout, eight figures, extra poses, new faces, side profiles, left-hand sword, pouch on image LEFT, cropped or intersecting swords, missing toes, oversized figures, opaque/checkerboard background, glow, shadows, ground, text or labels.
```

## PNG 只读统计

仅读取尺寸、像素 alpha、哈希与连通轮廓；未写回图片。

| 项目 | 实际结果 |
| --- | --- |
| 尺寸／模式 | 1536 × 1024 / RGBA |
| 总像素 | 1,572,864 |
| alpha 范围 | 0–254 |
| alpha = 0 | 1,122,086 |
| 1 ≤ alpha ≤ 254 | 450,778 |
| alpha = 255 | 0 |
| 四条画布边最大 alpha | 1 |
| 四边非零采样 | 7 / 5120（角重复） |
| 左主要连通主体 alpha > 127 bbox | [157,129,773,946] |
| 右主要连通主体 alpha > 127 bbox | [876,174,1414,946] |
| 两主体之间的净横向间距 | 103 像素 |
| 两主体 alpha > 127 下缘 | 都为 946（排除） |

包围盒为全图坐标，左上包含、右下排除。左 bbox 含高举武器，高 817 像素，即画布高 79.79%；右含上斜剑高 772，即 75.39%。目测两人束髻顶部约 y≈200，完整 body 高约 746，约 73% 画布高，未把人物撑满画布；仅属于语义位置目测近似，不把整个武器 bbox 冒称精确 body 高度。

严格中线为 x=768，左主体最右排除坐标为 773，剑尖核心略越中线约 5 像素；与右人物 bbox 左缘 876 之间仍有 103 像素净间距。原图实际没有交叉或裁掉剑尖，两人同一鞋底核心下缘；具体显示 region 留由主代理最终决定，未在本轮生成裁图或正式 JSON。

弱非零 alpha 也存在：左右半幅 alpha>0 bbox 分别为 [0,21,768,970] 与 [768,27,1516,1006]，远大于主体轮廓，不能声称每个周边像素都为零。保留原图全部 alpha，不清理噪声。

预览可见灰色背景光晕，但已核查多处这些背景实际为 alpha=0 的隐藏 RGB，例如 (790,250)=[36,35,37,0]、(1400,500)=[8,8,9,0]、(100,950)=[18,17,18,0]；正确 RGBA 合成不应显示完全透明的 RGB。此处不能据预览直接声称工具生成了不透明地面／投影，也不声称已经做了正式游戏缩放合成无光晕验证。

## 实际目测审核

- **数量／布局**：恰好两人，一左一右同一水平行；没有两行、八人或其他姿态副本。
- **正面**：两人两眼都可见，脸、胸前交领与骨盆朝向观者／画面下，没有用右向侧面替代。
- **左斩蓄势**：从自身画面左肩起始的右臂高举，右手握完整剑柄、护手，完整剑刃在头上向画面右展开；另一拳在胸前保护。可读为准备横斩，而非已出剑末势。
- **右护剑**：从自身画面左肩起始的右臂跨胸上握剑柄，画面右的左臂辅助下握；剑在胸前上斜，剑尖完整、未挡住两眼。
- **文袋**：两个棕色文袋均在各自画面右的解剖左髋，肩带从画面左肩连至画面右髋。没有镜像换边。
- **身份**：黑发刘海束髻与蓝带、暖肤少年脸、蓝灰交领衣、白领袖腰带、深色宽裤绑腿和布鞋保持可识别参考身份。目测脸与比例延续，不将 prompt 的“exact same”当作逐像素等同证据。
- **完整性**：两人双手、双腿、两只鞋及鞋尖可见，两把剑柄、护手与剑尖完整；画布边没有裁头脚。没有人物／剑交叉，也没有相邻行人物混入。
- **避免项**：没有文字、数字、格线、额外人物、地面或可辨认投影；真实 alpha 存在，但弱周边残留与正式运行时合成仍按数据／后续审核记录。

## 变更边界

本次仅新增 `hero_front_windup_guard_20261012.png` 与本记录。没有修改 renderer、正式资源、主登记、人物原图、物理或战斗规则，未提交、未打包。已按单调用上限结束。

