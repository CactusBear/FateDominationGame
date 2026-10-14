# Round51 候选选择预检与三项 blocker 收敛

## 结论

- 当前候选仍为 `selection_blocked`；`sourcePASS=false`、`releasePASS=false`。
- 当前正式选择：97 个 Godot 场景，其中 headless 95；另有 2 个 native standalone，`program_count=99`。
- 模式计数：`short_headless=89`、`native_integration=1`、`gui_required=2`、`long_correctness=2`、`performance=2`、`known_engine_negative=1`。
- `snapshot_drift=[]`、`godot_launch_count=0`、`business_suites_executed=0`；本次 Python preflight-only 没有启动候选全量。
- 唯一当前 blocker 是命名的 `round50_finished_lobby_tight_test`：明确分类为 `extracted_harness`，不进入正式场景选择，不补造 `res://tight_session.gd`。

## tight extracted_harness 契约

```json
{
  "suite": "round50_finished_lobby_tight_test",
  "kind": "extracted_harness",
  "helper": "tight_session.gd",
  "archive": "tight_session_extracted.gd",
  "runner": "tests/round50_finished_lobby_receipt_runner.py",
  "parent": "scripts/net/session/lobby_session.gd",
  "archive_hash_required": true,
  "counts_as_formal_scene": false
}
```

该命名覆盖仍保留在 additions/blockers 中，避免通过删除名字或放置空 helper 伪造闭合。独立 runner 仍负责从真实生产函数生成确切 helper，并将提取物归档、绑定父源码与 hash；这条 harness 执行契约没有改成正式 `res://` 依赖。

正式真实场景已加入当前选择并绑定原有门：

- `round50_finished_lobby_receipt_test`：16 checks。
- `round47_host_lifecycle_board_test`：14 checks；仍归 `long_correctness`，窗口调用不计 headless PASS。

## 文件改动

- `tools/tests/test_round29_integrated_evidence.py`
  - 增加 tight 的 `extracted_harness` 明确契约与 blocker 投影。
  - 保留 receipt/board 真实场景；登记 16/14 checks。
  - approved 服务场景加入显式输出参数，运行器把批准输出根作为首参数传入。
- `tools/tests/test_round50_candidate_selection.py`
  - 锁定 receipt/board 入选、tight 不入正式场景、父源码与 archive-hash 要求。
- `tests/net_server_data_approval_test.gd`
  - 删除固定仓库外绝对根；首参数优先，缺首参数时消费 `FATE_TEST_SCRATCH_ROOT`。
  - 在首次写入前拒绝缺根、非 E 盘、点段、链接/越界根；storage/provider/card 全部限制在批准根内。
  - 正常路径仍保留原 22 个业务断言。
- `tests/round47_worker_launch_lifecycle_test.gd`
  - 不再推测 `root/engine/`；Windows executable 核对改为实际 `OS.get_executable_path()`，保留精确 argv、父 PID 与完整 39 项 lifecycle 断言。
- `docs/round51-candidate-preflight.md`
  - 本轮选择、阻断、命令和实跑证据。

未创建 `res://tight_session.gd`，未修改生产 Session、其它 tests、native、GUI 或 main gate。

## 实跑与验证

### Godot 正向

- 服务端批准真实场景：
  - `res://tests/server_data_status_inbox_approval_test.tscn`
  - 退出码 0；`RESULT checks=22 failures=[]`；批准 JSON/图片逐字节下载断言通过。
  - 使用显式首参数 `E:/HermesScratch/round51-approval/runtime` 与同根环境变量；非 headless。
- worker lifecycle：
  - `res://tests/round47_worker_launch_lifecycle_test.tscn`
  - 退出码 0；`RESULT round47_worker_launch_lifecycle checks=39 failures=[]`。
  - fresh/restart 两次均核对实际 Windows argv、父 PID、approved clone executable、保存拒绝/成功闭合与旧 binding 隔离。
- worker argv helper：独立 route fixture 真实通过 `22 checks`；`fate_server` 参数分支也真实通过 `22 checks`。

### Godot 负向前置

使用 parent approval scene 验证首次写入前拒绝：

- 缺首参数/无环境根：退出码 2。
- `C:/unsafe-root`：退出码 2。
- E 盘 junction/link 根：退出码 2。

这些是预期安全拒绝，不豁免未知 `ERROR` 门，也不计业务 GREEN。

### Python

- `python -B tools/tests/test_round29_integrated_evidence.py --parser-only`：exit 0。
- `python -B tools/tests/test_round50_candidate_selection.py`：6 tests，exit 0。
- `python -B tools/tests/test_round29_integrated_evidence.py --round50 --preflight-only --approved-root E:/HermesScratch/round51-preflight`：exit 1（预期 blocker）；97/95/99 与上述模式计数一致，`snapshot_drift=[]`，Godot/业务执行均为 0。

曾用旧窄 freeze runner 尝试 worker lifecycle 时，因其裁剪输入造成 `ROOM_DATA_ASSEMBLY_REJECT`、READY 未达成，exit 1；未计 GREEN。随后用当前项目完整实际输入重新运行，得到上面的 39 checks GREEN；没有修改生产代码来掩盖该输入问题。

## 主代理最终一次完整命令

关闭并独立处理 extracted harness blocker、重新核对同一冻结后，才允许执行：

```text
python -B tools/tests/test_round29_integrated_evidence.py --round50 --complete-candidate --approved-root E:/scratch --collect-failures
```

本轮没有执行该命令；不宣称 97 场景、GUI、native standalone 或 release PASS。
