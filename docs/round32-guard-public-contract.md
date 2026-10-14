# Round32 — guard 测试公开事务契约

## 结果

- 真实仓库 gate：修前 exit=1，83 findings / 80 allowlist，NEW 为 `tests/host_guard_inbox_contract_test.gd:60/71/75 -> EffectManager._guard_transactions`；修后 exit=0，**80 findings / 80 allowlist，NEW=0、STALE=0**，layer=7、private=73。未修改 gate 或 allowlist。
- 最终专项 **72 checks**，其余六套 guard 恢复回归同冻结通过；共 **292 条真实 CHECK / 292 声明 checks**，所有 exit=0、failures=[]，无 SCRIPT ERROR/ERROR。
- 最终冻结上四个真实负向变异均 exit=1，失败 CHECK 与 RESULT 一致；完整恢复失败保留、预算闭锁、非 owner 旧 seq 优先门均有效，回滚前的观察器失败未被 skip 回滚清零。
- 本轮仅修改 `tests/host_guard_inbox_contract_test.gd`，场景 `.tscn` 未改；新增本报告。生产、其他 tests、共享 runner、gate、allowlist 均只读，无 Git 提交或暂存。

## 修改前中文耦合审查及 V4A 详释

原测试为故障注入直接访问 EffectManager 的私有事务表。已有公开 `capture_transaction_state()` / `restore_transaction_state()` 返回及恢复真实进程内令牌，保存原检查点引用身份，足以完成同样的故障注入，不需要扩生产接口、反射或手工重建 guard 结构。

1. 原检查点取自公开捕获令牌的 `transaction_bindings[effect]`。令牌由生产 API 生成；没有手写替身字典、复制内部 guard 布局或字符串读取私有成员。
2. 保留真实 ready 检查点随机状态损坏，再走原 `host.request("guard_skip",...)`；原暂停/已变魔力/完整检查点错误/无成功记录断言全部保留，追加公开 `can_rollback_runtime_guard()` 证明 ready 但恢复失败不是预算不可用。
3. 继续创建真实 EffectCheckpoint，设公开 `max_capture_values=0` 并执行 `capture([effect])`，必须实际失败且报预算。另捕获真实令牌，只替换该令牌的当前效果绑定，经公开 restore 安装；原断言追加安装成功、不可回滚及根身份一致，仍走真正房主 skip 请求验证闭锁。
4. 用最初的完整令牌恢复现场；原“所有失败不写管理成功记录”断言同时验证 restore 返回值、公开可回滚状态以及原检查点身份，随后继续继承的完整恢复/重开/大厅链。
5. 未减少 check 调用或放宽原条件，正常路径仍72 checks。真实 ENet 非 owner 旧 seq 断言、RSA、生命周期门、资源/随机/双方父子回滚和成功审计全部保留。
6. 负向预算试验揭示连续请求的旧 `host.error` 会残留：把 skip 的拒绝改成伪成功时，旧“完整检查点”错误仍能令闭锁断言误判，虽成功日志断言仍使套件 RED。于是仅在两次故障 skip 前清空 `host.error`，确保断言观察本次响应。最终负向试验已直接命中预算闭锁断言，不靠别的失败代替。
7. 所有改动事前中文详释，使用 V4A 锚定补丁；未新增 operation，也未将公开令牌替换为自行复制的内部结构。

## 真实 RED/GREEN

最终四个变异只写独占 E 冻结副本，每次 finally 按原始字节恢复，并保存恢复 SHA256 回执。此处 RED 是真实 Godot 业务断言失败，不是解析错误、超时或合成输出。

| 最终冻结执行 | checks / exit | 精确命中 |
|---|---:|---|
| green-current-error | 72 / 0 | 全部通过 |
| red-ready-partial-restore-final | 49 / 1 | 去掉随机恢复前置整数校验，部分恢复后拒绝：完整 ready 恢复失败必须保留暂停及已变资源 |
| red-budget-false-success-current-error | 49 / 1 | 将不可回滚 skip 拒绝改为伪成功：预算闭锁及无管理成功记录均失败 |
| red-old-seq-owner-order | 49 / 1 | 对 guard_skip 绕过旧 seq 门：真实 ENet 非 owner 旧 seq 优先断言失败 |
| red-observer-rollback-retains-failure | 50 / 1 | 回滚前故意 check(false)，随后真实 skip 恢复资源/随机；该失败仍保留至最终 RESULT |

RED 因继承夹具的真实阶段保护提前结束，所以不要求72 checks；逐条 CHECK 与 RESULT 声明数仍完全一致。所有最终 RED 的 stderr 空、无引擎错误。早期72-check GREEN、首次 ready RED、暴露旧错误的预算 RED也另存，未覆写为最终通过记录；它们不计入最终回归。

