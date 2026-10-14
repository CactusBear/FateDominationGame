# 有界回归调度器：交接契约与正确性证据

本模块已实现，不是设计占位。默认 serial；只有 caller 显式选择 jobs=2/4 才增加容量，未声明 known_parallel 的任务仍为全局串行屏障。不做场景/规则/no_dependencies 推断。用户取消测速后仅运行一次双任务 Godot 正确性冒烟；未运行串行/并行对照、4-way、GUI 或全量。

## 稳定公开 API

文件 `tools/tests/regression_parallel_scheduler.py` 顶部 docstring 是可直接使用的契约：

```python
Resources(cpu: int, memory: int, disk: int)
Task(key: str, resources: Resources, known_parallel=False,
     exclusive_keys=frozenset(), exclusive=False)
run(tasks, launch, *, budget: Resources, jobs=1,
    cancelled=lambda: False, monitor=lambda: None, interval=0.05) -> dict
```

- 资源值均为正整数、caller 显式提供；memory/disk 使用字节，cpu 是 caller 统一定义的预算单位。
- `launch(task)` 返回 handle；`poll()` 表示根和派生进程都结束；`cancel()` 同步 own-only 停止；`finish()` 返回至少 `passed: bool, job0: bool`。launch 抛错前必须同步收尾自己已经创建的进程。finish 不得在活体 Job 上归档或删除。
- 所有回调与结果汇总均在同一调用线程。结果按输入计划排序，不按完成顺序覆盖；每个 task.key 唯一。
- 业务失败 collect；launch/poll/finish/monitor 异常、Job0 未证实、全局预算失败、用户取消均阻止后续 launch。第一阶段错误与后续错误保留在 `errors`/结果中。
- `cancelled()` 每轮和每个 launch 前复查；一旦为真，不再 launch，active handle 均调用 cancel/finish，剩余任务记 notrun。
- `monitor() -> None | str` 每轮和每个 launch 前调用。caller 必须监控 **fixed 输入 + retained 输入 + 已完成证据 + 活动生成树** 的总用量，超量返回原因。资源 reservation 只做 admission，不是假装 OS 磁盘配额。
- 总预算只有一份；活动 reservations 求和，不能每 job 发 8GiB。原 owner 8GiB 包络须扣除 fixed/retained 成本再分配活动份额；实际 aggregate 超额仍由 monitor 拒绝。
- GUI、性能门、真实 long recovery、native 锁 helper 的 `exclusive=True` 必须保持，直到有专项实证。共享互斥资源通过 `exclusive_keys` 声明；同 key 不重叠，不绕过 FIFO 独占屏障。
- `accounted` 严格检查 `expected = executed ⊎ notrun`，以及 results keys=executed；launch 尝试即属于 executed，即使启动抛错。

## 给整合 owner e300aece 的精确接入位置

不在本交付中修改 `test_round29_integrated_evidence.py`。其 `run_round50_full()` 中现有 phase/suite loop（锚点 `output=round61_allocate_runtime(...)` 到 `round43_continue_after(...)`）由整合 owner 接线：

1. 入口增加显式 `--jobs`，choices=(1,2,4)，default=1；jobs=1 保留已有 serial 路径及原失败政策。prerequisite 保持 serial barrier。
2. 由 caller 显式能力声明构造 `Task(phase+'-'+name, reservation, known_parallel=..., exclusive_keys=..., exclusive=...)`。不得从 selection 的 no_dependencies 或 suite 名字推测安全性；特殊阶段独占来自现有明确类别/声明。
3. 将每套独立 freeze、APPDATA/LOCALAPPDATA/TMP/TEMP/TMPDIR、fixture 输出及 OS-bind 合法端口交给 launch adapter；不要向线程池提交现有共享 target 的 blocking `runner.execute`。可参考 smoke 文件的 `OwnedProcess`，但 **不可拿 smoke 的精简 project 配置替代整合工程**。
4. handle.finish 继续调用现有 `round71_analyze_suite(...)`、原资源回收/产物归档函数；scheduler 不解析 RESULT。manifest 修改集中在 caller 同线程回调中。原 `round43_continue_after` 的额外安全门由 adapter/monitor 转成 stop，不删除或放宽。
5. `budget=Resources(explicit_cpu, explicit_memory, runtime_bytes)`；monitor 按现有 `aggregate_charged_bytes = tree_bytes(owner)+retained_input_bytes` 的语义收费，包括已结束日志。真实 CPU/memory 上限由 caller 的 ProcessJob/监控约束，不把 reservation 当实测占用。
6. 将 `report['results']` 回写原 suite 表；保留 report expected/executed/notrun/accounted 和 errors，并维持最终整合认证/源码漂移/owner 清理门。不以“已调度完”替代原 full 验收。

