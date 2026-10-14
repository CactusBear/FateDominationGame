# Round36：end_command 测试端口修复

## 结论

- `battle_board_end_command_test` 恢复原 **38 checks**；同一最终冻结连续实跑3次均 exit0、唯一RESULT、failures=[]、零引擎/脚本错误。
- 不改production、旧端口fixture、其他既有tests；结束动作、重复点击、seq拒绝、close/reconnect、观战与seat切换、恢复可点等38个原断言调用逐行比较完全未变，原tscn摘要未变。
- 系统UDP `bind(0)` 选择端口并持有socket，释放后同步调用真实 `Lobby.host()` 一次；不再用PID或随机数猜端口，也不扫描20次ENet监听。失败明确返回并清理，不自动重试、不全局忽略错误。

## 根因与原语审查

已读 `hermesWarning.txt`、round33报告及真实调用链。round33 PID35708按旧公式得到51708–51727，落入当时/本次实际非管理UDP排除段51674–51773。旧20候选全失败属于端口夹具问题，不是结束命令业务回归。

既有 `tests/net_port_fixture.gd.available_range()` 使用UDP实际探测，但扫描固定区间并立即释放，不提供持有端口的交接契约；保持只读。插件TCP排除表工具不作为游戏UDP测试依赖。生产 `scripts/net/transport/enet_transport.gd.listen()` 第39行拒绝port0，不能直接给 `Lobby.host(0)`；生产接口保持不变。

新增fixture仅分离测试环境资源所有权：`reserve_udp()` 使用真正UDP port0；`handoff()` 释放socket后不await、立即调用监听回调，原样返回Error；`close()` 幂等回收。测试明确绑定127.0.0.1，与host/guest实际回环协议一致。排除表parser只用于诊断/独立负例，正常端口选择不依赖netsh或本地化输出。

**非原子边界**：生产host不能接管PacketPeerUDP socket，故释放至ENet绑定间仍有竞争窗口；没有声称绝对无竞态。独立占用负例在该窗口实际抢占，证明失败可见、仅尝试一次，并在释放占用后成功监听同一端口。

## RED与实现差异

在E隔离副本把旧测试候选替换为本机实际排除段起点，并仅保留一次试开；未改源树。真实RED为exit1、`RESULT checks=9 failures=["真实 ENet host"]`、恰一条`Couldn't create an ENet host`。原源码及该最小复现源码、完整stdout/stderr均归档。

仅修改结束测试的端口准备块、增加PortFixture preload、失败分支清理和TEST_PORT诊断。完整变更为归档 `evidence/end-command.diff`。

## 同一最终冻结验收

| 场景 | exit | checks | 错误及判定 |
|---|---:|---:|---|
| network_test_port_fixture_test | 0 | 21 | 零错误、严格通过 |
| battle_board_end_command_test | 0 | 38 | 零错误、严格通过 |
| battle_board_activation_command_test | 0 | 21 | 零错误、严格通过 |
| battle_command_adapter_test | 0 | 29 | 零错误、严格通过 |
| match_command_result_protocol_test | 0 | 39 | 零错误、严格通过 |
| network_test_port_occupied_negative_test | 0 | 7 | 一条原生ENet错误、独立限定负例通过 |
| network_test_port_excluded_negative_test | 0 | 7 | 一条原生ENet错误、独立限定负例通过 |

最终7个不同场景共162 checks，不将两次38-check重复运行计作额外场景。结束测试三次系统所选端口实际为50061、50066、50073，监听均返回OK。

两负例通用严格分析保持 `passed=false/reasons=["engine_or_assertion_error"]`；只在独立 `verify.py` 核对本次冻结源码hash、准确bind行、唯一开始/结束标记、全部CHECK真、exit0及完整stderr之后，赋予限定负例通过。占用负例stderr严格6行，bind第21行；排除负例严格4行，bind第28行。没有修改通用runner或放宽引擎错误判定。

本地化parser验收覆盖英文/中文标题、CRLF、Tab、管理星号、端点越界、倒序和非表格杂项。真实netsh输出也已解析并实跑非管理排除端口50263。

首次排除负例选择表中带`*`的管理项50000，实际ENet可以绑定，产生业务断言失败而非引擎错误；完整旧结果在 `evidence/pre-final-administered-diagnostic/`，未删除或伪装通过。最终parser默认保留全部项，通过显式参数过滤管理项供原生拒绝负例使用，未硬编码特定端口。管理排除并不保证当前进程不可绑定。

## 文件

- 修改：`tests/battle_board_end_command_test.gd`。
- 新增：`tests/network_test_port_fixture.gd`。
- 新增：`tests/network_test_port_fixture_test.gd/.tscn`。
- 新增：`tests/network_test_port_occupied_negative_test.gd/.tscn`。
- 新增：`tests/network_test_port_excluded_negative_test.gd/.tscn`。
- 新增本报告；`battle_board_end_command_test.tscn`未改。

注意：仓库 `.gitignore` 第47行忽略整个 `/tests/`；不能用空git diff/status冒充无改动。本轮以冻结摘要、归档源码、直接diff及实际运行核验，不擅自git add/commit。

## 执行、证据与回收

独占证据根：`E:/scratch/isolated-359e3498afa24c19926b0d4564494fc6/`。保留 `manifest.json`、实际执行器 `run.py`、限定核验器 `verify.py`、全量日志、源码摘要及最小源码证据；最终汇总 `evidence/final-verification.json`。

实际Godot命令（最终重复运行之一）：

```text
E:/scratch/isolated-359e3498afa24c19926b0d4564494fc6/generated/engine/Godot.exe --headless --fixed-fps 60 --path E:/scratch/isolated-359e3498afa24c19926b0d4564494fc6/generated/project --scene res://tests/battle_board_end_command_test.tscn
```

实际驱动与核验命令：`python -B <证据根>/run.py setup`、`red`、`refresh`、`scene <场景名>`、`python -B <证据根>/verify.py`、`run.py cleanup`；原命令、PID、退出码、耗时都在manifest。generated已回收，上述Godot命令是历史真实执行记录，重新执行须另建独占路径。

真实主/子Godot user://探针均验证物理E独占路径及继承环境，worker_pool/max_threads=20。APPDATA、LOCALAPPDATA、TEMP、TMP、TMPDIR和FATE_TEST_SCRATCH_ROOT显式指向本轮E生成树。冻结副本仅转换[editor]两项VCS字段，不改主工程配置或生产源码。每进程180s Windows Job看门狗仅本次所有权PID，无窗口、不询问用户。

22个自有执行记录全部退出、active_owned_processes=0、日志句柄已释放；源码所有拥有文件摘要未变、源Godot摘要未变。清理回执为 `generated_removed`，工程副本、独占E引擎、import缓存和APPDATA等大生成树已回收，最小证据保留。

源码在初始冻结后有其他owner对 `scripts/net/validation/room_data_validation_worker.gd` 的漂移，未回灌本次副本。本报告仅对本轮固定副本的专项headless结果负责，不宣称round33全66套、正式GUI输入、多机网络或当前全仓库最终freeze验收通过。