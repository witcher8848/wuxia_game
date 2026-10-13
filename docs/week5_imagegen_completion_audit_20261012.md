# 第五周新角色：完成门与打包／测试审计

日期：2026-10-12。对象是当前已认可外观方向的 imagegen 主角，而非 10-08 的旧原生像素主角。本文不生成／加工人物 PNG，不修改运行时素材、共享 renderer 或规则，不代签用户试玩、Windows、实体手柄及第四周体验。

## 1. 当前执行合同

本轮用户授权由代理自主按当前标准完成第五周、不再询问尺寸；主代理选择“原 PNG／原 alpha、主体约 48×72 显示、武器／倒地范围可更宽、GPU region 与实测脚底锚点”的路线。身份、脸与比例不重新设计。不把原图显示缩放称为原生 32×48 精灵，也不宣称它符合旧 11 色／二值 alpha／程序分层源合同。

这是测试主角的显示合同变更，不是修改 640×360 视口、32×32 地面格、20×12 碰撞、180／300 步速、范围、伤害、结算或存档的授权。原图只能原样复制；region 是 GPU 源坐标，不生成裁切 PNG、不阈值清边、不重绘、不量化。主体尺度与完整 region 尺寸不同：不得把长剑的完整 region 强行塞入 48×72 而扭曲纵横比。

计划依据是仓库根的`武侠RPG_六个月开发排期.md`与`武侠RPG_第五周每日任务.md`；另对照[历史评审](../11_week5_review.md)、[用户意见](./week5_playtest.md)、[原图与失败记录](./art_reference/protagonist_imagegen_week5_motion_20261011.md)。不将全部六个月设计／许可证链接图递归塞进本周评审附件。旧“工程完成”及“规格未批准”是各自日期的记录；本轮授权不倒改历史，但新交付必须有自己的证据。

## 2. 必须交付的完整门

| 日 | 新角色完成要求 | 可接受证据，不可替代的部分 |
|---|---|---|
| Day29 | 新源格式、原图／alpha、方向、帧序、region、锚点、等比显示、命名／来源冻结；开发参考与 PCK 分离 | 明确的新合同与来源哈希；旧像素 README 只能描述 legacy，不能充当新源契约 |
| Day30 | 四向各 4 步相，共 16 移动槽；idle 复用各向首步；朝左文袋近侧、朝右远侧；停脚锚点一致 | schema2、原图字节、逐相位实际预览；4 个不同文件／region 不等于近远腿与手臂真正交替 |
| Day31 | 默认探索使用新角色；真实走／冲刺／停步／转向／暂停／失焦；显示脚底跟随物理，不改规则 | 当前默认 manifest 实例断言＋现有物理回归＋实际探索截图；隔离静态合成不足 |
| Day32 | 每向 strike2、thrust3、slash3、guard1、hit1，加单向 down1；含移动共 57 逻辑槽 | 元数据覆盖及独立逐帧动作目视；恢复可复用姿态，不能把 idle 套武器冒充所有动作 |
| Day33 | 探索／战斗复用同资源；合法确认触发，预览／取消不触发；hit/down/retry 正常，表现不改战果 | 新默认实例＋真实战斗命令／快照不变／死亡与重试；人工构造 mapping 不取代合法命令测试 |
| Day34 | 手动四向／动作、1×／2×／3×、暂停、逐帧、步频可用；最近邻与原 alpha 导入；完整回归及当前实绘 | 实际 lab／explore／battle 捕获、布局不溢出、不暗中缩放；headless 或旧图夹具不是新美术实绘 |
| Day35 | 新的独立 EXE／PCK／启动入口、源与资源身份、校验清单、自包含包外评审材料、来源与遗留交接 | 新包内测试与同包真实 Mac 渲染；旧推荐包的 22 个校验和不能证明新角色接入 |

57 是逻辑槽数，不是 57 张独立原画；四向各有 14 个非 idle 槽（4+2+3+3+1+1），另加 down1。播放时序保持 walk8、攻招10、guard3、hit5、idle1、down1 FPS，冲刺乘 300/180；倒地持末帧，其他动作一次后回 idle。

