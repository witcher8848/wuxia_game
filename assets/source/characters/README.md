# 主角资源：当前imagegen入口与旧native fixture

## 当前生产入口（2026-10-12）

默认探索、战斗与`Character.command`实验室已经统一使用`HeroVisual.ACTIVE_DATA_PATH`指向的`res://assets/runtime/characters/chr_protagonist_imagegen_20261012.json`，不是只在预览中opt-in。该schema2帧表使用15张imagegen原图的逐字节副本，位于`assets/runtime/characters/imagegen_20261012/`；原始取材保留在`docs/art_reference/`，具体来源、实际提示词、输入／输出哈希和失败／取材边界见[生产记录](../../../docs/art_reference/hero_imagegen_production_20261012.md)。

`48×72`是站立主体的最大名义框，不是每帧都拉伸成48像素宽：束髻顶到鞋底约68显示像素，当前walk矩形约25～37像素宽；剑／高举动作和倒地可有更宽或不同高度的显示范围。以每帧`region`、等比`display_size`和相对区域的显示单位`anchor`为准，身体中轴X与鞋底Y保持在物理脚点上，不使用带剑矩形的中心或每次换腿的单只支撑鞋作为身体X轴。原PNG／原alpha保持；只在GPU选择原图区域，不生成位图裁片，不清边、阈值化、量化或程序补人物像素。导入为lossless、最近邻，关闭mipmap、alpha-border修正、预乘与size-limit。

保留57逻辑槽／29 clips：每方向walk4、strike2、thrust3、slash3、guard1、hit1，加单张down；idle复用walk0，thrust／slash恢复槽也复用该方向walk0，不声称57张独立绘画。时序仍为walk8FPS，拳／刺／斩10FPS、守势3FPS、受击5FPS，冲刺步频乘300/180；down持留最后帧。640×360视口、32×32地面／战斗格、20×12物理脚部与180／300速度、伤害／事件／存档规则不变，16×6阴影仍由共享表现层单独绘制。

在仓库根目录验证和查看当前资源：

```bash
python3 -B tools/build_hero_imagegen_manifest.py --verify
python3 -B tools/build_week5_candidate.py --preflight-only
./Character.command
./tools/check_project.sh
```

`--verify`核查已保存帧表、原PNG／runtime SHA、原alpha导入设置；`--preflight-only`只读检查，不构建或导出。需要重现元数据时，在带Pillow的Python环境运行`tools/build_hero_imagegen_manifest.py --emit`，它只读原图并向标准输出给出region、比例及已审查中轴坐标，不保存人物PNG。原始imagegen结果本身不是可由代码重画或保证重新生成同一字节的资产；保留的原PNG与哈希才是取材依据。PCK允许Godot将PNG纹理remap到导入资源，原PNG字节一致性在构建前验证，包内实际纹理由生产测试检查。

生产验证由`test_character_imagegen_pipeline.gd`检查未配置Hero／探索／战斗／实验室的实际默认来源、帧映射、键盘流程与原图保护；`test_character_manifest_renderer.gd`另保留旧atlas区域的工程fixture，不能用它代替新美术验收。当前源码headless与实际渲染14张证据、全量工程回归已通过；工程检查不替代动作自然性、用户审美或Windows硬件试玩。生成人物或补动作只允许使用内置imagegen，不再用下方代码源制作生产主角。

## 旧32×48 native fixture：保留的可再现代码源

`hero_pixel_source.gd`是旧测试图集的可编辑像素源：鞋／裤、短衣／交领、手臂／武器、头发／脸、文袋分层按顺序绘制；色板、四向和帧数在文件头声明。不是Aseprite工程，不依赖商业软件；旧fixture图像由整数坐标与像素行生成，不读取或缩放AI参考图。它只用于旧源／图集再现与回归，不是当前生产人物源；不反向修改旧导出PNG，也不能借此程序重绘已认可的imagegen脸与身体。

仅重现旧native fixture时，在仓库根目录运行：

```bash
./tools/godot.sh --headless --path . --script res://tools/export_hero_art.gd
./tools/godot.sh --headless --path . --editor --import
```

