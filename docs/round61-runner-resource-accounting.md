# Round61：逐套 runtime 资源归属与保守回收

## 结论与边界

- 已修复 full/未启动套件 continuation 的“全部 fixture 留到最后”接线；8GiB 不变，generic runner 未修改，byte_budget 仍是不可继续的安全失败。
- Python：资源专项 12 tests、candidate 16 tests、完整 parser-only 均真实 exit0。
- 新鲜小 proof：worker_content_environment_test 45 与 net_server_relay_cfg_test 22 均 exit0；relay 本轮只启动一次。资源 proof exit0，sourcePASS=false、releasePASS=false、顶层 candidate passed=false。没有 GUI、DLL/native 构建或旧 98 重跑。
- 实际回收两个 runtime 中已经归档读回的日志副本，合计 **3011 bytes**；不是大体积 Godot fixture 的整批实跑证明。三套累计输入副本超过小配额、修复后仍在原 owner 配额内的根因回归由真实文件系统 Python unit 证明。
- 每套实际 JSON 快照缓存保留在原位置，仍计入同一配额。共享 freeze/engine 与 res:// 生成的配置/room 证据在 proof 中保留。未碰生产存档、旧候选、旧日志、身份或 28100。

## 根因：真实 runner 协议

`tools/run_isolated_godot_test.py:347` 的 execute 使用 Windows Job；循环统计 `tree_bytes(generated.parent)`，不是单个活跃 fixture。125/byte_budget 不代表 relay 自身需要超过 8GiB：已退出套件的 fixture 仍累计在同一 owner 内。

原 full 只在末尾调用 delete_owned(generated, owner)。现有 delete_owned 拒绝任意 f/complete-* 子目录，只允许 `isolated-<32hex>/generated`、逐字 native str(Path) 回执和已退出进程，且先扫描全部 reparse。不能直接按前缀 rmtree 套件目录。

## 解耦与接线

新增函数均在授权的 test_round29_integrated_evidence.py 内：

1. `round61_allocate_runtime`：launch 前预分配 runtime/recycle 两个精确 UUID owner，记录 parent UUID/path、子树 volume/inode、suite/phase/index 与 frozen fingerprint。环境根注入 runtime/generated；两树始终位于原 generated/f 内。
2. `round61_artifact_declared`：提取并复用已有 archive_fixture_artifacts 的日志、result/response、ready/supervisor/recovery/report/manifest、transaction-evidence、round39-final-save、recovery-comparison 声明。旧入口额外 config.json 行为保持原样；新回收入口不读/复制配置、记录或密钥。
3. `round61_protected`：仅给予保留声明，不给予删除许可。records/secrets/keys/credentials/identities、配置/身份/密钥及源码明确的 LoadGame stored_jsons.dat 都保留；不读其内容。
4. `round61_reclaim_runtime`：读取精确 parent receipt，绑定当前唯一 label/command/PID 的 Job0 与日志释放记录；读回冻结输入全 hash map；归档 stdout/stderr、两个原始 ownership receipts 和全部声明 artifact；原字节 hash 读回后才形成删除计划。其余文件只有完整 SHA 与冻结输入一致才视为可再生成副本；未知文件在任何 rename/delete 前停止。
5. 无保留项时调用原 delete_owned(runtime/generated)。有保留项时，仅把已验证可回收文件逐个 rename 到 launch 前已授权的 recycle/generated，再由原 delete_owned 回收这个更小 scope。records/config/keys/cache 不移动。保留文件的 volume/inode/length 再读回；不能把目录缺失当作保存或退出证明。
6. 首次变更前写 recycle-intent；开始变更后的失败标为 recovery_required，不谎称 no deletion。正常结果原字节持久化并读回。未知/存活/坏 archive/缺 receipt/reparse 等变更前拒绝保持 no deletion。
7. full 与 continuation 保留逐套 archive/error 索引；不能因为 runtime 已回收而丢失 worker ERROR。最终父树清理不能绕过 retained/blocked runtime 或 res:// 中的保护文件。小 proof 明确保留共享树。

不复制安全路径验证和删除实现；所有 no_links/contained/tree_bytes/delete_owned 均复用真实 generic runner。没有 prefix 删除，也没有把 records 或生成副本移到预算外。generic 的 owner 总量统计、8GiB/min_free、byte_budget 异常和 collect-failures 安全停止协议保持不变。

## RED → GREEN 与拒绝测试

首次单位复现按旧末尾才清理行为产生三套副本，第三套报 `16417 not less than 14000: exited fixtures accumulated into suite 3 quota`，exit1。实现后绿色；强化后的最终单位按整个 owner（含 archive/receipt）统计，小配额 170000，三套真实 65536-byte 冻结输入副本逐套回收，全部通过。

第一次真实小跑只执行 worker45。其实际 stored_jsons.dat 未有删除许可，回收器正确 blocked_no_deletion，relay 未启动：

`E:/scratch/round61-resource-proof-bf515ce165464c529c37a41df0b0ef48/isolated-aa6bebfa575f4c83bc9dbc12dbeca44a/manifest.json`

随后为已知缓存的“小 scope 保留”新增 unit，真实 RED（undeclared runtime files），再给予保留声明而非读取/删除许可，GREEN。原失败证据没有删除、修改或追认通过。