不允许对高分图机械四／八等分后因“region 不越 PNG”就宣布安全。曾有剑尖跨邻格、上举手跨行等实际缺陷。生产 region 必须覆盖本姿态完整身体／武器且不混入邻姿态；这需要逐帧目视与实绘，结构验证无法判断人体或剑属于谁。文袋永远解剖左，持剑永远解剖右；侧面不能无修正镜像。

## 3. 测试身份必须分开

| 现有测试／检查 | 它实际证明什么 | 新合同处理 |
|---|---|---|
| `test_character_source.gd` | 固定旧 Source、256×384 atlas、32×48、(16,44)、11 色、二值 alpha、220 项程序源逐像素一致及旧侧别探针 | 保留全部数值为明确 legacy fixture；不能放宽颜色、亮肤色像素或 alpha 阈值来给新图制造通过 |
| `test_character_pipeline.gd` | 现有 playback、shadow、lab 键盘、战斗 hit/down/retry；有旧 atlas256×384断言 | 旧资源几何断言继续显式 legacy；与默认新角色有关的 playback／lab／战斗必须另有 active-production 覆盖 |
| `test_character_manifest_renderer.gd` | 从旧 atlas 区域构造临时 schema2，含可变 region 与布局、异常拒绝及倒地末帧工程夹具 | 继续显式读 legacy JSON 并配置 legacy 实例；其旧图截图与数百 checks 不算新外观或动作验收 |
| `test_exploration_controller.gd` 等物理／规则回归 | 20×12、180／300、暂停／失焦、存读与行为 | 原值保持；默认生产视觉要有新实例断言，不另改物理来迁就图片 |
| `test_exploration_flow.gd` 底部 HUD 探针 | 审计时硬写 `Rect2(foot−(16,44),(32,48))` | 由主代理改为读取实际 frame geometry／presentation bounds；不能沿用小旧框来漏测新人物遮挡 |
| `validate_hero_manifest.py`＋31 项单测 | 57 槽／clips、IHDR、源 SHA、resource 范围、等比尺寸、合法锚点、去重结构 | 可验证新 manifest；不完整解码、不判断 alpha／色板／自然步态／手与文袋侧别 |
| `audit_pack.gd` | 枚举真正 PCK、开发资源排除、入口／版本／独立存档及旧 atlas存在 | 继续用其广泛排除／入口检查；其旧 JSON 57 与旧 PNG 必需项不是 active manifest 证据 |
| 新 `test_character_imagegen_pipeline.gd` | 本轮生产入口，应验证默认 schema2、原图纹理尺寸、透明 sample、播放、lab、explore、battle、规则不变 | 后续由主代理委派本审计代理独立编写；兼容 `--require-pack` 与真实 `--capture-imagegen`，不能 opt-in 旧夹具后写 active PASS |

完整 `check_project.sh` 必须保留旧夹具及规则回归，同时加入新 active 测试，不能删除会失败的旧测试来让新图过关。源码验证入口不能仍然只执行旧程序像素源。各日志标明 legacy、工程 schema2 fixture 或 active-production；不合并计数掩盖对象。

## 4. 本轮独立第五周 builder

`tools/build_week5_candidate.py`不再只转发共享 builder。它仅导入共享 builder 的包外文档收集函数，不改已有 dirty 的 `build_week4_candidate.py`，不写源码 PNG。包外资料收集保持已有安全范围：正文提及的Python／shell命令是源码工作区入口，不作为可执行附件随review资料递归复制。

前置只读验证：

- 固定 active `res://assets/runtime/characters/chr_protagonist_imagegen_20261012.json`，调用现有 validator 校验 schema2／57／clips／region／等比／锚点／原 PNG SHA。
- 每个被引用 runtime PNG 在原图目录找到 SHA 完全相同的文件；不是同名或视觉相似就通过。主代理 `build_hero_imagegen_manifest.py --verify`负责选图／源映射复核。
- 每个 active PNG 必有 `.import`，明确 `compress/mode=0`、`mipmaps/generate=false`、`process/fix_alpha_border=false`、`process/premult_alpha=false`、`process/size_limit=0`、RGBA 通道 identity；缺字段或重复参数失败。项目默认最近邻仍为0，实际角色最近邻由 active test验证。
- 原 PNG→runtime→stage 的 SHA 相同，stage import 后再次验证 PNG／manifest 未变与导入参数合格。PCK 可以只保存 lossless 导入纹理，不强迫重复保存 PNG 原文件；包内 active test验证纹理原尺寸／透明采样／manifest，而来源原字节等式由源与 stage preflight证明。

