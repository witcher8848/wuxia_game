# 右向四步相远侧文袋 imagegen 候选（2026-10-12）

## 结论与任务边界

本轮只使用内置 `image_gen` 一次，将四个已有右向步相原图作为各自姿态参考，整理为一行四人，并请求仅统一解剖左髋远侧文袋遮挡。

**袋遮挡改善成立，但完整四相姿态保持未通过。** 输出四人都朝画面右，近侧大文袋消失，仅可见细棕色远侧边；第 1／3 格近侧臂姿态有差异。不过第 0／2 格仍显示相似的近侧臂后摆与接触腿覆盖，第 2 格没有保留输入 phase2 明显前伸的近侧大袖臂，不能宣称两个接触相已经清楚交换支撑腿／反摆手臂。保留候选供主代理复审，不作为完整四帧动画通过或第五周完成证据。

没有第二次调用、没有修改旧 PNG、镜像、裁切、程序重绘、缩小写回或清 alpha。仅新增本 PNG 与本记录，未改源码／renderer／其他 MD／登记，未提交、未 build 或打包。输入原图仍保留。完整读取 imagegen SKILL.md、prompting.md、sample-prompts.md，实际逐张查看五个输入与保存输出；skill 用于身份／姿态参考、透明输出和非破坏保存，单次限制优先于通用迭代建议。

## 实际输入（工具顺序）

所有路径均在 `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/`：

| 输入 | 完整文件名／角色 | SHA-256 | bytes |
| --- | --- | --- | --- |
| Image 1 | protagonist_imagegen_walk_right_pose0_restored_20261010.png；phase0 contact 近腿前／近臂后参考 | 48da9de48f6d13c1c58209f75dccc70ee462cc9d81f0429148d901b718e81ad9 | 1,196,341 |
| Image 2 | protagonist_imagegen_walk_right_pose1_restored_20261010.png；phase1 passing 参考 | 14a68f8777bc73ba8b82d98666b37cf1e756e66d40119a14df41204a5af91d97 | 1,149,420 |
| Image 3 | protagonist_imagegen_walk_right_pose2_consistent_20261010.png；phase2 opposite contact／近臂前参考 | c4860108e629eda5024e3607b1fd3a60f1e208c140ce65feff3ba9962658e357 | 1,240,074 |
| Image 4 | protagonist_imagegen_walk_right_pose3_bagfix_20261011.png；phase3 opposite passing／近袖前参考 | 96e7ece0373f6e0ef37b5096ac4bde45e78f066786f290b75739bfea334b4ba2 | 1,119,624 |
| Image 5 | protagonist_imagegen_turnaround_20261011_v3.png；已认可身份／右向远侧袋参考 | fdb71157e5dae68a1badfa3103a8ded1805742a6ed45e2db76e8d30bb0b5c67f | 1,124,087 |

工具 `referenced_image_paths` 恰为表中五个完整绝对路径；`transparent_background=true`，没有 recent-image 自动选择。2048×1024 为实际 prompt 中画布偏好，不是内置工具尺寸参数，也不将偏好当实际输出尺寸。

## 输出来源与原样保存

- 原始生成路径：`/Users/witcher/.codex/generated_images/01a12b2d-02c3-7b11-b2b2-6107ce8c028f/exec-9c4e400c-bfc4-4cf3-9599-6deb7d2e6b4f.png`
- 归档路径：`/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/hero_walk_right_20261012.png`
- 原始／归档 SHA-256 均为：`1e68448c90d2cd7bb7dfb26260998902aa16362c3b133ff2f43bcf193faf5156`
- 两处 bytes 均为 1,198,812，原始输出仍保留。
- 使用不覆盖的字节复制，未进行任何 PNG 处理或写回。

## 实际提交的完整 prompt

```text
Use case: identity-preserve
Asset type: one transparent four-frame right-facing walk-cycle sheet
Input images: Image 1 is walk phase 0; Image 2 is phase 1; Image 3 is phase 2; Image 4 is phase 3. Preserve each of these four distinct limb poses in exactly that order. Image 5 is the approved four-view identity/outfit reference; use its RIGHT-facing figure to confirm far-side pouch occlusion and the same youthful face, not to replace walking with standing.
Primary request: Compose exactly FOUR full-body figures in ONE HORIZONTAL ROW on a wide landscape canvas, preferred 2048 x 1024. All four figures are the same approved boy facing screen RIGHT, in phases 0,1,2,3 from left to right. Change only the incorrect pouch-side visibility in Images 1–4: anatomical LEFT-hip document pouch must be on the FAR side, mostly hidden by the torso and hips, at most a tiny brown far-side edge. REMOVE the large brown pouch shown on the visible NEAR hip of the pose references. Do not put a new large bag on the near hip. The strap remains coherent from anatomical right shoulder to far anatomical left hip, then disappears behind the body.
Pose preservation: Do not replace all four by one idle or walking pose, do not mirror originals, do not redesign faces. Use the original four poses as the authoritative shape references apart from pouch occlusion. Preserve each figure's near/far sleeve overlap, leg overlap, knee bend, lifted shoe and opposed arm swing. In frame 0/contact, the NEAR leg reaches FORWARD toward screen RIGHT and the FAR leg reaches BACK toward screen LEFT, with the near arm swinging backward and far arm forward. In frame 1/passing, the NEAR leg supports vertically under the body and the FAR leg passes forward lifted, retaining Image 2's arm/sleeve arrangement. In frame 2/opposite contact, the FAR leg reaches FORWARD toward screen RIGHT and NEAR leg reaches BACK toward screen LEFT; reverse the near/far leg overlaps and arm swings from frame 0, keeping Image 3's larger forward near sleeve. In frame 3/opposite passing, the FAR leg is the planted support and the NEAR leg passes forward lifted, retaining Image 4's forward near sleeve and near hand. Frames 0 and 2 MUST remain visibly different with opposite supporting legs; frames 1 and 3 MUST remain different opposite passing phases, not duplicates.
Identity/style invariants: keep the approved head/face proportions, short neck, black fringe/topknot and blue tie, warm skin, blue-gray cross-collar short tunic, white cuffs/collar and waist ties, dark loose trousers, blue leg wraps and complete dark cloth shoes. Preserve the same crisp stepped pixel style; do not grow the boy taller, older, more chibi or invent a new face.
Composition: normalize all four to the SAME body/head scale and planted-foot sole baseline, with similar full-body height and ample top/bottom transparent margins. One figure in each quarter, centered with enough empty space for both complete shoes and arm swing; no shoe, toe, limb or hair crosses into a neighbor's quarter, touches the canvas or is cropped. Keep all four figures independently separated, no overlap, no second row.
Scene/backdrop: genuinely transparent RGBA, original-style alpha from imagegen, no opaque backdrop, no fake checkerboard, no ground, shadow, glow, halo, captions, numbers, grid lines, weapons or effects. Do not perform alpha cleaning or pixel redraw outside imagegen. No sword. No near-side large pouch.
Text: none.
Avoid: mirroring, direction changes, new avatar identity, front-facing figures, idle duplicates, same near leg leading in both contact phases, same passing leg in frames 1 and 3, swapping pouch to anatomical right hip, large visible near-side pouch, clipped shoes, cross-frame overlap, extra people or rows.
```

