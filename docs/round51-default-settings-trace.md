# Round51 默认15首 settings 链 trace

## 结论

当前未改生产源码在同一 E 盘物理 Godot 主/worker 路径下已稳定通过首 settings 链；因此本轮没有生产 diff，也没有把旧现场的失败改写成绿：

- 当前原 `server_simulation_default_budget_test`：父 13 checks、child 24 checks、failures=[]、exit0；scene 墙钟 51.948s。
- 当前 `round51_default_settings_trace`：父 9 checks、child 9 checks、failures=[]、exit0；trace 预算 18s，实际在 11.429s 观察到 READY 与 client snapshot。
- 当前链可称 `default15 currentchain PASS`，仅限本次未冻结源码现场；不升级为完整204随机模拟、GUI、发行包或历史红现场已修复。

## 旧红现场保留

1. `E:/scratch/isolated-65d35784905e4dfe92141d430999caa2/manifest.json`：`server_simulation_default_budget` 父13 exit1；原 stdout 的 child checks=8、rows=[]，worker engine log 只有 Godot header；房间目录和数据输出已保留。该现场首个可观察失败是 worker→gateway→client settings 断言没有得到 snapshot，不能从日志证明更早的具体生产调用点。
2. `E:/scratch/isolated-9dd9c21b4c35475d9d75b4bffbeb971a/manifest.json`：exit1、44.647s；`cli.log` 显示 CLI/gateway/manager.data_settings/建房均已成功，settings 断言失败；worker log 只有 header；`data.building-28365310` 保留。该现场未证明 CPU、startup budget、argv 或端口是原因。
3. 当前原测试同源码、同 E 物理引擎真实运行：`E:/scratch/isolated-7f4a5addb41e42f488937cd43e714eae/manifest.json`，`freeze=false`（生产配置保留不改）；父13、child24、exit0。其 child rows 三次均收到默认15/0/7.5，证明当前原入口不是持续红。

## Round51 trace 观测

证据：`E:/scratch/isolated-56ff68bb0e5f47698d09fb4f83dfa694/manifest.json` 与 `evidence/scene.stdout.log`。仅打印 settings 标量、UUID、PID、SHA256，不打印身份库、密钥、票据或原始认证资料。

- parent run UUID：`56ff68bb0e5f47698d09fb4f83dfa694`；trace main PID `27736`。
- room UUID：`015d40222781911bd17e655b6a0aa203`；worker instance UUID：`90cdcbf26475b8d37f44b90dfa9b87c9`；worker PID `29644`。
- template/CLI.data/manager.data_settings：`random_sim_enabled=true`、`random_sim_budget_sec=15.0`。
- worker config settings：`capacity=2, minimum=2, ai_count=0, selection_mode=unique_master_class_pool, spectator_limit=2, random_sim_enabled=true, random_sim_budget_sec=15.0`。
- worker config settings `var_to_bytes` SHA256：`5163d5e7098e6de5fde84b5e8f3753b32415f19931c3a5d643186f2c1d9354d`。
- `RoomState.decode_json_settings` 对该 config 返回 true；预期 RoomState settings 字节摘要：`2f7b2c6c855aa504157d21d7668b31e9b160ac7b951fef058f96e1a570a47303`。没有为读取 worker 内部对象而加生产日志；这一层用真实 worker config、同一生产 decode 函数结果、READY 后认证 snapshot 三者交叉验证。
- 首次可定位 room sample：`838ms`，room 已登记、worker 未 READY、`ready.json` 不存在、client snapshot 为空、无 manager error。
- 首次 READY/client snapshot：`11429ms`，`manager_ready=true`、`ready.json=true`、`data=true`、staging_count=0；没有先收到 READY 后补 snapshot 的倒序。
- client snapshot：`capacity=7`（worker 按可用阵容派生），其余 settings 与 config 一致；client full settings SHA256：`da58a38300404f3ae3a81aada4e59902bcd4da0ee6b3acf788cbcc826e7b47c4`；随机设置字段摘要：`4896b110c2b0de284884843b2220aa0ee7c9853eb195d534f04ebb353b51310c`。
- `first_divergence=""`；当前 trace 没有发现字段丢失、顺序错误或 READY 先于 snapshot。

## 最短时间线与判断

`template 15 → CLI.data 15 → manager.data_settings 15 → worker config 15 → RoomState decode/config 合法 → assembly/data 完成 → ready.json/manager READY → authenticated client snapshot 15`。

旧 `65d/9dd` 的共同证据只到“默认数据策略已进入 manager、worker 已启动但没有可消费 snapshot”；两份 worker 日志缺少内部阶段标记，不能从旧实际日志证明具体是哪一个修复或 fixture 导致恢复。当前绿现场显示当前源码链路已走通，但不能反推历史红的唯一根因。

## 生产边界

- 未修改 CLI、manager、worker、RoomState、Session、预算、ready 时限、端口选择、重试或 sleep。
- 未跑完整204随机模拟、97套件或GUI。
- trace 测试只新增：`tests/round51_default_settings_trace_test.gd`、`tests/round51_default_settings_trace_test.tscn`；本文件为新增诊断文档。
- 冻结 runner 的 editor import 另因只读副本缺 GitPlugin/VCS 扩展而拒绝；运行证据仍使用物理 E 引擎、E scratch、真实 PID/Job 回收的未冻结源码现场，不能冒称 frozen-import PASS。