旧 atlas `.import` 中的 `process/fix_alpha_border=true` 是审计事实，不改旧夹具；新原 alpha PNG不能沿用此值。PNG IHDR读取不是完整 decode，source 与真实导入纹理 decode由新生产测试补足。

构建过程：

1. preflight与主代理 helper `--verify`通过后才创建新目录；原源树不改 version／入口／存档。
2. 私有 stage复制 game（排除tests/tools）和 assets/runtime，保留项目导出排除规则；stage设置0.5.0版本和 `ProjectWumingCharacterPrototype` 独立存档目录。
3. 导入／Windows Release导出／真正 PCK排除审计，执行包内story／onboarding／week4-feedback及新 active headless test。
4. 同一包使用非 headless的Mac真实渲染执行 `--capture-imagegen --require-pack`，图片写包外 `evidence/`；必须有唯一明确 `CHARACTER_IMAGEGEN_PIPELINE_PASS`，`packed=true`与完整14张640×360 PNG，不能凭退出0或单张图通过。此步骤不宣称 Windows EXE或人类试玩通过。
5. 真实包跨进程存读、PE x86_64、许可证、两Mac PCK启动脚本；评审资料递归复制到 `review/`并重写／验证链接，开发文档不进 PCK。
6. 元数据记录当前 HEAD、真实dirty状态、stage源快照SHA、active manifest／各原PNG／import配置身份，生成覆盖产物、日志、图片和评审资料的SHA256SUMS；只有所有步骤成功才输出 `WEEK5_IMAGEGEN_CANDIDATE_PASS`。

某阶段失败留下的目录是中间产物，不是推荐候选；未将旧包验证迁移至这个目录。Mac脚本依赖本机固定引擎，不是独立Mac App。构建不commit／push／发布。

## 5. 可执行命令及本次已执行结果

```bash
# 只读；不创建build目录、不import／export。生产文件尚未就绪时明确失败。
python3 -B tools/build_week5_candidate.py --preflight-only

# 只在生产PNG／导入／57槽表／默认入口／新测试就绪后运行；生成新独立候选。
python3 -B tools/build_week5_candidate.py

# 保留全部测试对象；临时小PNG仅单元测试夹具，不是生产人物图。
python3 -B -m unittest discover -s tools/tests -p 'test_hero_manifest.py' -v
python3 -B -m unittest discover -s tools/tests -p 'test_review_bundle.py' -v
```

初始审计快照实跑：

- `test_review_bundle.py`：32项，0失败；原13项保持，新增18项只读production provenance／import／stage／PE／checksum测试，另有本审计文件自包含打包回归。
- `test_hero_manifest.py`：31项，0失败；本轮再次执行，不修改原测试阈值。
- 当前用户反馈材料自包含收集：18文档、155本地链接、106文件，未import／export；保留用户原话。
- `--preflight-only`：退出1，明确缺少 `chr_protagonist_imagegen_20261012.json`；这是审计时生产尚未落地的事实，不是伪造PASS。没有运行完整build。
- `git diff --check -- tools/build_week5_candidate.py tools/tests/test_review_bundle.py`：退出0。
- 审计文档首次自包含收集因直接链接整套六个月／逐日计划而递归到允许范围外的`licenses/GODOT.txt`，退出1。已将计划依据保留为正文路径、仅复制本周评审链接图；新增独立审计文件收集测试后通过，不放宽共享builder安全范围。

审计时正式旧三文件保持原字节（不是新角色交付证据）：

