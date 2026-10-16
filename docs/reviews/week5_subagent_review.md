# 第5周 subagent review：主角素材与共享渲染

日期：2026-10-16。审查基线：`041038d4d83acb38a418629c6804f76b9e5c4778`。

本次先独立只读审查，再按主代理采纳意见修复。范围是一名现有主角的素材管线和表现层，不扩展正式角色量产，不重新设计已认可的脸、服装或比例。

## 审查依据与范围

依据第5周每日任务、`11_week5_review.md`、`05_art_bible.md`第12节当前原PNG合同、生产记录与试玩反馈。区分当前imagegen默认与旧32×48历史fixture，不以旧图测试替代新默认验收。

核对了以下内容：

- 四向各4行走帧、57逻辑槽／29 clips，idle和攻击恢复帧的明确复用。
- walk 8 FPS、攻招10 FPS、guard 3 FPS、hit 5 FPS；倒地保持和重复同步不重启，重试清除。
- 探索真实移动、180／300速度、20×12脚部碰撞、整数显示与小数物理，以及暂停／失焦。
- 真实成功命令触发动作，预览／取消不触发；hit／down／retry、战斗插值与脚底排序不改规则快照。
- 探索、战斗、实验室共享默认。第6周战斗专用0.4 GPU缩放与原图显示合同共存，未当作审美bug撤销。
- 原PNG／原alpha、纹理区域／脚锚、最近邻及无损导入、资源路径／范围／异常配置校验，实验室倍率／动作／逐帧。

实际查看了已有生产截图walk 1×、thrust、down，未见明显裁鞋、裁剑或邻人污染。这是查看既有图片，不是本轮新GPU实绘，也不等于用户对自然度或审美签字。

## 发现与修复

### W5-R1 · P2 · 查询结果可以篡改已验证的角色数据（已修复）

基线位置：`game/presentation/characters/hero_visual.gd:66–72`。

`manifest_data()`和`clip_data()`返回内部可变Dictionary；修改查询结果的嵌套Array即可绕过`configure_manifest()`校验，且几何／bounds缓存不会失效。

复现脚本位于本地`builds/qa/review_week5_query_probe.gd`，未写入生产素材：

```gdscript
var view = hero.manifest_data()
view.frames[0].anchor = [0, 0]
var clip = hero.clip_data("walk_down")
clip.cells[0] = 999
```

修复前`review_w5_query_probe.log`记录：元数据锚点变为`[0,0]`，缓存锚点仍为`(13,68)`；当前帧变为999、几何为空，人物会静默消失，但manifest路径仍宣称生产资源有效。

修复将对外manifest／clip查询改为深拷贝；逐帧内部访问使用私有借用函数，避免每帧复制整份57槽manifest。配置校验、缓存更新策略、动作时序、脚锚、碰撞和所有角色原图均保持。

`presentation_bounds()`返回的是Rect2值，不存在Dictionary／Array别名；仍补充了修改返回值不会改缓存的回归。`frame_geometry()`原有独立Dictionary查询也再次覆盖。

新增34项回归覆盖生产默认、legacy实例、schema2 fixture以及入树前legacy fallback：修改嵌套帧锚／region／clips／cells、清空数组、改fps、修改几何与bounds，均不得改变有效数据、当前可见帧、缓存或来源身份。

修复后`review_w5_query_probe_fixed.log`记录：元数据与缓存锚点保持`(13,68)`，当前帧仍为0、几何非空，来源与几何不变。

没有发现其他达到可复现P0／P1／P2标准的问题；未把未认可的审美改动、未来量产能力或Windows／手柄未测当作本轮工程缺陷。

## 实际验证

全部为源码／本地headless或只读校验；本代理未运行GPU、导出或重建冻结包。

| 检查 | 结果 | 本地证据 |
|---|---|---|
| manifest Python单测 | 31项通过 | `python3 -B -m unittest discover -s tools/tests -p 'test_hero_manifest.py'` |
| 原图／runtime／导入／结构 | 57槽、15份原PNG通过 | `python3 tools/build_hero_imagegen_manifest.py --verify` |
| 修复前renderer | 597项／0失败；尚未覆盖查询别名 | `builds/qa/review_w5_renderer.log` |
| 修复后renderer | 631项／0失败，新增34项隔离回归 | `builds/qa/review_w5_renderer_fixed.log` |
| 修复后生产默认管线 | 1183项／0失败，`packed=false captures=0` | `builds/qa/review_w5_active_fixed.log` |
| 原缺陷前后对照 | 相同临时脚本，坏帧999变为合法帧0 | `builds/qa/review_w5_query_probe.log`／`review_w5_query_probe_fixed.log` |

复测命令：

```bash
python3 tools/run_checked.py review_w5_renderer_fixed ./tools/godot.sh --headless --path . --script res://game/tests/test_character_manifest_renderer.gd
python3 tools/run_checked.py review_w5_active_fixed ./tools/godot.sh --headless --path . --script res://game/tests/test_character_imagegen_pipeline.gd
python3 tools/build_hero_imagegen_manifest.py --verify
```

`run_checked.py`同时核对退出码和Godot脚本错误，不只凭退出0判通过。

## 原图保护与验收边界

生产manifest SHA-256仍为`ed5a342f06b62191a718551521020c5159ffc2f5a5b97f9bf582bc5385098561`，与审查基线和第5周冻结记录一致；`--verify`逐一确认其15份原PNG／runtime字节SHA、原尺寸与导入设置匹配。生产默认测试也检查读取前后保护hash。没有修改manifest或角色PNG，原alpha、原图取材和脚锚未变。

本代理只修改共享renderer、对应renderer测试和本记录；未提交、推送、生成图片、构建发行包或改写冻结候选。用户审美、连续步态自然度、第四周引导复测、新玩家／首月体验门、Windows真机及实体手柄仍不代签。角色当前在战斗中较小的可读性可由主代理另行评估，不借本次数据隔离修复暗改显示比例。
