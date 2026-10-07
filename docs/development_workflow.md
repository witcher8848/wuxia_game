# 开发与验收流程

> 工程协作与第五周角色测试管线。更新：2026-10-07。

## 1. 每次恢复工作

先读 [README](../README.md)、[第四周每日任务](../武侠RPG_第四周每日任务.md)及未完成的[第三周每日任务](../武侠RPG_第三周每日任务.md)，需要历史证据时查[第二周评审](../08_week2_review.md)、[反馈处理单](./week2_feedback_followup.md)和[第一周评审](../07_week1_review.md)。再检查 `git status --short` 和当前分支，确认未提交修改属于谁。通过 `./tools/godot.sh --version` 检查工具链，运行 `./tools/check_project.sh` 获取当前基线。失败时记录已有问题，不能假定是本次改动造成，也不能覆盖他人的工作来换取干净状态。

第一周的技术／设计冻结不等于整个游戏已制作。第二周的目标是灰盒探索，第三周才进入回合战斗，第四周串起调查与状态闭环。

当前第四周工程及首轮反馈已提交`355ada7`，第五周按[每日计划](../武侠RPG_第五周每日任务.md)推进主角测试资源和动画管线；恢复优先查看[第五周评审](../11_week5_review.md)。第四周第二入口与引导修订体验、首月门仍待复测；自动检查不能替代人工体验。不要根据旧开工记录重复实现已完成的功能，也不据此启动正式地图和NPC量产。

## 2. 分支和提交

- `main` 保持可启动；日常有范围的实现使用 `codex/<工作名>`，例如 `codex/week2-exploration`。
- 同一小任务一组相关提交。前缀使用 `feat`、`fix`、`test`、`docs`、`build`、`chore`，摘要说明具体行为，例如 `feat: add region exit and spawn handling`。
- 暂存时列明文件，不用全仓库暂存把无关内容混入。提交前阅读差异、运行该任务必要的检查，并核对素材来源。
- 需要修改另一位协作者负责的文件时先协调所有权。子代理独立验收应报告具体证据和复现，不替主实现代理伪造通过结果。
- 只有实际创建提交／推送／运行 CI 后才更新对应状态。遇到认证、网络或设备问题保留当前工作和真实日志，不用本地结果冒充远端结果。

仓库忽略 `.godot/`、`.tools/`、`builds/`、本机日志、用户存档和导出凭证。保留 Godot 需要的 `.gd.uid` 和资源导入配置；导入缓存不进入 Git。单文件超过 25 MB 时先评估拆分或 Git LFS，再纳入版本控制。

## 3. 本地验证与构建

常用入口：

| 入口 | 用途 | 成功证据 |
|---|---|---|
| `./Character.command` | 主角四向、所有动作、1×／2×／3×预览 | PNG／JSON驱动，非概念图；风格认可仍待用户 |
| `python3 tools/build_week5_candidate.py` | 独立第五周角色候选 | `WEEK5_CANDIDATE_PASS`、包内角色／剧情／引导／存读审计，独立用户目录；不是Windows真机验收 |
| `./tools/setup_godot.sh` | 下载固定编辑器和 Windows 模板并核验 | 官方文件 SHA-512 匹配，`--version` 与锁定版本一致 |
| `./tools/check_project.sh` | 文档／数据／资源／Godot／状态／UI／探索控制器与内容、流程、完整脚本步行／主场景检查 | 每个子步骤成功并输出 `PROJECT_CHECK_PASS`；检查没有脚本错误文本 |
| `./tools/run.sh --dev` | 图形窗口检查与开发运行 | 主菜单进入小镇，键盘操作、存档、菜单与显示正常 |
| `python3 tools/run_checked.py investigation_rules ./tools/godot.sh --headless --path . --script res://game/tests/test_investigation_rules.gd` | 第四周Day 22数据／状态／服务／隔离存档测试；也纳入全量检查 | `INVESTIGATION_RULES`零失败，无脚本错误；不是对话UI或真实战斗验收 |
| `python3 tools/run_checked.py week2_visual ./tools/godot.sh --path . --script res://game/tests/capture_week2.gd` | 实际渲染、窗口／全屏缩放和灰盒截图 | `WEEK2_VISUAL_PASS`；仍须目视检查与人工试玩，不算 Windows 真机验收 |
| `./tools/build_windows_debug.sh` | 可诊断的 Windows 候选包 | `WINDOWS_BUILD_PASS`、构建元数据和文件校验清单 |
| `./tools/build_windows_release.sh` | Release 候选包 | 同上，且关闭开发入口、排除测试和源资产 |
| `./Battle.command` | 独立完整战斗评审原型 | 移动、行动、敌人AI、胜败／撤离、重试；不写探索档 |
| `python3 tools/build_battle_candidate.py` | 单独的战斗Windows评审候选，不改正常入口 | `BATTLE_CANDIDATE_PASS`；独立用户目录、实际PCK审计／战斗胜利重试、元数据和校验清单；不等于Windows真机通过 |

每项检查保留构建／提交标识、命令、结果与设备。数据和规则用确定性测试；UI、文字和像素比例必须实际渲染检查。2026-09-16 用户决定先验键盘、保留手柄同动作映射；实体手柄实测移至输入完善里程碑，不阻塞第一周／第二周。物理手柄和 Windows 真机实际验收时仍必须登记真实环境，不把模拟事件当成硬件证据。

测试用独立的 `user://tests/` 目录创建和清理自己的文件。正常游戏存档位于 `ProjectWuming/saves/`；故障注入不在玩家真实档位执行。存档相关修复至少回归往返一致性、坏档备份、未来 schema 拒绝和安全文件路径。

## 4. CI 与发布状态

技术规格要求 CI 在 push／PR 检查文档、数据、Godot 导入和测试；主分支生成 Windows Debug artifact，版本标签生成 Release 候选与校验清单。实际触发条件以 `.github/workflows/` 中已落盘的工作流为准；工作流文件存在仍不等于远端运行成功。

首个远端验证必须记录运行 URL、关联提交、各 job 结果及 artifact。未推送时写“未运行”；执行中写“运行中”；失败记录原因，不能取前一次成功 artifact 标注为当前版本。发布商店、上传构建或联系外测者按照对应里程碑和用户授权执行，不由本地检查自动发起。

外部候选包最少记录操作系统、GPU、输入设备、包 SHA、启动、移动、保存、退出重开、读档和全屏。键盘优先的早期版本明确标注手柄未验；首次对外提供手柄支持前增加型号、连接、导航、确认取消和断开后键盘恢复检查，最迟纳入第 19 周输入完善。Windows 10 和 Windows 11 的发行级矩阵应分别完成；本次只调整输入范围，Day 6 的 Windows x64 真机要求仍单列，未自动后移。

## 5. 备份与每周交接

源文件以 Git 提交／远端推送形成版本记录，但 GitHub 不代替另一份磁盘备份。技术规格要求系统级每日备份及每周恢复一份源文件；是否已经启用和实测必须记录，不能把这条约定标为执行完成。玩家档案由存档服务保存上一版备份，恢复结果明确标出来源。

每周结束前生成可运行构建，回填任务实际工时、已完成证据、P0／P1／P2 和下周依赖。周目标有外部条件未满足时，继续完成可验证的工程部分，并在评审中列出缺口；不把“有文档／有 EXE”当作全部验收。

新增功能遵守[范围基线](../06_scope_and_backlog.md)的等量换出规则。手感、剧情好坏和人物取舍由开发者参与判断；代码、状态与打包问题先由自动化和独立审查收集证据。