## PNG 只读统计

Pillow 仅读取尺寸、alpha、哈希与主体连通坐标，没有把区域保存成图片。

| 检查项 | 实际值 |
| --- | --- |
| 输出尺寸／模式 | 1774 × 887 / RGBA |
| 总像素 | 1,573,538 |
| alpha 范围 | 0–255 |
| alpha = 0 | 867,034 |
| 1 ≤ alpha ≤ 254 | 705,520 |
| alpha = 255 | 984 |
| 外边最大 alpha／非零采样 | 0 / 0（5322 四边采样，角重复） |
| phase0 主体 alpha>127 bbox | [41,61,481,855] |
| phase1 主体 alpha>127 bbox | [517,61,870,859] |
| phase2 主体 alpha>127 bbox | [895,61,1325,855] |
| phase3 主体 alpha>127 bbox | [1384,64,1754,859] |
| 相邻主体横向净间距 | 36 / 25 / 59 像素 |
| 各主体鞋底核心下缘（排除） | 855 / 859 / 855 / 859 |

包围盒使用左上包含、右下排除的全图坐标。四主体高度为 794／798／794／795；scale 与脸身体大小观感基本一致，但 planted sole 并非精确同一 source y，contact 与 passing 相下缘相差 4 像素。这不是已完成的脚底 anchor 校准；主代理可另行确定显示 metadata。

严格按四等列取 region 为 [0,0,443,887]、[443,0,444,887]、[887,0,443,887]、[1330,0,444,887] 时，phase0 右脚核心会穿过 x=443 分界到 x=480，第一／二 quarter 边界 alpha 最大均为 253，不能用硬等分截鞋。phase1 真实主体从 x=517 起，仍与 phase0 有 36 像素净间隔；因此存在不等分独立显示区域的空间，不能只因等分失败便宣称真实两人重叠。phase2/3 严格边界最大 alpha 仅为 1 的弱像素。具体 region 由主代理测定，本轮不生成裁图／JSON。

输出存在大量半透明像素，画布外沿全零；未进一步证明所有主体周边像素都没有弱残留，不作 alpha 清理，不把“transparent=true”提示当成验收结果。透明数据只证明 PNG 真实 RGBA 与外边无非零，不代替实际游戏合成／缩放 review。

## 实际逐相目测审核

- **共同身份与方向**：四人均向右，黑发束髻蓝带、已认可少年侧脸观感、蓝灰交领短衣白袖腰带、深裤绑腿布鞋保持可识别身份。没有换成 front、left 或另一脸设计；不能声称逐像素等同原单图。
- **文袋**：四格原来的近侧大片棕袋都消失，侧腰只留狭窄棕色远侧边，肩带仍可辨。这与 faceRIGHT 时解剖左髋远侧主要遮挡的约定相符。
- **phase0**：张腿接触姿态，近侧较大袖臂向画面左后方摆，另一臂在前，双鞋完整。
- **phase1**：一腿垂直支撑、另一脚在画面右前方抬起；近侧臂更垂直向下，比 contact 收拢。
- **phase2（未通过保持）**：本应保留 Image3 的前伸近侧大袖臂与 phase0 相反的腿覆盖，但输出近侧大袖仍后摆，前面仍是另一较小袖／手。两 contact 格裤腿覆盖与鞋方向也相近，没有足够明确的近远腿交换证据。只因两 region/hash 不同，不代表动作相反。
- **phase3**：近侧大袖与手在画面右前方，另一袖手后摆，与 phase1 的袖臂层次有差异；一腿支撑、另一脚右前抬起。passing 的近远腿语义仍需连播复审，不宣称已在游戏 1×验证。
- **完整性与避免项**：四人均双鞋可见，真实主体之间有间隔，没有其他人物、武器、文字数字、格线、地面或可辨认投影。第一格鞋不是画布裁掉，而是稍跨严格 quarter 分界，独立区域可另选。

本轮至此停止：袋遮挡可用作改善参考，不能把 pose0／pose2 相似的失败掩盖为完整四相循环成功。

