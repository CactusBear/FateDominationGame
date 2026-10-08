# 测试发现与验收前置审计

## 范围与结论

仅新增本目录工具、单测和盘点报告。没有运行/终止 Godot、没有修改生产、测试源码、凭证、`.gitignore` 或技能，也没有 commit。以下全部是**静态检查或 Python 工具验证，不是游戏运行通过**。

最终扫描快照：337 个 `tests/*_test.tscn`，其中 75 个已跟踪、262 个未跟踪；递归源码 `.gd/.tscn` 共 726 个，其中 540 个未跟踪源码被忽略。并行代理写入期间最早一次扫描为 336 套，最终为 337 套，因此该快照不能当冻结验收基线；正式验收前必须等所有写入者退出再重扫。

## 发现

### 1. Git 可见性与磁盘发现

- `.gitignore:47` 的 `/tests/` 明确忽略整个测试目录（注释连测试源码一起排除）；已跟踪文件仍然由 Git 管理，不能声称所有测试都消失。
- 现有跑批器实际上用磁盘 `glob('*_test.tscn')`，所以本机仍能发现未跟踪套件，但其他检出/CI 不会自动获得这 262 个场景。Git 搜索、默认状态和增量发现也可能遗漏它们。
- 本工具采用磁盘发现，并独立读取 Git index 和 NUL 分隔 `check-ignore --stdin -z`，避免 Windows 文本 stdin 的 CRLF 被当成文件名尾部而误报“全部忽略”。
- 建议主代理获准后分离源码与输出忽略策略；不能只在 `/tests/` 后加 `!*.gd`，因为父目录已排除。应移除整目录忽略，或逐层重新纳入目录，再精确忽略 `tests/runtime_reports` 等输出。本轮不调整规则、不强制添加文件。

### 2. 场景路径与启动入口

- 当前快照所有 337 个套件直接场景资源路径存在；场景脚本及 `extends "res://..."` 继承链能找到 `_ready/_initialize`、RESULT、quit 的文本线索。**这不证明脚本解析成功、入口接线实际执行或依赖完整。**
- 工具识别 `ext_resource` 属性顺序差异；`servant_skill_eight_magic_test.tscn` 将 path 写在 type 前，不能使用固定属性顺序正则，否则会误报缺入口。
- 只覆盖直接场景 `res://` 资源与字符串式继承，不执行 Godot 解析、不追全部 preload/load、不解析类名继承/动态路径；`entry_hint` 是文本线索，不是控制流证明。

### 3. 窗口是否真正执行

- 35 套有 `OS.get_cmdline_user_args().has("window")` 线索，137 套有 DisplayServer 条件线索（两组重叠，不可相加）。逐套清单和**未执行**命令见 `inventory.json`。
- `match_driver_window_test` 通过 DisplayServer 判定；headless 分支输出 `checks=0 failures=[] window_only=true` 并退出，只是跳过。它继承 `match_driver_headless_test` 的启动与看门狗。
- `net_p2p_lobby_window_test` 明确要求 `-- window`，仅去掉 `--headless` 仍会静默跳过；工具沿继承链生成该用户参数。
- 现有跑批器固定 headless，没有窗口参数接口，且把上述跳过当正常绿结果；只能做 headless 基础批次，不能据此报告窗口验收。
- 真正窗口验收必须保留实际 argv、场景、源码快照、开始/结束时间、原始退出码和完整日志；确认没有 skip，并对比同版本窗口/headless checks 与明确分支标记。日志工具始终返回 `window_execution=UNPROVEN`，不靠无错误或 checks 大于零推断窗口执行。真实输入与截图目视是后续独立要求。

### 4. 输出目录与 E 盘

- `E:/Projects/Godot/FateDomination/test` 实际存在；`C:/Users/Administrator/AppData/Roaming/FateDomination` 经 `is_junction()` 和 `resolve()` 确认为指向该 E 盘目录的联接。本轮没有创建/修复联接、没有写入或读取存档内容。
- `tests/runtime_reports` 存在，根 `runtime_reports` 不存在；当前套件/继承源码扫描发现的报告路径均为前者，没有直接引用后者。不能因为技能历史文案提到根目录就重新创建输出路径；用实际源码决定。
- 本轮没有可对账的新 Godot 运行日志。检查根 `regression_out*/summary.json`、scratch 下 summary、上述两个现存目录顶层日志均未取得运行证据；并未穷举所有历史日志目录，不能推断“历史从未运行”。

### 5. 看门狗与超时

