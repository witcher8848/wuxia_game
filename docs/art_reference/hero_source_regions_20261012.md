# 主角原始 PNG：GPU region 只读测量（2026-10-12）

## 结论

首批 12 张原 PNG 共 49 个主体，**41 个可用独立矩形，8 个必须换源**。新增 front 四动作单行原图已有 4 个独立主体，可替换旧 down 的 0..3；合计现已测量 13 张 / 53 个主体，45 个可隔离。原测量全部保留，旧失败记录不会因新来源通过而删除。

当前尚待换源只有 **down 4 斩蓄 / 6 护剑；left 2 刺蓄 / 4 斩蓄**。动作编号均为 0-based 阅读顺序：0拳蓄、1拳伸、2刺蓄、3刺出、4斩蓄、5斩末、6护剑、7受击。

完整逐帧 bbox、SHA-256、邻人像素计数及推荐 GPU rect 见 [实际测量 JSON](hero_source_regions_20261012.json)。测量只看 **Alpha > 127，8 连通**；没有把 Alpha=0 的隐藏 RGB 或灰底预览判作可见 halo。没有改动、裁切、缩放、抠图、重编码任何 PNG，也没有使用 mask/shader 分离人物。

## 哪些矩形必须换源

| 原图 key | 原格 | 最小完整 region [x,y,w,h] | 该矩形内邻人 Alpha >127 像素 | 状态 |
| --- | --- | --- | --- | --- |
| combat_down | 0 | [145,13,255,393] | 234 | 已有 front_first4 0 替代 |
| combat_down | 1 | [621,14,253,401] | 607 | 已有 front_first4 1 替代 |
| combat_down | 2 | [142,398,278,379] | 550 | 已有 front_first4 2 替代 |
| combat_down | 3 | [607,400,277,383] | 839 | 已有 front_first4 3 替代 |
| combat_down | 4 | [141,782,292,368] | 573 | 需新独立来源 |
| combat_down | 6 | [154,1135,238,386] | 839 | 需新独立来源 |
| combat_left | 2 | [124,398,325,361] | 212 | 需新独立来源 |
| combat_left | 4 | [120,753,333,389] | 292 | 需新独立来源 |

每个主体完整的轴对齐矩形一定包含其最小 bbox。上述邻人已经位于最小 bbox 内；缩小会剪自身，放大仍含邻人，因此不能靠不等分、更大 region 或平移解决。

## 可以直接交给 renderer 的范围

- `combat_right` v3 和 `combat_up`：各 8 帧均可用独立 GPU rect。
- `combat_left`：0、1、3、5、6、7 可用。特别是原格 3 虽剑尖跨等分列，实际完整 bbox 没有邻人；推荐 **[495,396,471,365]**，旧“跨格所以不能用”的结论已撤销。
- `combat_down`：5、7 可用；它们只能加 1px 原始 padding（推荐分别 **[580,787,407,363] / [617,1149,277,373]**），加 2px 会混入邻人。其他推荐帧采用 2px 原始 padding。
- 新 `combat_down_first4`：[front 拳/刺四格](hero_front_fist_thrust_20261012.png)，实际 2172×724；四帧推荐为 **[56,8,463,699]、[600,8,466,699]、[1166,8,455,699]、[1688,8,459,699]**，均没有邻人，未触画布边。
- 三张 walk 四格及 right 四张单图：16 帧全部可矩形隔离，没有因 region 需要重生的步相。这个结论不是“四步相已通过”的伪证明；之前单看姿态的相位/近远腿疑点应由实际 8fps 播放核对，不应再以等分格或隐藏 RGB 作阻碍。
- defeat：独立单体，推荐 **[138,239,1502,451]**，完整头左脚右侧卧，没有邻人或画布裁切。

首批各图的 >127 组件总数与预期人物数完全一致（8 / 4 / 1），未发现额外断开的 >127 剑尖/手脚组件。推荐 rect 保留全部自身 >127 像素，带原有 1/2px 边缘；“完整”定义是本次明确指定的 Alpha 阈值主体，不假装证明每一个极低 Alpha 边缘都已归属。

约 48×72 是人类本次已授权路线，但 **不要把包含长剑的整个 region 强行挤入同一个 48×72 矩形**：renderer 应统一角色身体尺度与鞋底锚点，允许剑的 region 更宽/举剑区域更高，倒地也应沿用同身体尺度。此工具只测源区域，不改变速度、碰撞、判定或正式 manifest。

## 重跑与增量接口

工具 `tools/analyze_hero_source_regions.py` 仅向 stdout 打印 JSON，不自行写文件。使用 bundled Python（Pillow 已就绪），无需 NumPy/SciPy。这里使用代码路径而非评审包链接，不要求将开发用 Python 源码放进 review 或 PCK。默认枚举当前 13 张；`--source` 可重复，提供时只测指定的新文件，方便将结果用 apply_patch 追加到同一 snapshot：

```sh
/Users/witcher/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/analyze_hero_source_regions.py --self-test
/Users/witcher/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/analyze_hero_source_regions.py --source combat_down_first4 docs/art_reference/hero_front_fist_thrust_20261012.png 4 1
```

验证：run-length 8 连通实现与 20 组独立 flood-fill 对照；Alpha=127 排除、Alpha=128 纳入、对角连通、邻人计数、透明隐藏 RGB 不成为主体的合成测试均通过。输入 PNG SHA-256 保存在 JSON；源码没有 image save/crop/resize 或输出图片操作。本轮未生成图、未改正式资源/主记录、未 commit/build/export。
