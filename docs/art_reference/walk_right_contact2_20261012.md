# 右向相反接触 phase2 单帧 imagegen 补充（2026-10-12）

## 状态与范围

本轮是独立单帧需求，仅调用内置 `image_gen` 一次。以原 pose2 为编辑目标，保留其近侧大白袖臂前摆、远侧臂后摆、相反接触腿姿态，仅请求改变文袋为解剖左髋远侧主要遮挡。输出单个完整右向少年，**目测 pose2 关键区别保持，可供主代理独立取 region 复审**；未生成四姿态表，也未重绘新 sheet 的 0／1／3。

未调用第二次、未程序处理 PNG、镜像、裁图、缩放写回、清 alpha 或更改人物脸。只新增此 PNG 与本记录；旧单图和四帧新 sheet 均保留。没有修改 renderer、源码、其他 MD、主登记、正式资源，未提交或 build／打包。仍需主代理在实际运行时连播、尺寸／anchor 校准及完整第五周验证，不将单帧成功冒称全部动画通过。

完整读取 imagegen SKILL.md、prompting.md、sample-prompts.md，并实际查看两个输入与输出。skill 引导采用精确对象编辑、显式不变量、透明输出、非破坏保存；单调用限制优先于通用迭代建议。

## 输入、原始来源与哈希

1. **Image1 编辑目标／唯一 limb、脸比例、服装姿态依据**：
   - `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/protagonist_imagegen_walk_right_pose2_consistent_20261010.png`
   - SHA-256 `c4860108e629eda5024e3607b1fd3a60f1e208c140ce65feff3ba9962658e357`
   - 1,240,074 bytes。
2. **Image2 仅 rendering／身份与远侧袋参考**，不复制其重复 contact2，也不重画其四人表：
   - `/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/hero_walk_right_20261012.png`
   - SHA-256 `1e68448c90d2cd7bb7dfb26260998902aa16362c3b133ff2f43bcf193faf5156`
   - 1,198,812 bytes。

工具参数为 `transparent_background=true`、`referenced_image_paths` 恰为上述两个完整原图，未使用 recent-image 自动选择。输入哈希在保存后再次读取仍一致。

- 原始生成路径：`/Users/witcher/.codex/generated_images/01a12b2d-02c3-7b11-b2b2-6107ce8c028f/exec-106adc00-3619-4245-b343-e715b15a680b.png`
- 原样归档：`/Users/witcher/Documents/ChatGPT/wuxia_game/docs/art_reference/hero_walk_right_contact2_20261012.png`
- 原始／归档 SHA-256 均为：`64e6c083ab605328fd6223ec873356be16d3131b6b6f71a7b294beabfb17d17a`
- 两处 bytes 均为 1,178,188。
- 不覆盖旧文件的字节复制，原始输出仍保留；没有写回人物像素。

## 实际提交完整 prompt