```text
hero_pixel_source.gd       b9a67f25008e390b0fa281fa3566a2e29afb2010a185ac6e0b55001d29136a9b
chr_protagonist_atlas.png  e13be6ae0ed90c069bcd195d396b3557b13ac8cfbea97fb95c9dd05f632c0358
chr_protagonist_atlas.json d600fddcbe1def27e727ef0ebaa41e39535018e0f4ac281a1a73a3dbf55d8146
```

已有dirty共享builder的审计SHA为 `145de6d823f661a837e996e2af794ab05d89625a2f3b4829e61f545dce8dc042`；本代理不修改它。其他代理后续修改的生产资产／renderer／检查入口由各自记录与新候选身份说明。

## 6. 尚不能签的结论

截至上方初始快照，新生产57槽、真实默认探索／战斗、手动样本、完整项目回归和新包均未由本代理验证。后续必须追加真实路径、hash、命令结果与实绘目视记录，不能将计划写成结果。

已有原图来源齐全或四向八姿态齐全，只能说明候选覆盖，不自动说明四向自然循环、完整武器region、正确解剖持剑或安全遮挡。原PNG预览中的透明RGB灰底亦不能直接推断实际可见光晕；10-12实际Godot合成已纠正此误判，但不消除region／动作缺陷。

用户旧版“整体动画演出没有问题”不转移为新图每帧认可；可交付测试版并如实标明仍需人工判断的自然度／风格。第四周引导复测、首月体验门、Windows真机、实体手柄、新玩家样本保持未验。第五周收口不扩展为第六周、地图／NPC量产或商店发布。

## 7. 新 active-production 测试落地（仍未给素材签通过）

本代理后续独占新`game/tests/test_character_imagegen_pipeline.gd`，不改旧fixture测试／renderer／PNG。默认 manifest 必须是`chr_protagonist_imagegen_20261012.json`；如果文件缺失或`Hero.ACTIVE_DATA_PATH`仍legacy，就退出1，无最终PASS，不靠`configure_manifest()`临时替换旧默认通过。

实际覆盖包括：

- schema2／57槽／29clips／时序／idle复用；所有texture完整解码、原尺寸`source_size`、region有可见内容、透明背景与最近邻；每帧明确`source_reference`和SHA。
- 源码模式原PNG与runtime逐字节SHA相等，导入纹理readback与原PNG解码RGBA逐字节相等；PNG只读、开始结束保护hash。PCK无原PNG时如实使用原尺寸／SHA格式／texture alpha readback，原文件等式由build preflight证明，不从`.ctex`字节伪造原PNG SHA。
- 每向4个实际解码region内容hash不同，并打印16个fingerprint；明确标注它不证明解剖步相、手臂方向或自然度。
- 真实CharacterBody输入、20×12／180／300、四向走停、整数显示／小数物理、冲刺、暂停／失焦／SceneTree暂停与释放门；普通`main.tscn`真实探索实例、真实移动与免费时段。
- 正常lab默认四向新资源，手动动作／1×2×3×／暂停／冲刺／逐帧／方向切换；全动作每倍率边界检查，完整region不得隐藏为越界警告或静默缩小。
- 原故事遭遇配置＋生产`BattleScreen`／`Board`默认实例；合法键盘guard与取消、合法敌人伤害hit、真实down／重复同步不重启、键盘重试、真实移动插值与快照不变。retry仅允许既有规则的revision+1（废弃旧预览），其他战斗快照字段必须与初始完全相同；不修改规则或属性。

固定实绘清单为14张：`walk_1x.png`、`walk_2x.png`、`walk_3x.png`、`walk_phase_0.png`至`walk_phase_3.png`、`thrust.png`、`slash.png`、`guard.png`、`hit.png`、`down.png`、`exploration.png`、`battle.png`。截图只写viewport证据，禁止写源／角色目录；生产人物PNG不处理、不写回。完整包外验证还要求确切文件集合、每张IHDR640×360与唯一最终packed PASS marker。

实际命令：

```bash
./tools/godot.sh --headless --path . --script res://game/tests/test_character_imagegen_pipeline.gd
```

