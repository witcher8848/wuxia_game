# 第七周独立 subagent review

审查日期：2026-10-16。基线提交：`041038d`；修订工作分支：`codex/weeks3-7-review`。本审查由独立子代理完成，先只读，再经主代理授权仅修改 `dialogue_panel.gd` 与 `test_week7_world_ui.gd`。没有提交、推送、构建或运行 GPU 渲染；未改用户存档和原试玩意见。

## 范围与结论

完整阅读《第七周每日任务》、`13_week7_review.md`、`docs/week7_playtest.md` 和 `03_core_gameplay.md` 第八章的正式时间规则；核对 WorldRules、ContentDB、GameSession、WorldPanel、DialoguePanel／SocialDialoguePanel、ExplorationRegion、ActivityPanel／Journal、SaveService 及相关规则／UI／冷重启测试。

发现并修复 **1 项 P2**；未发现已复现的 P0／P1。以下“未发现”仅指本报告列出的代码、场景和验证范围，不宣称没有任何缺陷。正式三日八剧情时段、公共事件、截止失败、自动存档、实时寻路、新地图和第八周分支内容是明示后置边界，不作为第七周漏做项。

## W7-R1 [P2] 反复前置闲谈遮住调查回答与质证引导（已修复）

- 原位置：`game/presentation/investigation/dialogue_panel.gd:86`～`93`；正文区域定义在第35行，高度86像素。
- 复现：到码头交谈，问老妇是否乘船；当前 `D_DOCK`／`D_BOAT` 节点每次刷新都会先放四行“时段、站位、关系、声望”闲谈，再放当前问题的回答。`go_to()` 将滚动条回到顶部。
- 实际：默认视口只看到重复闲谈，关于“三个月未乘船”的证言和如何质证的提示在折叠区；玩家已经问了问题，还需另按 PgDn 才能看到回答。原 Mac 实绘 `docs/week7_evidence/week7_zh_CN_boatman_topic.png` 明确显示此布局。对主角独白节点还会将面板标题改成船夫名字。
- 预期：当前节点的回答／行动说明优先可见，标题保持实际发言人；新增日常对白仍可观察，但不挤掉每次问答的主要内容。
- 修法：保留原节点正文和 speaker；仅当前入口在正文后追加一次、明确署名 NPC 的完整闲谈。非入口 `D_BOAT` 等回答不再重复前置闲谈。H 人情面板仍完整展示真实时间／关系对白。没有扩大正文区域、隐藏正文、删掉调查选项或削弱质证条件。
- 新回归：中英文真实 Main 键盘路径 `E领取索引 → E接受任务 → E询问船夫 → D_BOAT → H → Esc返回`，验证正文优先、NPC闲谈署名、主角／船夫标题、证言回答不重复闲谈、H仍为真实 world_greeting、返回保留原节点和回答。既有 W7 UI 74 项扩展至94项。

## 逐项核对

| 要求／风险 | 本次证据 | 结论 |
|---|---|---|
| 原型时间与正式章程区分 | 每日排期、评审、试玩表及 WorldPanel 文本；当前每天8技术槽 | 边界一致，不冒称正式三日剧情时间线 |
| 查询和预览只读 | WorldRules 候选副本、334项纯规则；Session预览前后全状态比较 | 查询／取消不补写旧空容器、不发奖励 |
| 明示耗时与再次确认 | WorldPanel默认取消；真实键盘94项；独立E echo探针 | 无直接确认误花时段；代价／奖励及封顶说明保留 |
| 伪造／过期／重复token | GameSession全状态快照与候选重算；386项Session验证 | token不复活，变化后拒绝；试武／剧情战斗期间锁定 |
| 不远程或隔墙帮忙 | ContentDB当前地图、距离、安全位置、墙体与其他交互体遮挡；Session复算 | 不能只靠UI提供目标ID直接获奖；普通对话不刷值 |
| 两NPC所有时段真实落点 | 2 NPC ×8槽；284项物理／射线／旧位空出检查 | 画面、碰撞、交互来自同一投影，无旧位幽灵体 |
| 所有落点从入口可达 | 新独立16像素网格BFS，逐边端点／中点检查20×12脚部，最后用正式服务检查交互距离／遮挡 | 2 NPC ×8槽全部具有从原地图入口到可交互位置的连续安全路径；不是仅检查孤立落点 |
| 玩家占住预定NPC落点 | WorldRules先选持久化安全备用anchor；284项真实Region旧档最近安全恢复 | 不让NPC压住玩家；旧档恢复仅移动必要距离 |
| 已知信息与人物页 | INSPECTED知识标记、people只投影已结识者、第三页真实界面测试 | 不显示未遇人物、隐藏信任分值、坐标或完整日程 |
| 关系／声望及每日限制 | 实际help事务、last_help_day、信任／声望范围与每日跨日验证 | 每NPC每天一次、耗1槽；另一NPC的声望对白实际改变 |
| 持续按键与面板输入 | 新探针持续D跨H面板、E echo、H取消、关闭后释放再按；主Main键盘94项 | 面板不漏移动／快存；按住方向不会在关面板后立即滑走 |
| 内容原子注册 | 40项ContentDB测试与world_text双语引用验证 | 坏日程、坐标、缺文本拒绝，旧registry保留 |
| 存读与真正冷重启 | 实际SaveService386项；新独立 writer／reader 360／38项 | 时间、关系、声望、位置和旧空状态跨进程一致；未把同进程往返称冷重启 |
| 旧剧情和调查衔接 | 旧Dialogue822项、Inquiry208项、Onboarding212项；W7实际问答路径 | 旧调查、质证和开篇可继续；当前节点正文优先修复回退 |

