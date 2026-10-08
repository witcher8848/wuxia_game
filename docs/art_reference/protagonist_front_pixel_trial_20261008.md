# 主角像素外观复核与单张生成试验

日期：2026-10-08。用户要求建立子agent review，指出脸太黑、与生成参考差距大；随后明确选择“内置图片生成，先试一张像素候选”。本次不替换运行时图集、不修改像素源／动画／碰撞，也不提交或推送Git。

## 子agent review

`hero_face_review`查看了原参考、1×／3×样本、探索实绘和图集，并核对源与导入；`hero_asset_review`查看参考、3×行走、直刺及管线／测试。两者均为只读review。

1. **P1：脸部色块和造型未达到参考方向。** 正面亮肤色面积少，近黑发际与轮廓过重。左右侧脸不是独立模板，而是在正脸上盖5×8深色矩形，右侧尤其窄暗。背面是后脑头发，不能把它也当作脸统一提亮。见[像素源](../../assets/source/characters/hero_pixel_source.gd)的93～102行。
2. **P1：轮廓也有差距，不能只换一个肤色。** 参考的宽松袖裤、布带层次、发束和眉眼，在当前代码绘制版本中被简化成细直肢体与方形衣块；侧身大量复用正面身体，转向不足。下一步应独立设计侧面，而不是继续盖深色块。
3. **不是已发现的统一渲染变暗。** 角色最近邻、32×48原尺寸显示；PNG无损、关闭mipmap，显示脚本没有额外脸部压暗逻辑。源色与截图可对应。现有证据指向源像素设计，不支持靠改过滤解决。
4. **P2：工程测试不是美术验收。** 逐帧比对同一源证明导出可复现，不证明好看；帧号变化不证明自然步态；全图不相同也不等于腿部动作正确。1×可读、参考气质、侧脸和动作连续性仍须图像复核与用户意见。

## 本轮试验与后续门槛

仅生成一张正面待机候选：保留同一身份、蓝灰短衣、束发、浅领口、文袋在角色自身左侧。扩大连续亮肤色色块，减少黑边，尝试统一粗像素网格。先保留32×48目标，不擅自升级分辨率或扩大制作预算。

生成输出不自动等于原生32×48资源。检查真实文件尺寸、透明度、网格和小尺寸可读性；若只有高清“像素风”而非一致逻辑网格，必须明确标为未通过生产规格，不能直接缩小后宣称已完成。此次用户只批准单张候选，不自动增加侧面、整套行走或接入工作。

若外观获得认可，建议再制作真正32×48可编辑正／侧样本，放到1×／2×／3×和游戏背景；然后扩为四向行走加一种攻击，验证同一人、脚底、文袋、持剑手与动作连续性。替换生产源时同步改导出契约，不能直接覆盖会被现有导出器重建的PNG，也不能删一致性测试掩盖来源冲突。

## 生成记录

工具：内置imagegen，未调用外部API、未配置或索取API密钥；具体生成模型版本未另核实。输入为[本项目已有四向参考](./protagonist_turnaround_week5.png)，角色身份／服装参考，不是可直接采样的像素网格。输出要求透明。

第一版[原样候选](./protagonist_front_pixel_trial_20261008.png)，来自本任务生成目录的`exec-1b188efa-1a1c-465a-b848-5ccc05d95c54.png`。SHA-256：`389a4f468f2e1234b433ee51d9cddc48dc3fe3d49b660bd4c90a426e9a9dada6`。脸和服装比现有程序像素图更接近参考，但不满足生产规格：实际1024×1536 RGBA，73191种RGBA取值，alpha范围0～254；按要求的32×32显示块检查，1536个逻辑格中没有一个完全均匀。此统计直接读取原文件，未缩放或修改图片。该结果不能称为原生32×48精灵。

因此仅针对网格和透明度做一次修订，不扩展角色数量、方向或动画。原始输出保留，游戏资产不变。

### 修订结果与结论

