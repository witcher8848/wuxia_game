# 外部验收待办

更新：2026-09-15。GitHub 推送与首次远端 CI 已通过；其余未完成项目保留原 Day 6／第一周门槛。

## GitHub 与远端 CI（首次运行通过）

2026-09-15，本机 GitHub CLI 登录生效，已通过 Git 推送 `codex/week1-foundation` 和日期标签 `week1-local-2026-09-15`。二者的首轮验证对象均为 `ccad9fd8c4d1074dfcc0598681ea989c705e739f`，没有修改 `main`。此前缺 HTTPS 凭据／连接器写入 403 是历史阻塞，不再代表本机当前推送状态。

- [分支运行 34981898201](https://github.com/witcher8848/wuxia_game/actions/runs/34981898201)：Linux 检查、Debug 导出、artifact 上传与 Windows 云端启动通过；Release 两步骤按非标签条件跳过。
- [标签运行 34981897065](https://github.com/witcher8848/wuxia_game/actions/runs/34981897065)：Linux 检查、Debug／Release 导出、artifact 上传与两包 Windows 云端启动通过。

当次 artifact 下载、元数据／校验清单和日志的独立核对结果见 [独立验收报告](./week1_independent_audit.md)。后续提交继续以对应运行和产物验证，不复用旧绿色状态。无需再为本次推送提供 token；任何凭据都不应发到对话或写入仓库。云端运行使用 `--headless --quit-after 10`，仅证明导出的程序可启动并退出，不覆盖以下实体设备项目。

## Windows x64 与实体手柄

将整个构建目录复制到 Windows 电脑，保持 EXE／PCK 相邻。先登记日期、操作者、Windows 版本、CPU／GPU、手柄型号与连接方式、build_info.json、EXE／PCK 的 SHA-256，再逐项操作：

- [ ] 无 Godot、无 Steam 客户端也可启动。
- [ ] 进入庭院，中文无缺字，1280×720 下像素清楚。
- [ ] WASD／方向键移动，Enter／E／Esc 导航与确认取消正常。
- [ ] 实体手柄十字键／摇杆移动，A／B／Menu 导航正常，无持续漂移。
- [ ] F5 或菜单保存，文件位于 `%APPDATA%\ProjectWuming\saves\quick.sav`。
- [ ] 退出并重开 EXE，读取快速档，位置与状态恢复。
- [ ] 窗口与全屏切换正常，焦点仍可操作。
- [ ] 断开手柄后自动暂停，键盘仍可继续。
- [ ] 正常退出，无错误日志。

失败项记录操作顺序、日志与截图；不能先填勾再安排测试。

## 系统备份与卖点理解

`tmutil destinationinfo` 返回 `No destinations configured`。需要选择备份磁盘或既有备份方案，启用每日备份后恢复一个源文件到独立目录，比对哈希并记录结果。本机 Git 提交／bundle 可以用于版本恢复和转移，但同一磁盘上的副本不满足独立备份要求。

请一名未参与项目的人阅读 README 第一段 30 秒，再复述“我扮演谁、主要做什么、与普通武侠游戏有什么区别”，记录原话。作者或 AI 自评不替代外部理解测试；试玩时长与资产制作速度留在对应原型／内容里程碑实测。