## 同冻结最终 guard 恢复回归

| suite | 真实 CHECK / 声明 checks | exit |
|---|---:|---:|
| host_guard_inbox_contract_test | 72 / 72 | 0 |
| net_runtime_guard_test | 34 / 34 | 0 |
| net_guard_rollback_test | 39 / 39 | 0 |
| rule_guard_root_transaction_v2_test | 58 / 58 | 0 |
| rule_guard_rollback_test | 18 / 18 | 0 |
| rule_guard_chain_rollback_test | 17 / 17 | 0 |
| rule_guard_continuation_occurrence_test | 54 / 54 | 0 |
| 合计 | **292 / 292** | 全部0 |

七套运行前核对最终冻结全部清单。冻结2062文件，只复制 scripts/assets/data/addons、project/icon及追踪出的具体测试依赖，不复制历史 tests 全目录、reports、源 .godot。开发 MCP autoload/plugin 与缺失编辑器 GitPlugin 只在独占 project.godot 关闭；原 application、20线程配置及生产 project.godot 不变。

## E 盘、命令、PID、证据和回收

独占根：`E:/Fate-round32-guard-public-contract/`。执行脚本 `verify.py` 复用只读共享 runner 的 Windows OwnedJob/execute/analyze；显式 APPDATA、LOCALAPPDATA、TEMP、TMP、TMPDIR 均在本轮 generated 内，不修改全局环境。

真实主 PID=5528、子探针 PID=9468，物理 user 路径均为：

`E:/Fate-round32-guard-public-contract/generated/appdata/FateDomination`

真实执行形式：

```
python E:/Fate-round32-guard-public-contract/verify.py prepare
python E:/Fate-round32-guard-public-contract/verify.py scene green-current-error host_guard_inbox_contract_test
python E:/Fate-round32-guard-public-contract/verify.py mutant ready
python E:/Fate-round32-guard-public-contract/verify.py mutant budget
python E:/Fate-round32-guard-public-contract/verify.py mutant seq
python E:/Fate-round32-guard-public-contract/verify.py mutant observer
python E:/Fate-round32-guard-public-contract/verify.py final
python tools/check_layer_deps.py --root E:/Projects/Godot/FateDominationGame-master --json
python E:/Fate-round32-guard-public-contract/verify.py cleanup
```

每套引擎实际命令、PID、退出码、时长及句柄释放回执位于 `<label>.processes.json`；完整 stdout/stderr 位于 `evidence/`。引擎形式为：

```
E:/Fate-round32-guard-public-contract/generated/engine/Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path E:/Fate-round32-guard-public-contract/generated/project --scene res://tests/<suite>.tscn
```

每进程180s看门狗，只拥有独立 Job 的 PID 树；全部17次主执行记录已证明 ActiveProcesses=0、退出及日志句柄释放，未按进程名终止他人进程。主/子 user 回执、原引擎/副本 SHA256、最终2062项冻结manifest、逐套日志哈希、mutation/restored、聚合及修前修后gate输出均保留。

`cleanup.json` 证明已回收 generated，包括引擎副本、冻结工程、import缓存、临时目录和user数据，共900613886 bytes；generated 不存在，未回收他人目录或正式用户数据。证据和脚本留在独占根。

## 问题与未伪报边界

- 首次预算变异锚点因 CRLF 未匹配，未启动 Godot；只修验收脚本匹配时换行归一化，恢复仍使用原始字节。随后真实预算 RED/GREEN 有效。
- 验收结束将真实仓库与冻结哈希比较，检测到另一写入者改变 `scripts/match/view_mirror.gd`；本代理未碰该文件，`source-readback.json` 已记录。七套通过属于统一冻结，不冒充并行变更后的整仓冻结验收；自有测试 gd/tscn 均与验收冻结一致，最终 gate 是真实当前仓库扫描。
- 整仓 `git diff --check` exit=2，指出已有共享 `scripts/system/global/climax_resolver.gd:60` EOF空行；该文件不属于本轮，不越权清理。自有测试diff已留 `owned-test.diff`。
- 无窗口、跨网、多机、专用 authority worker 及发行包验收；user子探针不是正式worker整链。本次仅真实 headless 规则及同进程 ENet/RSA 契约回归。
- tests 被项目gitignore忽略，文件实际落盘并运行，未擅自 git add。观察器技能补充“连续故障请求清旧错误并用负向成功回执验证”的通用教训。

## 自有源码 SHA256

- `tests/host_guard_inbox_contract_test.gd`：`e6e4f50cea6d46b2c39b1ecf6677196055f9655c0b9d53f57dc208f0a5d3bc0c`
- `.tscn` 哈希见 `source-readback.json` 与最终 `freeze-manifest.json`；场景未修改。