- 仅 13 个套件继承链有 watchdog/time_limit/timeout_guard 文本线索，剩余没有此线索；不是严格看门狗覆盖率，命名不同或其他逻辑可能漏报。
- 已实际阅读的 `match_driver_headless_test.gd:10-17` 从 `_ready` 调用 `_watchdog()`，180 秒后添加失败并 finish；该链适用于窗口子类。解析失败时 `_ready` 不执行，看门狗也无效。
- 外部墙钟超时仍必须保留；普通 120 秒预算早于上述内部 180 秒，可能先拿到 TIMEOUT 而非 watchdog RESULT。不能盲目加预算：先看完整进度日志、历史耗时和当前阶段。
- 现有 runner 默认 `kill_strays()` 按 `taskkill -IM` 杀同名所有 Godot，违反只清自己 PID 的约束。未来运行必须 `--no-kill`，超时后仅清本次所属 PID/子进程树。本轮没有启动或清任何进程。

### 6. 退出码 / RESULT / SCRIPT ERROR

实际审阅了仓库 `skills/fate-domination-engine/scripts/run_all_tests.py`（与已加载技能脚本同类实现）：

- `FAIL_RE` 只认 `failures=[...]`，遇到真实源码 `ask_player_option_test.gd:80` 的 `failures=%d` 或 `failures=N [...]` 会匹配失败，然后写成 `[]`；本轮用它的实际正则在 Python 执行证实 `failures=2 [a,b]` 匹配为 None，能导致假绿。
- 只采用最后一个 RESULT，可能吞掉先前失败；未知格式也默认空 failures。skip 字段不参与判定，零 checks 跳过可算绿。错误是独立证据，不能拿 RESULT 替代。
- 新日志对账函数兼容 JSON 和文本数组/整数，保存全部 RESULT；任一失败、非零退出/超时或错误行为 FAIL，未知/缺 RESULT 为 INCOMPLETE，显式跳过为 SKIP。所有证据干净也仅称 `LOG_CLEAN_NOT_RUNTIME_VERIFIED`，不报告游戏或窗口通过。checks 缺失保持 null，不编造总数。
- 错误不做自动白名单；故意触发错误的反例须由主代理逐条定位并独立注明。计数为匹配的日志行数，不是唯一异常数量。

## 工具与已执行验证

```bash
python scratch/test-harness-audit/test_preflight.py
python scratch/test-harness-audit/preflight.py
# 仅解析现有真实日志；退出码必须是 Godot 原始退出码，不是 grep/tee 的退出码：
python scratch/test-harness-audit/preflight.py --log <完整日志> --exit-code <0或1或TIMEOUT>
```

- 首次单测因工具尚未创建明确失败；numeric failure 实现后通过。
- 场景资源属性顺序回归用例先复现失败，再修复后通过。
- 最终 `unittest` 实际返回 0：3 个测试方法，其中日志矩阵包含 14 个子用例，另外覆盖数字失败与实际场景属性顺序。用例里的日志均是明确的单测输入，**不是伪造游戏运行证据**。
- 最终静态扫描实际返回 0，`blocking_static=[]`，E 盘联接匹配；0 仅表示当前实现的静态阻塞项未发现，不表示允许现在并行启动 Godot。
- console exe 在指定 D 盘路径存在，但未启动。
- 输出参数仅能写本工具目录；默认写 `inventory.json`。日志模式不写生产/日志文件。

## 主代理接手门槛（尚未执行）

1. 所有写入代理结束，核对各生产 diff 与 scratch 交接后冻结源码；重跑本工具，确认套件集合没有丢失。
2. 获准后处理 tests 源码版本管理策略，以及 runner 的失败数解析、skip 判定、默认全局杀进程问题。
3. 单执行者串行运行受影响专项，使用实际 console 路径、`--fixed-fps 60 --path ... --scene res://tests/...`；窗口条件根据清单使用非 headless 与必要的 `-- window`。性能测试不套固定帧率模板。
4. 每套分别保存 argv、原退出码、完整 RESULT/错误/skip；窗口分支证据不足保持未验收。超时只清己方 PID，不动用户编辑器。

## 可复用教训（供主代理合并技能）

- Windows Git stdin 批量路径用 NUL 二进制模式，避免 CRLF 成为路径的一部分。
- TSCN 资源属性按键解析，不依赖 path/type 顺序。
- 未识别 failures 不可默认为空；skip/无 RESULT 不可算通过，窗口参数只证明意图不证明分支执行。
- 静态检查和历史日志无权替代冻结后的实际游戏验收。
