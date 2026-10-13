# 第三方素材与依赖来源登记

> 建立：2026-09-13；更新：2026-10-12。记录实际状态；“已选型”不等于“文件已引入”或“可发布”。

每个外部代码依赖、字体、图片、音效、音乐或参考图都要有来源。正式素材引入时补全固定版本／原下载链接、原始许可证路径、必要凭证、文件路径和修改说明。生成内容另见 [AI 内容登记](./ai_content_register.md)。

| ID | 名称／作者 | 来源与许可证 | 用途 | 文件／版本与引入状态 | 修改与发布要求 |
|---|---|---|---|---|---|
| HERO-IMAGEGEN-W5-20261012 | 新主角四向／基础动作测试资产／imagegen | 本项目生成身份和姿态图；本批9次内置调用，无第三方图像；AI-ART-035 | 常规探索、战斗和角色样本的共享新默认测试角色 | 15份原PNG逐字节复制至 `assets/runtime/characters/imagegen_20261012/`，schema2／57逻辑槽；原始prompt／哈希／失败候选见[生产记录](./art_reference/hero_imagegen_production_20261012.md)和AI登记 | 已接入本地测试，不是正式发行美术；仅GPU区域／等比显示／元数据锚点，不程序加工PNG；旧源保留，人设最终认可与发行审核分离 |
| REF-AI-HERO-COMBAT4-20261012 | 四向基础战斗补缺／朝右重排与背景试验／imagegen | 本项目生成参考；5次内置调用，无第三方图片；AI-ART-034 | 独立战斗姿态、真实alpha合成评审 | 五张原样PNG／prompt字段／哈希与两张Godot截图见[主记录](./art_reference/protagonist_imagegen_week5_motion_20261011.md)及各子记录 | 实际合成证实alpha0隐藏RGB不显色；等格和部分动作仍不通过，不程序改图、不激活／入包，新生产规格待人工选择 |
| REF-AI-HERO-MOTION-20261011 | 主角并行动作／配件纠错候选／imagegen | 本项目生成图；7次内置调用，无第三方图片；AI-ART-033 | 纵向／左向行走、朝右战斗、倒地及侧别候选 | 七张原样PNG、完整提示／哈希见[主记录](./art_reference/protagonist_imagegen_week5_motion_20261011.md)及其子记录；另有两张Godot尺寸截图 | 步相和战斗跨格未通过；倒地单帧仅候选；旧侧别更正为左近右远，不程序加工人物、不入包／商店，新显示合同待用户确认 |
| REF-AI-HERO-WALK-LEFT-20261011 | 主角朝左行走条带候选／imagegen | 本项目四向v2；内置生成，无第三方图片；AI-ART-032 | 补动作的独立候选 | [原图／完整提示词／哈希](./art_reference/protagonist_imagegen_week5_motion_20261011.md)，原样1774×887 PNG | 身份基本保持，但腿相可能重复、手臂摆动不足；未判完整循环，不程序改图、不替换运行时，规格另待确认 |
| REF-AI-HERO-WALK-BAGFIX-20261011 | 主角phase3文袋形状修订／imagegen | 本项目armfix与旧pose3；内置编辑，无第三方图片；AI-ART-031 | 隔离袋形／动作一致性评审 | 一张原样PNG和新10张Godot截图，见[完整记录](./art_reference/protagonist_imagegen_walk_bagfix_review_20261011.md) | 袋更长、近臂保留，但袋外RGB重渲染；不冒称仅袋像素编辑或动态通过，旧候选保留、运行时不变，不入包／商店 |
| REF-AI-HERO-WALK-ARMFIX-20261011 | 主角phase3手臂修订／失败清边试验／imagegen | 本项目生成图；内置编辑，无第三方图片；AI-ART-030 | 隔离外观／四帧连续观感评审 | 两张原样PNG、新10张Godot截图及实际AVI／MP4来源见[完整记录](./art_reference/protagonist_imagegen_walk_armfix_review_20261011.md) | 近臂改善、文袋有漂移，清边失败未采用；未程序改人物图、未替换运行时，尺寸／自然度／生产边缘未验收，不入包／商店 |
| REF-AI-HERO-WALK-SINGLE-20261010 | 主角单帧姿态诊断／原色四关键帧／imagegen | 本项目生成图与仅线圆绘制的Godot骨架；内置生成／编辑，无第三方图片；AI-ART-029 | 隔离单帧动作／真实尺寸评审 | 十张原样PNG逐张列于[完整提示词／原始文件／哈希／检查](./art_reference/protagonist_imagegen_walk_single_progress_20261010.md)，显示证据在`hero_imagegen_walk_20261010/single_frames/` | 不手工／程序修人物位图，48×72仅显示框；循环自然度、phase3手臂和生产透明／网格未验收，不入运行时／包／商店 |
| REF-AI-HERO-WALK-20261010 | 主角行走条带／单帧姿态试验／imagegen | 本项目四向图及生成试验图；内置生成／编辑，最后增加本项目Godot骨架姿态输入，无第三方图像；AI-ART-028 | 隔离动作可控性试验 | `docs/art_reference/protagonist_imagegen_walk_right*20261010*.png`及`hero_imagegen_walk_20261010/`；[完整提示词／哈希／真实渲染与失败记录](./art_reference/protagonist_imagegen_walk_trial_20261010.md) | 原图不做程序编辑；四帧循环尚未通过，48×72仅临时显示框，不是批准的生产规格，不入运行时／包／商店 |
| REF-AI-HERO-PROGRESS-20261010 | 主角细节收敛／四向静态参考／imagegen | 本项目AI-ART-026首图及本轮生成图依次作为唯一图像输入；内置编辑与扩展，无第三方图片；AI-ART-027 | 内部四向外观与显示尺寸评审 | `docs/art_reference/protagonist_imagegen_candidate_20261010_v2.png`及`protagonist_imagegen_turnaround_20261010*.png`；[三次完整提示词／哈希／检查](./art_reference/protagonist_imagegen_progress_20261010.md) | 用户认可首图方向，新四向待评；原样复制，未生产像素化／动画化，不入运行时／包／商店 |
| REF-AI-HERO-20261010 | 主角重新生成的像素风外观候选／imagegen | 本项目文字人设；内置 imagegen 新图，无图像输入；观看《逸剑风云决》官方实机作为描述参考，用户百度图因403未见；AI-ART-026 | 内部外观评审 | `docs/art_reference/protagonist_imagegen_candidate_20261010.png`，原样复制；[完整提示词／来源／检查](./art_reference/protagonist_imagegen_candidate_20261010.md) | 用户认可长相与少年气质更接近；1024×1536，存在部分透明与光晕，不是原生32×48或动画图集，不入包／商店 |
| HERO-SIMPLE-20261009 | 主角短颈／去褐边／大色块简化候选／Codex辅助像素源 | 本项目A眼形和独立整数像素源；观看《金／银》官方实机，仅参考方法，无外部像素输入；AI-ART-025 | 内部静态造型评审 | `assets/source/characters/hero_simple_candidate_20261009.gd`与`docs/art_reference/hero_simple_review_20261009/`；[参考／过程／哈希](./hero_simple_candidate_review_20261009.md) | 原生32×48、6色、两轮剪影；用户选择A眼形，新整体外观待评，不入atlas／包／商店 |
| HERO-FACE-20261009 | 主角五官专项静态修订／Codex辅助像素源 | 本项目旧静态候选的面部源码修订，无外部像素输入；AI-ART-024 | 内部五官评审 | `assets/source/characters/hero_face_candidate_20261009.gd`与`docs/art_reference/hero_face_review_20261009/`；[修改／检查记录](./hero_face_candidate_review_20261009.md) | 仅改面部，身体／头发保留；后续用户选择A眼形，原整体未获认可，不接入atlas／包／商店 |
| HERO-STATIC-20261009 | 主角正面／左侧静态候选／Codex辅助像素源 | 本项目独立整数像素源与既有色板，无外部像素输入；AI-ART-023 | 内部造型评审 | `assets/source/characters/hero_static_candidate_20261009.gd`与`docs/art_reference/hero_static_20261009/`；[来源／哈希／检查](./hero_static_candidate_review_20261009.md) | 原生32×48，不采样或缩小其他图像；用户尚未认可，不接入atlas、不入包或商店 |
| REF-AI-HERO-FACE-20261008 | 同一主角的正面像素候选及修订／imagegen | 本项目四向参考与首版候选；内置生成与编辑。另观看《逸剑风云决》Steam官方实机作为描述参考，无第三方图像输入；[完整记录](./art_reference/protagonist_front_pixel_trial_20261008.md) | 内部外观试验 | `docs/art_reference/protagonist_front_pixel_trial_20261008.png`、`_v2.png`、`_v3.png`及`_v3_edge_trial.png`，均原样复制，AI-ART-022 | 用户初步肯定首版方向，v3为新主要候选待评；精确像素网格／透明度仍未满足生产规格，不入包、不替换当前角色 |
| REF-AI-HERO-W5 | 主角四向比例参考／imagegen | 本项目文字规范，内置生成＋一次编辑，无外部图像；详见[记录](./art_reference/protagonist_week5_prompt.md) | 内部参考 | `docs/art_reference/protagonist_turnaround_week5.png`，未进包 | 原样复制；不声称获用户认可或可直接作生产精灵 |
| HERO-PIXEL-W5 | 主角测试图集／Codex辅助代码源 | 本项目独立整数像素源，无第三方像素输入；AI-ART-021 | 内部候选探索／战斗 | `assets/source/characters/hero_pixel_source.gd` → `assets/runtime/characters/chr_protagonist_atlas.png`及JSON；2026-10-08按脸部反馈重做四向轮廓与步态，PNG哈希`e13be6ae0ed90c069bcd195d396b3557b13ac8cfbea97fb95c9dd05f632c0358` | 工程验证与正式美术／发行审核分离，未缩放或采样生成参考；用户新版外观评审待完成 |
| DEP-GODOT | Godot Engine／Godot contributors | [官方许可说明](https://godotengine.org/license/)，MIT；引擎附带组件分别保留原许可 | 编辑器、运行时、导出模板 | 已安装 `4.7.2.stable.official.ed1daf0bf`，2026-09-14 命令行复核；官方编辑器包、模板包与 SHA-512 清单在 `.tools/downloads/`；许可原文 [GODOT.txt](../licenses/GODOT.txt) | 未修改引擎源码；发布包保留 Godot 及所用第三方组件声明；模板与 Debug／Release 实际导出已验证；第三方组件完整声明另存 [GODOT-COPYRIGHT.txt](../licenses/GODOT-COPYRIGHT.txt) 并随包分发 |
| FONT-NOTO-CJK-SC | Noto Sans CJK SC Regular／Noto 项目 | [上游字体文件](https://github.com/notofonts/noto-cjk/blob/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf)、[上游许可证](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE)，SIL OFL 1.1 | 中文 UI | 已取得 [Regular 字体](../assets/runtime/fonts/NotoSansCJKsc-Regular.otf)；许可原文 [NOTO-OFL.txt](../licenses/NOTO-OFL.txt)。当前二进制由下表 SHA-256 固定；上游提交／字体内部版本未单独记录。Medium／Bold 尚未引入 | 未修改／未子集化；已绑定 main.gd 的 UI Theme；Mac 图形截图和菜单操作验证当前中文无缺字；保留 OFL 和版权信息 |
| REF-AI-TOWN-V2 | 北地残卷日常县城明亮版 v2／本任务 AI 生成 | imagegen，2026-09-16；本项目文字规范与第一版 AI 图为输入，无外部图像输入；不是按第三方素材许可证取得，不把方向认可等同于已审核可商用，详见 [AI-ART-006](./ai_content_register.md#ai-art-006-原始记录与边界) | 内部气质／构图参考，用户已认可方向 | [仓库原样副本](./art_reference/northern_town_daylight_v2.png)；原始生成位置、第一版来源和提示意图见 AI 登记；已取得但未进入运行时或商店 | 无后期修改；仅供文档讨论，现有导出预设排除 `docs/*`；转作生产素材时另建批次并审核，不宣称本图满足瓦片／角色像素规格 |

官方许可证已在 2026-09-13 核对；2026-09-14 对实际文件运行 `shasum -a 256`，结果如下。原文件下载 URL 的具体请求记录未单独归档时，使用上游文件定位与本地哈希，不虚构固定上游提交。

| 实际文件 | SHA-256 |
|---|---|
| `assets/runtime/fonts/NotoSansCJKsc-Regular.otf` | `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b` |
| `licenses/NOTO-OFL.txt` | `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2` |
| `licenses/GODOT.txt` | `b0435e3b3e4e55238f05f4b306f30524a1b2e20147810d436eaa554fa6855c80` |
| `docs/art_reference/northern_town_daylight_v2.png`（2026-09-16 核对） | `9f5789eb649b332fc454b9de6188cff54b1afcbe8da60f437d09f1493308ae0a` |

当前表中未登记任何已完成的正式人物、地图、音乐或音效资产。灰盒颜色、程序绘制形状和内部占位文字不能计入正式资产完成量。Godot 下载包可通过 `python3 tools/verify_downloads.py .tools/downloads Godot_v4.7.2-stable_macos.universal.zip Godot_v4.7.2-stable_export_templates.tpz` 复核官方 SHA-512 清单；该命令核对的是实际下载文件，不是仅比对文件名。

新增条目至少包含：

```text
asset_id:
名称／作者:
原始来源链接:
固定版本／取得日期／文件 SHA-256:
许可证名称及本地原文路径:
购买凭证位置（如适用，不公开个人付款资料）:
原始文件路径／运行时文件路径:
用途与允许的修改／分发范围:
人工修改内容:
状态：候选 / 已取得 / 已接入 / 已审核可发布 / 已移除
审核人及日期:
```

已接入时检查运行时文件实际存在；已审核可发布时检查许可证、署名和包内用途匹配。来源不明确的素材停留在候选状态，不随正式包发布。具体资产的记录随引入动作更新，不能用本表的通用条目覆盖以后所有外部素材。