第二版[网格修订候选](./protagonist_front_pixel_trial_20261008_v2.png)，原始文件`exec-b2c1fd4f-35cc-4594-b251-ab832e2f78da.png`，SHA-256：`f0703586e8062a48549592d459fa56668fea382bd5fd2d3b4d2cc1e5ceaf7c14`。实际仍1024×1536 RGBA，57751种RGBA取值，alpha范围0～254，均匀32×32显示格仍0/1536。色块视觉上更大，但还不是严格32×48原生素材。

上述RGBA统计包含透明区，不能把取值总数当成肉眼可见颜色数；统一显示格检查是对本次明确要求的精确网格进行严格检查。结合实际观察到的不均匀色块、柔化边缘和亮晕，两版均未通过生产素材要求。未进行程序缩放、扣图、改色或将不合格结果接入运行时。

`hero_face_review`再次目视两版和旧样本：明亮连续肤色、眼与发分离、蓝灰衣物和宽松袖裤均有改善；首版更保留少年侠客感。二版大眼、鼻口消失、方圆脸和大头发块更幼态，不建议作为最终人物气质。

**建议：保留首版人物气质与亮脸方向，吸收第二版的大块明暗和衣物分区；不要保留娃娃脸或光晕。** 内置生成可以用于外观候选，但本轮两次实际输出都不能证明能直接交付精确可用的像素精灵。下一步若用户认可方向，应单独授权低分辨率像素源制作／修整与实机验证，之后再扩四向和动画。不能靠继续生成漂亮大图来宣称该生产步骤已完成。

本次完成的是两名子agent的review，以及用户批准的一张正面候选的生成与一次针对性修订。没有修改第五周游戏代码／测试／资产、没有发布／推送、没有额外外部API服务；人设和生产替换仍待用户决定。

## 参考《逸剑风云决》的定向修订建议（2026-10-08）

用户反馈第一版方向可以，但希望参考《逸剑风云决》继续提高。本节先把参考观察转成项目自己的美术要求，不复制该作的角色、服装或具体像素图。

