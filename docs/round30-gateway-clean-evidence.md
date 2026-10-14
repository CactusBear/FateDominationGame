# Round30 Gateway clean evidence

## 结论

本轮把真实 ENet bind 失败从 Gateway 正向专项中分离为独立负向场景。生产 Gateway、其他源码以及 `tools/tests/test_round29_integrated_evidence.py` 未修改。

- 正向 `gateway_relisten_acceptance_test`：真实 Godot exit `0`，`RESULT checks=38 failures=[]`；stdout/stderr 均无 `ERROR:`, `SCRIPT ERROR`, `SHADER ERROR` 或 `FAIL`。
- 负向 `gateway_bind_failure_test`：真实 Godot exit `0`，`RESULT checks=7 failures=[]`；stderr 仅为预期 ENet bind 原生错误及其固定回溯，且绑定到新负向测试第 13 行；没有全局忽略 engine error。
- 正向保留：目录失败关闭、目录失败后的显式重监听、普通 close 不自动开门、未知 `UNKNOWN` 实例拒绝重监听并保留资源、在途保存监督拒绝重监听、真实 worker 保存回执/退出释放/recovery、安全重监听，以及关闭期间请求拒绝。
- 负向保留：真实 blocker 占端口、bind 失败返回、失败后保持关闭、失败路径不保留半成品传输、释放端口后的显式重监听与新生命周期。

## 真实运行

引擎：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`

```text
FATE_TEST_SCRATCH_ROOT=E:/Caches/Hermes/cache/scratch/round30-gateway-clean/red-fixtures D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master --scene res://tests/gateway_bind_failure_test.tscn
FATE_TEST_SCRATCH_ROOT=E:/Caches/Hermes/cache/scratch/round30-gateway-clean/green3-fixtures D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master --scene res://tests/gateway_relisten_acceptance_test.tscn
```

最终日志：

- RED/负向 stdout：`E:/Caches/Hermes/cache/scratch/round30-gateway-clean/red.stdout.log`
- RED/负向 stderr：`E:/Caches/Hermes/cache/scratch/round30-gateway-clean/red.stderr.log`
- GREEN/正向 stdout：`E:/Caches/Hermes/cache/scratch/round30-gateway-clean/green.stdout.log`
- GREEN/正向 stderr：`E:/Caches/Hermes/cache/scratch/round30-gateway-clean/green.stderr.log`

负向 stderr 精确内容（唯一允许错误）：

```text
ERROR: Couldn't create an ENet host.
   at: _create (modules/enet/enet_connection.cpp:319)
   GDScript backtrace (most recent call first):
       [0] listen (res://scripts/net/transport/enet_transport.gd:44)
       [1] listen (res://scripts/net/server/server_gateway.gd:51)
       [2] run (res://tests/gateway_bind_failure_test.gd:13)
```

## 主代理聚合器接线口径

`test_round29_integrated_evidence.py` 是整合代理唯一拥有文件，本轮未改。聚合器必须把两个 scene 当作两个明确 suite，分别调用并分别解析：

1. **正向**：运行 `res://tests/gateway_relisten_acceptance_test.tscn`；要求 `exit == 0`、唯一 stdout `RESULT`、`checks == 38`、`failures == []`，并要求 stdout/stderr 完全没有 `ERROR:|SCRIPT ERROR|SHADER ERROR|^FAIL`。
2. **负向**：运行 `res://tests/gateway_bind_failure_test.tscn`；要求 `exit == 0`、唯一 stdout `RESULT`、`checks == 7`、`failures == []`。不要把负向 stderr 送入正向的全局零错误规则；改用场景级白名单精确匹配上面的 6 行（包括测试源码行 13），并拒绝任何额外错误、额外回溯、非预期 `FAIL` 或 `SCRIPT ERROR`。
3. 两套都必须检查结果行、CHECK 唯一性/布尔值/数量一致性；负向“允许错误”只能在该 suite 的精确 bind 调用与源码 hash 绑定成立时生效，不能修改全局 `analyze` 或忽略所有 ENet 错误。

## 文件与校验

修改/新增：

- `tests/gateway_relisten_acceptance_test.gd`（正向从 41 checks 调整为 38 checks；移除占端口负向，补回无错误的显式重监听契约）
- `tests/gateway_bind_failure_test.gd`
- `tests/gateway_bind_failure_test.tscn`
- `tests/gateway_relisten_acceptance_test.tscn` 未改

`git diff --check`：exit 0。整合聚合器相对工作树无 diff。

SHA256：

```text
b8695d773e39841c3932bf618f57550fd734c57d9bd8c6ee492807e953f7ccab  tests/gateway_relisten_acceptance_test.gd
6c46f177404b0cf8421af477c8882ced896f9e98a4e3858c6ecb0fe471c52ab1  tests/gateway_relisten_acceptance_test.tscn
c6f4d7889f6b733b0f19228e15fa417173b6d6a346d3db60ae53025f445bdb63  tests/gateway_bind_failure_test.gd
7ea3445f77ce8ec45bc4150510201863f539bf0ef4671808b302399e54e4a638  tests/gateway_bind_failure_test.tscn
```