## 本次执行命令与结果

除冷重启编排外，以下命令均由 `python3 -B tools/run_checked.py <日志label>` 包裹运行，以同时检查进程返回码和 Godot 脚本错误。日志目录为 `builds/qa/`，不是正式发行包证据。

| 命令主体 | 日志 | 本次结果 |
|---|---|---|
| `./tools/godot.sh --headless --path . --script game/tests/test_world_rules.gd` | `review_week7_rules.log` | 334项，0失败 |
| `./tools/godot.sh --headless --path . --script game/tests/test_week7_content.gd` | `review_week7_content.log` | 40项，0失败 |
| `./tools/godot.sh --headless --path . --script game/tests/test_week7_npc_ui.gd` | `review_week7_npc_ui.log` | 284项，0失败 |
| `./tools/godot.sh --headless --path . --script game/tests/test_week7_world_session.gd` | `review_week7_session.log` | 386项，0失败；同进程服务测试 |
| `./tools/godot.sh --headless --path . --script game/tests/test_week7_world_ui.gd` | `review_week7_ui_fixed.log` | 修复后中英文94项，0失败，无截图 |
| `./tools/godot.sh --headless --path . --script game/tests/test_dialogue.gd` | `review_week7_dialogue.log` | 822项，0失败 |
| `./tools/godot.sh --headless --path . --script game/tests/test_inquiry.gd` | `review_week7_inquiry.log` | 208项，0失败 |
| `./tools/godot.sh --headless --path . --script game/tests/test_onboarding.gd` | `review_week7_onboarding.log` | 212项，0失败 |
| `./tools/godot.sh --headless --path . --script builds/qa/week7_review_probe.gd` | `week7_review_probe_fixed.log` | 新独立路径／held-input探针39项，0失败 |
| `python3 -B tools/check_world_persistence.py` | `week7_world_persistence_write.log`／`read.log` | writer PID47583：360项；退出后启动reader PID47590：38项；RESTART_PASS |

探针首次在 SceneTree 启动前 preload 依赖 autoload 的Region，导致探针自身编译错误；该轮手动终止并保留 `week7_review_probe.log`，不算产品缺陷或通过证据。将脚本加载移至autoloader就绪后并添加90秒watchdog，再得到上表39项通过。临时探针仅存于忽略目录 `builds/qa/`，未加入生产工程。

## 未验项与交接

- 本代理没有重新生成 Mac GPU 截图；原实绘只作为缺陷存在的证据，不用来证明修复后的画面。主代理需统一进行新实绘和全项目回归。
- 本代理没有跑新的PCK或发行包；所有本次Godot测试均 `packed=false`。
- Windows、实体手柄、真人易懂度、文字审美和人物清晰度未验；脚本键盘与自动截图不代签这些项目。
- 第七周独立冷重启已重跑，但其日志会被之后主代理的统一验证更新；应以最终主代理收口记录为准，不混用历史PID和新日志。
- 第六周原PCK和用户原反馈未改写；本次跨周工作未自动进入第八周，也未改变“正式时间轴后置”的决策。