Steam官方商店页将其描述为“像素武侠RPG”，并明确其视觉方法是把传统像素画面置入3D场景融合呈现，同时强调现代化视觉效果。由此可学的不是给角色叠发光、模糊或写实小纹理，而是**角色像素造型自身足够清楚，同时能在有纵深、较丰富的场景中被一眼读出来**。这是基于官方页面描述作出的美术方向推断；该页不是角色逐像素制作规范。[Steam官方商店页](https://store.steampowered.com/app/1876890/%E9%80%B8%E5%89%91%E9%A3%8E%E4%BA%91%E5%86%B3/?l=schinese)

### 本项目候选需要改进的地方

1. **脸先读得出来，再谈精致。** 沿用首版明亮、温和的少年气质；缩小大眼感，明确眉、眼、鼻口的少量像素关系。避免黑发际线把脸压成面具，也避免高光亮晕。
2. **剪影承载身份。** 强化束发与头顶发结、短交领、较宽袖口、松裤和角色自身左侧文袋的外轮廓；在缩到32×48的构图时，仍应能辨认“年轻文书之子/初入江湖”，而不是泛化的黑发蓝衣小人。
3. **用成组色阶表现布料，不用软光。** 蓝灰衣服至少有主色、受光面、折叠阴影三个互相区分的大色块；领口、袖口和腰带形成稳定的浅/暖色节奏。背景可以后续有纵深，但这一张正面立绘必须保持透明底、硬边、无光晕。
4. **成熟感来自比例与克制。** 保持约四头身、肩宽略增、眼睛缩小、下颌不做圆娃娃脸；姿态放松而有戒备，像故事刚开始的普通少年，不要直接画成威风成熟的大侠。
5. **保持项目辨识度。** 蓝灰短衣、浅色交领、布腰带、左侧文袋，以及“身份文书/名册”主题应留下来。《逸剑风云决》的像素与现代场景融合是参考方法，本项目仍是2D像素角色，且主角的文袋与书吏家庭出身是自己的识别点。

### 下一张图的修订指令草案

以首版为身份／服装底稿，保留单张正面全身、透明背景、人物比例与现有核心配色。表情从“可爱大眼”收敛为清醒、略紧张但有韧劲的少年；减小眼睛和脸部黑边，增加眉眼层次和一两处克制的面部像素。拉开头发与脸的明度对比。扩大肩、袖、裤的轮廓层次，保留文袋并使其在小尺寸仍可辨认。衣物以少数硬边像素色块呈现布料受光与褶皱；禁止渐变、柔焦、Bloom、半透明边缘和装饰性噪点。目标仍是严谨32×48逻辑网格，不把高清像素风图误报为游戏素材。

**执行状态更新：** 上一轮曾因内置工具入口缺失停在文字方案；本轮入口恢复，已使用内置imagegen生成造型修订版v3和一次边缘清理试验，结果见下文。没有改用CLI/API备用路线。

### 官方实机画面核对与实际修订结果

实际查看了Steam官方页面的实机预览，以及[钓鱼场景截图](https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/1876890/ss_6da139b1ffa32da20d30f87dcd142a6c1b6ffe25.1920x1080.jpg?t=1774667199)。页面通过浏览器直接观看，没有下载、复制或将第三方图像输入生成工具。

目视可借鉴的点是：场景内的小人物靠少量集中的眉眼色块、发束剪影、衣物明暗和衣领／腰部的层次维持辨识度；界面中的人物头像承载更细的五官信息。这里没有测量其精灵原始像素尺寸，也不把本项目四头身或32×48规格称为该作的制作规范。

本项目将这些观察转为“**暖肤色、克制眉眼、稍带戒备的少年神情、蓝灰交领短布衣、宽袖松裤、腰带与文袋、成组布料色阶和硬边像素轮廓**”的生成描述。保持首版的服装身份，通过缩小眼睛、加强眉线与下颌、细化发束和服装分区来提高少年侠客感；不新增兵器或成熟大侠装备。

本轮以外观候选为交付范围：提示词明确其为放大像素参考，优先人物气质、剪影与服装，保留未来32×48制作目标；不再把生成的高清候选要求或宣称成精确可用的生产图集。

| 版本 | 结果与用途 | 原始文件与SHA-256 |
|---|---|---|
| [v3造型修订版](./protagonist_front_pixel_trial_20261008_v3.png) | 选为本轮主要外观候选；眉眼更克制、下颌更明确，发束、衣襟、袖口和裤腿更有层次。暖肤色、蓝灰服装、角色左侧文袋、单张正面全身均保留；等待用户外观评审 | `exec-dc63186d-6a45-445d-97b9-0f11b17bf1c5.png`；`d84f538b80f492258812c94211afa8dce64bcb08561099e8b84fa1dc11d961d9` |
| [v3边缘清理试验](./protagonist_front_pixel_trial_20261008_v3_edge_trial.png) | 只针对亮晕与透明边缘修订。黑边变硬、部分边缘更清楚，但蓝灰／橙色亮晕仍可见，没有实现完全清理；不选为主要造型候选 | `exec-a4e78fd8-44aa-44ee-a785-a1f64f168039.png`；`24c08d3a69f003e10d7bde5006422acebb1d60a0117279d09add4c2277e1c9a1` |

两份原始文件均位于本任务的`/Users/witcher/.codex/generated_images/01a08145-47dc-7242-a49b-7d4016caecda/`，仓库副本经`cmp`确认相同。两份实际均为1024×1536 RGBA、alpha范围0～254：v3有1,028,175个alpha=0像素、532,130个alpha=1～253像素及12,559个alpha=254像素；清理试验对应1,032,955、467,836及72,073个像素，两者均无alpha=255像素。结合目视亮晕，不能称为二值透明生产素材。没有执行程序改图、缩放或扣图。首版哈希仍为`389a4f468f2e1234b433ee51d9cddc48dc3fe3d49b660bd4c90a426e9a9dada6`，原图未覆盖。

**验收范围：** 已完成参考画面核对、描述调整、同一主角外观修改、目视复核与原始图片／提示词归档。用户已初步肯定首版方向，尚未评审v3；本轮候选完成不代表正式人设、精确网格、动画或实机替换获批。游戏源、运行时图集和导出预设未修改。

### v3造型修订：完整实际提示词

```text
Use case: style-transfer.
Asset type: a single front-view pixel wuxia RPG protagonist visual candidate for review.
Input image 1: edit target, our approved first protagonist candidate. Preserve his identity, clothing scheme, document pouch, front view and full-body framing. Improve the actual character design and pixel rendering.

Primary request: redraw this same young Chinese male clerk's son as a more appealing, distinctive classic pixel wuxia RPG hero, informed by the compact expressive sprite design and clear garment layers seen in Wandering Sword (逸剑风云决). Keep our original character and costume. Aim for an earnest 18-to-20-year-old at the beginning of his adventure: observant, slightly wary, resilient and approachable.

Specific improvements:
1. The current enormous shiny eyes and round toy-like face need refinement. Reduce eye size by about one third, use narrow dark eye clusters and short decisive eyebrows, keep a small understated nose and mouth. Give the chin a slightly firmer shape. Keep a broad warm peach face area, with shadows only at hairline, under the jaw and one cheek edge. Hair must not engulf the face.
2. Refine the black tied-up hair into clear, slightly asymmetric clumps, a small topknot and a modest tan tie. A few well-placed blue-grey highlight clusters should describe hair volume. Remove the uniform heavy black ring around the whole face.
3. Give shoulders, roomy sleeves and loose trouser legs more convincing shape. Add a clear overlap to the cross-collar, layered cuff folds, a neatly tied tan belt, and a slightly irregular short tunic hem. Show cloth folds through three organized flat color values, with clean large pixel clusters. Keep the small brown document pouch on his anatomical LEFT, viewer RIGHT, clearly distinguishable from the trouser.
4. Maintain approximately four-head-tall stylized RPG proportions and a compact readable silhouette. Relax his hands near the hips, slightly separate elbows from torso, feet planted naturally. Convey readiness through posture without a combat pose.

Palette and costume invariants: slate-blue / blue-grey short cross-collar cloth tunic, pale cream collar and cuffs, charcoal loose trousers, simple dark cloth shoes, tan cloth belt, brown document pouch, black topknot. No weapons, armor, scarf, cape, new ornaments, symbols or text. Preserve a humble civilian beginning.

Rendering: enlarged low-resolution pixel sprite reference, coarse consistent square pixels, crisp stepped hard edges and grouped flat colors, restrained 16-to-24-color appearance. Design large shapes with eventual 32x48 game-sprite readability in mind. Avoid dense high-resolution anime detailing, smooth gradients, anti-aliasing, bloom, glow, airbrush, photographic texture or soft shadows. This output is a visual candidate rather than a production atlas; prioritize face, silhouette and attractive coherent pixel shapes.

Composition: ONE centered orthographic front-facing full-body character, entire topknot and soles visible, comfortable transparent margins, completely transparent background. No ground shadow, scenery, comparison panels, extra views, writing, borders or watermark.
```

### v3边缘清理试验：完整实际提示词

```text
Use case: background-extraction.
Input image 1: edit target, the improved young pixel wuxia RPG protagonist.
Primary request: remove the diffuse blue-grey and orange glow surrounding this character and return a clean transparent cutout.
Preserve the character's face, smaller eyes, strong eyebrows, hair clusters, topknot, tan hair tie, blue-grey crossed-collar short tunic, cream collar and rolled cuffs, tan belt, brown pouch on viewer-right, dark loose trousers, shoes, proportions, front-facing pose and entire full-body framing.
The previous image has a large hazy luminous cloud around the hands, head, body and feet. Erase that entire halo. Immediately outside the hard stepped pixel silhouette must be completely transparent. No residual lighting spill or soft ground shadow. Preserve only the opaque character silhouette, crisp pixel-shaped edge steps and interior flat-color clusters. Remove soft antialiasing at the outer edge.
Use fully opaque pixels for the character and fully transparent background pixels. Preserve facial expression and garment shapes; do not add props, scenery, words, shadows, panels, watermarks or extra views. One character only.
```

### 首次生成：完整提示词

```text
Use case: style-transfer.
Input image 1 is the existing original wuxia protagonist identity/costume reference, NOT a pixel-grid template. Transform this four-view reference into ONE front-facing full-body idle game sprite candidate of the SAME young male clerk's son. Do not show four views.
Asset goal: genuinely low-resolution pixel sprite, NOT a detailed pixel-styled illustration. Work as if authoring on an exact 32 columns by 48 rows transparent logical canvas; show this enlarged with identical square pixels and hard nearest-neighbor edges. Prefer a 1024 by 1536 output with each logical pixel a uniform 32 by 32 solid-color square. No subpixel details, no partial tiles, no uneven pixel scales, no antialiasing, gradients, dithering, bloom, texture or tiny decorative pixels.
Keep the entire body including topknot and soles inside the canvas, feet anchored at logical (16,44), sole baseline row 43, about 40 logical pixels tall. Centered orthographic front view, modest four-head-tall RPG proportions, relaxed neutral arms connected naturally to the torso, hands separated from the belt, two feet clearly readable. Transparent background with no ground or cast shadow.
Preserve black topknot with a tan tie, dark muted blue-grey short cross-collar tunic, cream crossing collar and rolled cuffs, tan cloth belt, dark loose trousers, cloth shoes, small brown document pouch on the character's anatomical LEFT (viewer's RIGHT). No weapons, armor, new emblems, scarves or new character features.
Critical face correction: bright clean warm-peach face with one broad connected light-skin cluster. Keep peach across forehead and cheeks. Small warm midtone/shadow only at the hairline and jaw edges. No near-black ring around the entire face, no dark mask or muddy brown cheeks, no hair covering half the face. Two very small readable dark eyes, restrained brows, a single small warm mouth mark; simplify rather than attempting high-resolution anime features.
Use a small discrete palette of approximately 12-16 flat colors: hair charcoal/navy, clothes desaturated slate-blue, trousers charcoal, belt/pouch warm brown. Skin is deliberately lighter than the previous runtime sprite: cream-peach #F4C69F highlight, warm peach #E2AA78 base, #BF7857 limited edge shadow. All colors are provisional candidate choices, not a claim of adherence to a production palette.
Priorities: 1) readable attractive face at actual small sprite scale, 2) same costume silhouette as the reference with slightly loose sleeves/trousers, 3) strict coarse shared pixel grid, 4) stable feet anchor. No text, labels, grid lines, portrait inset, comparison panel, scenery, watermark or border. One sprite only. This is a candidate for review, not an automatically accepted production atlas.
```

### 网格与透明度修订：完整提示词

```text
Edit the supplied candidate. Keep the same single front-facing young wuxia protagonist, bright peach face, black topknot, blue-grey short tunic, cream collar/cuffs, tan belt and document pouch on viewer-right, loose dark trousers and cloth shoes.
Change ONLY the rendering resolution and transparency discipline: redraw it as a genuinely tiny 32x48 logical-pixel videogame sprite, displayed at exactly 32x nearest-neighbor magnification on a 1024x1536 transparent canvas. Each logical pixel must be one completely uniform 32x32 square, all square boundaries aligned to multiples of 32 from the top-left. This means at most 32 blocks across the entire image and 48 blocks vertically. The previous output had far too many small pixels and was a high-resolution pixel-style illustration; simplify drastically.
Place soles at logical row 43, horizontal foot anchor at column16. Topknot near row4. Whole sprite about24 logical pixels wide and40 tall. Head approximately10 logical pixels wide and10 tall. Face is a connected bright peach area about7 pixels wide and6 high; eyes are just one or two dark logical pixels each, optional one cream pixel, no detailed anime rendering. Torso about14 pixels wide, short sleeves and loose trousers expressed by large simple blocks, hands about2x3 pixels. Preserve charm using silhouette and large color clusters, NOT high-resolution detail.
Use no more than16 flat colors. Light warm skin stays dominant: #F4C69F and #E2AA78 with sparse #BF7857 jaw shadow. Charcoal hair with one lighter blue-grey hair highlight. Muted slate-blue cloth, cream trim, brown belt/pouch. No black facial mask or thick black ring around the cheeks.
All filled pixels fully opaque; all surrounding background fully transparent. Remove ALL glow, blur, semi-transparent pixels, shading gradients, airbrush, noise and texture. Pixel edges must be stepped hard squares. No lighting halo, no ground shadow, no text, no ruler, no grid lines, no extra views. Do not preserve fine details that cannot fit the32x48 grid. One candidate only, not an animation sheet.
```