旧导出器只写`assets/runtime/characters/chr_protagonist_atlas.png`和同名JSON，不切换当前`ACTIVE_DATA_PATH`。该旧fixture每帧32×48，脚底(16,44)，8列；方向down/left/right/up，方向内walk4、strike2、thrust3、slash3、guard1、hit1；最后down1，共57帧槽。idle引用walk首帧。相同恢复姿态可以有重复像素，不声称57张独立绘画。要预览旧图集须显式`configure_manifest(HeroVisual.DATA_PATH)`；普通`Character.command`加载的是上方新默认资源。

walk8FPS、冲刺乘300/180；strike/thrust/slash10FPS；guard3FPS、hit5FPS（避免只有0.1秒难以辨认）；倒地持续。动作时序由元数据读取。侧面文袋只显示角色左侧，不对称镜像。

旧源与开发工具不进入导出包；运行时JSON及纹理／Godot导入资源进入包。`HeroVisual.DATA_PATH`、`ATLAS`与静态`data`仍代表旧fixture；它们的存在不意味着默认仍使用32×48。`test_character_source.gd`逐帧比对旧源和旧导出、色板／透明度／导入参数；`test_character_pipeline.gd`保留共享运行时与实际受伤／死亡恢复回归。

2026-10-08脸部反馈修订：正面、侧面、背面分别使用头部模板，暖色脸部形成连续色块；侧面仅镜像头部几何，文袋和持剑手保持解剖侧别。短衣、侧身衣襟、宽袖与松裤分别编辑；行走的腿和脚按相反相位迈步，倒地也落在row43。沿用11色、32×48、57帧槽和既有时序，没有修改碰撞或战斗范围。imagegen候选仅用于外观讨论，本源未读取、裁切或采样候选图片。

`Character.command`中←／→会暂停并前后逐帧，跨动作末帧会循环；空格恢复播放。先在1×检查朝向和脸部，在3×检查像素轮廓与脚底。源回归新增脸部亮色面积／连通性、侧脸一致性和脚部相位检查；这些能防止已知问题回归，但不能自动判断好看或动作自然。

共享表现层另外绘制16×6的固定整数像素椭圆阴影，不写入角色atlas；探索和战斗使用同一阴影几何。战斗插值移动的遮挡顺序按当前显示脚底排序，不按已提交的目标格提前跳层。

2026-10-09独立静态候选源`hero_static_candidate_20261009.gd`只包含正面与左侧，用于造型评审，不参与现有atlas导出器。开发工具`tools/preview_hero_static_candidate.gd`导出原生PNG、1×／3×对比与临时真实场景展示；结果在`docs/art_reference/hero_static_20261009/`，详见[评审记录](../../../docs/hero_static_candidate_review_20261009.md)。候选未经认可前不替换57帧槽或改变动画契约。

同日用户反馈眼睛／五官仍不好看，新增`hero_face_candidate_20261009.gd`仅修订旧候选的面部区域；旧候选源和图片保留。专项工具`tools/preview_hero_face_candidate.gd`输出同身体的前后对比、8×诊断及真实场景截图，见[五官专项review](../../../docs/hero_face_candidate_review_20261009.md)。正常角色导出器／启动器不使用此候选，认可前不迁移到动画。

后续用户选择A并要求短颈、去褐边、参考《口袋妖怪 金》少细节风格，新增`hero_simple_candidate_20261009.gd`重组整个静态造型。源保留`first`／`final`变体，`tools/preview_hero_simple_candidate.gd`输出A与最终版、首轮与剪影收整版及实景；[简化review与重现](../../../docs/hero_simple_candidate_review_20261009.md)。只用既有色板中的6色，A单点眼保留；仍不参与正常atlas导出，脚底和现有动画契约未改。

## 2026-10-11：新原图帧清单准备（未切换）

以下保留2026-10-11当时的准备状态与用户意见，已由上方2026-10-12生产入口取代，不是当前默认说明。用户保留已认可的imagegen外观，要求完成第五周。当时新原图仍是独立候选，正式源与旧导出器保持；不把高清图等比显示称为原生32×48精灵。当时新显示规格等待用户确认，常规探索／战斗／`Character.command`仍加载原atlas。

共享表现层准备`schema_version=2`的可选帧表接口：每个逻辑帧保存原图纹理路径、源区域、等比显示尺寸、脚底锚点及源PNG哈希，保留`clips.cells`的整数索引。只加载／显示导入纹理，不裁切、重绘、缩小写回或清边PNG；待素材齐全且合同批准后再接入默认入口。来源与实际失败候选见[动作补齐记录](../../../docs/art_reference/protagonist_imagegen_week5_motion_20261011.md)。
