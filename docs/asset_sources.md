# 第三方素材与依赖来源登记

> 建立：2026-09-13；更新：2026-10-07。记录实际状态；“已选型”不等于“文件已引入”或“可发布”。

每个外部代码依赖、字体、图片、音效、音乐或参考图都要有来源。正式素材引入时补全固定版本／原下载链接、原始许可证路径、必要凭证、文件路径和修改说明。生成内容另见 [AI 内容登记](./ai_content_register.md)。

| ID | 名称／作者 | 来源与许可证 | 用途 | 文件／版本与引入状态 | 修改与发布要求 |
|---|---|---|---|---|---|
| REF-AI-HERO-W5 | 主角四向比例参考／imagegen | 本项目文字规范，内置生成＋一次编辑，无外部图像；详见[记录](./art_reference/protagonist_week5_prompt.md) | 内部参考 | `docs/art_reference/protagonist_turnaround_week5.png`，未进包 | 原样复制；不声称获用户认可或可直接作生产精灵 |
| HERO-PIXEL-W5 | 主角测试图集／Codex辅助代码源 | 本项目独立整数像素源，无第三方像素输入；AI-ART-021 | 内部候选探索／战斗 | `assets/source/characters/hero_pixel_source.gd` → `assets/runtime/characters/chr_protagonist_atlas.png`及JSON | 工程验证与正式美术／发行审核分离，不缩放生成参考图；后续改源再导出 |
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
