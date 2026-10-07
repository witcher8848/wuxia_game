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
