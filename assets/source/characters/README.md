# 主角测试精灵源

`hero_pixel_source.gd`是本周的可编辑像素源：鞋／裤、短衣／交领、手臂／武器、头发／脸、文袋分层按顺序绘制；色板、四向和帧数在文件头声明。不是Aseprite工程，不依赖商业软件；图像由整数坐标与像素行生成，不读取或缩放AI参考图。后续可迁移到图形编辑器，但迁移前以此源为准，不反向修改导出的PNG。

在仓库根目录运行：

```bash
./tools/godot.sh --headless --path . --script res://tools/export_hero_art.gd
./tools/godot.sh --headless --path . --editor --import
./Character.command
```

导出到`assets/runtime/characters/chr_protagonist_atlas.png`和同名JSON。每帧32×48，脚底(16,44)，8列；方向down/left/right/up，方向内walk4、strike2、thrust3、slash3、guard1、hit1；最后down1，共57帧槽。idle引用walk首帧。相同恢复姿态可以有重复像素，不声称57张独立绘画。

walk8FPS、冲刺乘300/180；strike/thrust/slash10FPS；guard3FPS、hit5FPS（避免只有0.1秒难以辨认）；倒地持续。动作时序由元数据读取。侧面文袋只显示角色左侧，不对称镜像。

源与开发工具不进入导出包；JSON与PNG必须一起进入包。测试：`test_character_source.gd`逐帧比对源和导出、色板／透明度／导入参数，`test_character_pipeline.gd`验证运行时与实际受伤／死亡恢复。

2026-10-08脸部反馈修订：正面、侧面、背面分别使用头部模板，暖色脸部形成连续色块；侧面仅镜像头部几何，文袋和持剑手保持解剖侧别。短衣、侧身衣襟、宽袖与松裤分别编辑；行走的腿和脚按相反相位迈步，倒地也落在row43。沿用11色、32×48、57帧槽和既有时序，没有修改碰撞或战斗范围。imagegen候选仅用于外观讨论，本源未读取、裁切或采样候选图片。

`Character.command`中←／→会暂停并前后逐帧，跨动作末帧会循环；空格恢复播放。先在1×检查朝向和脸部，在3×检查像素轮廓与脚底。源回归新增脸部亮色面积／连通性、侧脸一致性和脚部相位检查；这些能防止已知问题回归，但不能自动判断好看或动作自然。

共享表现层另外绘制16×6的固定整数像素椭圆阴影，不写入角色atlas；探索和战斗使用同一阴影几何。战斗插值移动的遮挡顺序按当前显示脚底排序，不按已提交的目标格提前跳层。

2026-10-09独立静态候选源`hero_static_candidate_20261009.gd`只包含正面与左侧，用于造型评审，不参与现有atlas导出器。开发工具`tools/preview_hero_static_candidate.gd`导出原生PNG、1×／3×对比与临时真实场景展示；结果在`docs/art_reference/hero_static_20261009/`，详见[评审记录](../../../docs/hero_static_candidate_review_20261009.md)。候选未经认可前不替换57帧槽或改变动画契约。