最终资源专项覆盖：三套累计、archive corruption、Job live、日志未释放、unknown scope、receipt missing、directory identity mismatch、unknown file、frozen drift、真实 Windows junction、known save/private key/原 shutdown response/shared freeze、已知快照缓存保留。拒绝前后复制输入与 report 原字节不变；known save 与密钥仍在原路径。secret/records digest 调用在 unit 中明确禁止。

真实命令：

```text
python -B tools/tests/test_round61_runner_resource_accounting.py
python -B tools/tests/test_round29_integrated_evidence.py --parser-only
python -B tools/tests/test_round50_candidate_selection.py
```

原始输出和逐文件 SHA：
`E:/scratch/round61-resource-proof-486a085c8e55481eb659d22b62f13990/python-verification/results.json`

## 两场景实际 proof

```text
python -B tools/tests/test_round29_integrated_evidence.py --round50 --resource-proof-two-scenes --approved-root E:/scratch/round61-resource-proof-486a085c8e55481eb659d22b62f13990
```

- manifest：`E:/scratch/round61-resource-proof-486a085c8e55481eb659d22b62f13990/isolated-4c99f2d34a8648169e9acb80e4e053ba/manifest.json`
- manifest SHA-256：`158e65ae2a0bd45a5dddbab95886aa8429e0aabcab99b1323d4a76160362f6d5`
- 独立读回：同 owner 的 `verification-readback.json`。
- 1795 冻结输入；test 输入仅两场景及六个真实依赖，不冻结/冒认整个 98-suite 测试树稳定。
- cold import exit0、main/worker 路径 probe exit0；worker45 exit0，回收 1215 bytes；relay22 exit0/22 CHECK，回收 1796 bytes。
- 两套均 retained_protected，各保留 373328-byte stored_jsons.dat；volume/inode/length 读回一致，无内容读取。回收结果与原 JSON 文件读回相等。
- 所有 own Job active 合计 0，所有进程 exit0，所有日志句柄释放；额外只读进程查询无该两次 proof 根的存活 executable。
- archive SHA 无不一致；冻结输入、源引擎和执行器 hash 读回一致；worker ERROR=[]；excluded test changes/additions=[]。
- 当次 owner 占用 1066899851 bytes，预算仍为 8589934592 bytes。日志归档有持久证据开销；3011 是 runtime 副本回收字节，不能冒称同额磁盘净释放。
- resource_proof_passed=true。candidate passed=false 的原因 cleanup_not_verified 是明确保留共享树，不作为 sourcePASS/releasePASS。

## 第二个独立 worker ERROR：仍 blocked

亲读当前 `tests/room_data_preparation_dependencies_test.gd`：第55–57行只选择 surveil 单卡；第103–109行证明真实隔离组装内容并断言完整数据被拒绝。它并未声明“可以打印无法读取 masters/servants 的 ERROR”。

当前 worker 第53–65行组装 validation-data 后进入 _inspect_loaded_content；第129–136行安装内容环境并调用 LoadGame.reload_game，随后报告空阵容。load_game.gd 第180–198行对 roster scan 失败分别 push_error。这解释了错误来源，不构成 ERROR 许可。

已有 round42 scope 绑定旧三份固定 source hash、旧 worker 第127/61行回溯及原 manifest/report/Job 结构；当前 worker reload 位于第131行。只替换 hash/行号、接受文字 trace、或通用忽略这两条 ERROR 均不合法。本轮没有扩 whitelist，没有修改 production 或游戏 tests。

candidate unit 从旧98真实 worker error 读取原字节：基础错误仍无法获得 scope；追加 unexpected extra ERROR 后仍 RED，严格 analyze 也 RED；旧 manifest hash 前后相同。建议交给唯一 production consumer owner：在 validation worker 的加载边界对已批准但缺失 roster 目录的输入返回精确结构化负向 report，正确恢复环境，不让预期数据拒绝落入会 push_error 的通用 loader。需独立真实专项证明正常 roster、缺失 roster、其他额外 ERROR 的分支；本代理未实施该修复。

## Shutdown 原字节与不可恢复风险

原 full 只归档 report/manifest/log，未保存已有声明的 response/result/事务/保存证据。新入口保留批准范围内 response 原字节及 raw SHA；可展示投影严格限 ok/room/pid/instance/authority_host_mode/request_id 与 result 的 closing/saved/released/exited 布尔值。projection 明确不是可恢复原文，不读/dump secret 文件，也不全面复制 records/configkeys。

unit 已证明 CRLF 原 shutdown.response.json 精确保留及保存证据保留。此次两场景不是 shutdown 行为专项，不能声称当前正式 shutdown 保存退出链已验证。旧98已删掉、且没有归档的 response 原字节无法从 RESULT/文字日志/hash 重建；没有伪造旧证据或修改旧 manifest。

## 尚未覆盖

- 未执行新 full98、未真实运行 continuation；只验证 parser/candidate 契约与两场景 resource proof。
- 不声称所有生产者的生成文件已具有可删除声明；未知文件仍安全 block，不能为追求 full PASS 推断来源或扩删除许可。
- shared res:// runtime 与 records/配置保留仍占预算；额外同等范围授权及完整归档前不得总树清理。
- 沿用现有 runner 的路径验证/rmtree 协议，不宣称新增原生句柄级抗外部替换能力。

修改文件仅：两个授权 Python 文件、新 test_round61_runner_resource_accounting.py、本说明；无 git add/commit。