```text
Use case: precise-object-edit
Asset type: one transparent full-body RIGHT-facing opposite-contact walk pose
Input images: Image 1 is the EDIT TARGET and sole authority for this pose's face, head/body proportions, silhouette, limb positions, sleeve/leg overlaps, colors and clothing. Image 2 is ONLY a rendering/identity and far-side pouch visibility reference; its LEFTMOST figure may guide the tiny hidden-pouch treatment. Do NOT copy the repeated contact pose from Image 2, and do not output its four-person sheet.
Primary request: Return exactly ONE complete full-body boy, facing screen RIGHT, preserving Image 1's opposite-contact pose. Change ONLY the brown document pouch's visibility: it belongs on anatomical LEFT hip, the FAR side from this camera, almost fully hidden by torso/hip. Remove the large visible NEAR-side brown pouch; at most leave a tiny far brown edge. Keep its existing diagonal strap coherent and disappearing behind the far hip. Do not move the pouch onto anatomical right hip.
Essential pose lock: Keep Image 1's prominent NEAR anatomical RIGHT arm and LARGE WHITE CUFF swinging FORWARD toward screen RIGHT, in front of the chest/waist. Keep FAR arm swinging BACK toward screen LEFT. Keep FAR leg extended FORWARD toward screen RIGHT with the front shoe planted. Keep NEAR trouser leg extended BACK toward screen LEFT with its trailing heel raised. Preserve the original pant-leg overlap showing that the back leg is near and the forward leg is far. Do not reverse the arm swing, do not shift the large near cuff backward, do not switch to the other contact pose or a passing/idle pose. The forward near arm is the most important visual distinction from the repeated phase-0 pose in Image 2.
Identity invariants: retain Image 1's exact approved youthful side face and head proportions, short neck, black fringe/topknot with blue tie, warm skin, blue-gray tunic, white collar/cuffs and waist ties, dark loose pants, blue leg wraps and both complete dark cloth shoes. Do not redesign or redraw the face or restyle the boy. Preserve the reference's crisp stepped pixel illustration.
Composition: one figure only, centered on a portrait canvas (prefer the edit target's 1024 x 1536 framing), complete topknot, both hands, legs, shoes and toes visible with transparent margin. No additional poses or people.
Background: actual transparent RGBA, preserve the generated alpha; no ground, shadow, glow, checkerboard, text, number, label, weapon, skeleton overlay, guide lines, temporary colors or effects. No programmatic alpha cleanup.
Avoid: four-frame sheet, copying Image 2's duplicate contact stance, near arm swinging backward, incorrect leg overlap, near-side large bag, left-facing mirror, new face, cropped shoes or enlarged/taller body.
```

## PNG 只读核查

仅用 Pillow 读取尺寸、alpha、包围盒与哈希，不导出图片片段。

| 项目 | 实际值 |
| --- | --- |
| 输出尺寸／模式 | 1024 × 1536 / RGBA |
| 总像素 | 1,572,864 |
| alpha 范围 | 0–254 |
| alpha = 0 | 1,120,388 |
| 1 ≤ alpha ≤ 254 | 452,476 |
| alpha = 255 | 0 |
| alpha > 0 bbox | [33,29,920,1520] |
| alpha > 127 bbox | [174,91,889,1464] |
| 四条外边最大 alpha／非零采样 | 0 / 0（5120 四边采样，角重复） |

坐标为左上包含、右下排除。主体 alpha>127 的头／鞋轮廓距画布左右上下面约 174／135／91／72 像素，完整全身有 margin。弱 alpha>0 范围更宽，未证明周边完全无残留，也未进行 alpha 清理。真实透明数据不是依赖 `transparent=true` 提示；正式游戏合成与缩放仍由主代理测试。

## 实际目测审核

- **数量与方向**：仅一个完整人物，侧脸朝画面右，没有四帧 sheet、镜像、其他人物或站立 idle。
- **关键近臂**：近侧蓝色大袖与大白袖口在胸／腰前，近侧手向画面右前摆；不是新 sheet contact0／contact2 的近臂后摆。袖口、手掌与前伸层次清晰。
- **远臂**：另一较远袖／手臂向画面左后摆，与近臂相反；没有临时颜色或骨架指示。
- **腿**：前踏鞋在画面右，后蹬鞋在画面左，裤腿覆盖层次与原 pose2 观感一致。按目标姿态解读为远腿向右前踏、近腿向左后蹬，后鞋跟较高；没有变为双腿收拢的 passing。近远腿语义仍属于二维目测，未做骨骼绑定或游戏连播证明。
- **文袋**：原先近侧大片棕色文袋被隐藏，袋下原先遮挡的蓝衣片可见，仅保留窄棕色边／肩带消失处，符合解剖左髋远侧主要遮挡。没有新放大的近侧袋。
- **身份与衣服**：原 pose2 的少年脸、眼鼻轮廓、发髻蓝带、短颈与头身比例、蓝灰交领衣白袖腰带、深裤绑腿布鞋保持可识别；未设计另一张脸。不能据目测宣称整个输出与原图只有某矩形内像素变化，imagegen 结果不等于精确像素差分保证。
- **完整与避免项**：头发、双手、双腿、两鞋／鞋尖完整，无剑、文字数字、色标、骨架、地面或可辨认投影。

本轮单帧归档后停止。原四帧 sheet phase2 的回退风险记录不删除；主代理可以独立用此新原图替代该逻辑 frame2，而不改写另外三帧像素。

