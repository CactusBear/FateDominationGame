# E08–E15 headless 复验

- 复验源码 HEAD：`8c0f946faf6cc0cd3f04f12f66f5a99a413088ca`
- 隔离源指纹：`19650861e174944b68a50c2c5c4ebdfc2321acd936f159ff0127ec19bf36b1f3`
- 指纹：冻结前后相同；冻结文件 1438；生产树未写入。
- 隔离证据总 manifest：`E:/scratch/isolated-e08-e15-83aeaf0d2b69455d9a7a035f7375b244/manifest.json`
- 所有已执行进程 `active_owned_processes=0`、`exited=true`、`log_handles_released=true`；无超时，因此未触发超时重跑。

## 真实套件结果

| 项 | RESULT / CHECK | exit | ERROR | Job0 | 判定 |
|---|---|---:|---|---|---|
| content_environment | `RESULT content_environment_test checks=30 failures=0`（该旧套件不打印逐行 CHECK） | 0 | 无 | 是，PID 14608 | PASS |
| preparation_consumer | `RESULT checks=31 failures=["真实子进程已就绪并入房"]`；其余 30 条已打印 CHECK 为 true | 1 | 无 | 是，PID 4644 | RED |
| preparation_dependencies | `RESULT checks=34 failures=[]` | 0 | 无 | 是，PID 38008 | PASS |
| assembly_publish_204 | `RESULT checks=36 failures=[]`；含真实 204 清单发布/读回 | 0 | 无 | 是，PID 7264 | PASS |
| loader_missing_roster | `RESULT loader_error_boundary checks=9 failures=[]`；6 条声明错误与 6 条实际 `ERROR` 逐字一致 | 0 | 6 条**预期**缺 masters/servants 错误，无额外错误 | 是，PID 26848 | 严格负向 PASS |
| net_server_gateway_restart | `RESULT checks=9 failures=[按 ready 等待…, room worker starts, 保存回执…, 释放全部房间…]` | 1 | 无 | 是，PID 11152 | RED |

准备器消费者的绿色部分包含显式工厂注入、validation 别名同步、取消只影响本实例、独立校验进程保持运行、旧信号解绑等；唯一首红是权威子进程未 ready。网关重启在 room worker ready 前失败，随后 save 无法确认“本次保存”，未宣称恢复成功。

## 静态核对

- `scripts/system/global/content_environment.gd` 只有两类全局写入：
  - `LoadHelper.session_data_dir`：install/restore；
  - `LoadGame.stored_jsons_path`：install/restore。
  其余加载路径、tag/snapshot/texture cache、flags 与 cache budget 由 `content_environment_test` 的 30 条检查保持不变。
- 生产 `scripts/**/*.gd` 的精确赋值扫描：
  - `LoadGame.stored_jsons_path` 只命中 `content_environment.gd:13,21`；通过。
  - `LoadHelper.session_data_dir` 另命中 `scripts/match/match_replay.gd:151,525` 与 `scripts/match/effect_checkpoint.gd:82`。这三处不在本次两 worker 进程级安装点内；若项目豁免仅允许 worker 安装点，则该 grep 门不通过，未擅自修改。
  - `server_room_worker.gd`、`room_data_validation_worker.gd` 没有这两处直接赋值；worker 使用 `ContentEnvironment.install/restore`。
- `room_data_validation_worker.gd:129–158` 在加载失败、写报告失败、正常结束均显式 restore，并 assert 两个全局值回到 token；`loader_missing_roster` 严格负向真实执行通过。
- 生产准备器 `room_data_preparation.gd` 的 `_init` 显式注入 settings/humans/blobs/publish/download；生产扫描无 `session.room._humans`。仅测试夹具仍有两处旧写法命中，未改测试。

## 未覆盖 / 限制

- `lobby_content_environment_restore_test` 未跑：E09–E11 的 lobby 全部恢复专场未覆盖。
- `worker_content_environment_test` 未跑：本次覆盖的是 validation worker 缺 roster 严格错误，不等同完整 room-worker 内容环境专场。
- E14 的 client/server 独立 EXE 启动面未跑。
- E12 的 `net_server_gateway_restart` 已执行但 RED，未形成成功的 authority 存档恢复证据。
- 第一次隔离构建因并行 owner 写入导致源漂移而 fail-closed；第二次冻结后源指纹稳定并完成上述套件。未读取密钥/票据，未触碰 PID 17120/28100，未修改断言或生产文件。