首次编译遇到429行多余括号，Godot竟退出0但有`SCRIPT ERROR/Parse Error`；已修正。这正是不能只看退出码的实证。修复后已两次实际运行，成功编译并明确退出1，`2 checks, 2 failures`：生产manifest缺失、默认仍legacy。没有`CHARACTER_IMAGEGEN_PIPELINE_PASS`，没有生成截图；素材齐备后的更深覆盖仍待真实执行，不能因代码写齐就标通过。

wrapper另加入source_reference原路径与source_size精确IHDR核对、明确packed PASS和完整14截图校验；`test_review_bundle.py`现35项全通过，旧13项不变。renderer代理已只读复核wrapper入口／无PNG加工／preflight无写入，并建议最终marker与完整清单；建议已落实。完整build依然未运行。

## 8. 最终实际收尾复核（2026-10-13）

上文第5～7节是落地前历史快照，不再代表当前缺资源状态。新默认已切换，schema2／57槽／29clips／15原PNG已接入。源码headless1183／0、Apple M4 Compatibility源码实绘1255／0／14图；完整日志 `builds/qa/week5_imagegen_final_project_check.log` 以 `PROJECT_CHECK_PASS` 结束，包含新生产测试而非仅legacy fixture。

已成功运行一次完整builder，未重启或用中间包替代：`builds/week5/0.5.0-week5-prototype_imagegen_645127f_20261012T154536Z/`。真正包内headless1092／0、同包Mac实际渲染1164／0／完整14图，唯一PASS marker分别为packed=true／captures=0和packed=true／captures=14。资源排除审计141／34、故事623、引导213、第四周反馈199、跨进程存读131／24均通过；Windows PE为x86_64，未执行Windows真机。

10月13日主代理直接读取包内日志、完整SHA256SUMS、元数据与14张包内PNG。166个构建时文件校验全部通过；15个原图／manifest／import参数的current preflight与包元数据完整相等，且重新执行wrapper的最终marker／精确14张640×360集合／PE验证通过。包内原PNG无需重复保存，源到stage原字节和导入原RGBA已在源码／构建前验证，PCK验证实际导入纹理／默认接线／运行行为。

包PCK SHA-256 `714c927dd2dfdc3c0b86aa24fd2da486a46486b7ae9ed21e7a9886aedc937cbe`，EXE `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`，manifest `ed5a342f06b62191a718551521020c5159ffc2f5a5b97f9bf582bc5385098561`。元数据dirty=true与真实工作树一致；源码快照SHA `5463741224d4893a48d68c4d685d8cb868c3686f8d422719b854d55395ff844b`，存档隔离 `ProjectWumingCharacterPrototype`。收尾仅追加包外启动说明并更新其校验清单，不修改PCK／EXE／角色PNG。

Day29规格／来源、30四向移动、31实际探索、32基础动作、33战斗共享、34手动预览与完整回归、35独立包／意见／交接均有直接证据；当前测试资产与工程交付可收口。最终审美／连续节奏、新玩家体验、首月门、Windows／实体手柄仍未替用户签字；不进入第六周或美术量产。逐项最终记录在[第五周评审](../11_week5_review.md)。

追加启动说明后最终校验：SHA256SUMS共167项，清单与实际所有文件集合精确相等、每项SHA正确；167项包括新增HANDOFF.md，PCK／EXE仍为上述hash。current runtime137个文件（含候选版本／存档配置的确定性替换）重新按stage规则计算，SHA仍为上述54637412…44b，证明不是只有人物PNG相同而运行代码已漂移。原图测量重现manifest57槽／29clips／15来源完全相等。

10月13日最后全量回归记录 `builds/qa/week5_imagegen_delivery_project_check.log` 退出0，以 `PROJECT_CHECK_PASS` 结束；源码生产1183项零失败、31／35项单测、25文档／193链接通过。包内PLAYTEST／HANDOFF／来源快照199个本地链接检查通过。附加普通角色场景启动检查首次误用相对PCK路径明确退出1，日志保留，未计通过；改用与实际启动器一致的绝对PCK路径后实启30帧退出0，`week5_imagegen_final_lab_entry_absolute.log` 无脚本错误。这是测试命令路径修正，不声称修复了不存在的角色或游戏错误。
