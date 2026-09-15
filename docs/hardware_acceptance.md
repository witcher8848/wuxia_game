# 外部验收待办

更新：2026-09-14。以下项目尚未通过，保留原 Day 6／第一周门槛。

## GitHub 与远端 CI

本机 Git 推送预检因没有 HTTPS 登录凭据失败；GitHub 连接器可读取仓库，但写入 Git tree 返回 `403 Resource not accessible by integration`。尚未向远端创建本次分支或触发工作流。

开发者在本机完成 GitHub CLI 或 Git HTTPS 登录后，执行：

```bash
git push -u origin codex/week1-foundation
```

不要把 token 发到对话或写入仓库。推送后记录完整提交 SHA、Actions run URL、Linux 校验及 Windows cloud runtime 结果和 artifact 下载验证。云端无头启动与实体设备检查分开计。

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