caller 必须提供上述能力声明、资源额度、owned launch/finish、aggregate monitor、cancel signal。scheduler 不再扩成资源推断/管理框架。共享只读输入若没有明确发布 hash 和真实写权限边界，就独立 copy；任何可写树都不得 hardlink。端口 suite 必须用其合法 OS-bind fixture；本次 journal smoke 不使用端口。

## 已执行正确性证据

### Python unit / Windows owned cancellation

```bash
PARALLEL_TEST_ROOT=E:/scratch python -B -m unittest discover -s tools/tests -p test_regression_parallel_scheduler.py -v
```

fakejobs 明确标注，不作为 Godot 或性能证据。最终 **13 项全部通过，退出码 0**，含真实 Windows 取消测试。覆盖 default/2/4 容量、unknown/exclusive/key barriers、三种总预算 admission、aggregate stop、最后完成证据总预算复核、collect failures、Job0 拒绝、回调异常及 finish 抛错后 own-only stop/retry、计划对账、非法声明、partial stdout 原错日志归档。真实 Windows 取消夹具使用两个 Python 根各派生一个 child，确认各自 E cwd/环境、Job0、日志句柄释放、两项 queued 未 launch，父 cwd/os.environ 不变；不是游戏行为替身。

### 一次双任务已有 Godot 场景冒烟

```bash
python -B tools/tests/regression_parallel_smoke.py --project E:/Projects/Godot/FateDominationGame-master --root E:/scratch --godot E:/scratch/round51-engine/Godot_v4.7.2-stable_win64.exe --jobs 2 --cpu 12 --memory-bytes 2147483648 --max-bytes 8589934592 --case-cpu 6 --case-memory-bytes 1073741824 --case-max-bytes 536870912 --min-free-bytes 1073741824 --timeout 60 --outer-timeout 240
```

回执：`E:/scratch/isolated-8b069d0799fd47b697a53ed09fd0637c/manifest.json`。

- 两个独立 copy 的已有 `tests/match_journal_test.tscn`，各 checks=9、failures=[]、exit=0，内外 Job0，全部日志句柄释放。
- expected/executed 均为 journal-A、journal-B；notrun=[]；accounted=true；passed=true。
- 同 hash 的显式依赖清单与每套独立引擎/generic 副本；没有 hardlink、共享可写项目、父进程 cwd/环境变更。冷导入由原 runner 各自完成。
- standalone smoke 仅保留原 application/threading，去掉缺省 main_scene/icon，其他配置不带入；不是完整游戏候选认证。没有修改项目 scene 或生产 GD，也没改变旧 DLL/worker pool。
- main/worker 探针两套各报告 worker_pool_max_threads=20；原 runner 仍独占 RESULT 判定。
- 冻结 generic SHA256：`a048b2291ab5d0548501489cb3dd7b701b2e0f89c75480804b185376479801bb`。启动时读取原字节一次，所有实际 subprocess 使用独立冻结副本；不热读后续 no_links 修改。
- 引擎 SHA256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。
- 已读回总 manifest 及原 runner 回执；generated_removed，实际生成目录不存在，证据仍在独占 owner/evidence。

冒烟后补充的 partial-stdout 归档修复由对应 Python fixture 验证；没有重复 Godot 场景冒烟。未测加速、不承诺倍数，不将该旧冻结 generic 的证据与其他优化叠乘。新 generic 与 full 接线由各自 owner 做必要接口正确性确认；未覆盖全量/GUI/真实恢复/native 锁并发。
