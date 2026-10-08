# worker 启动参数与 bootstrap 路由审计

## 结论与边界

- **静态确认：正常 create/recover 调用链没有发现错误场景、父参数串入、职责 flag 重复或三个批准路径丢失。** 源码模式直接加载 worker 场景；`fate_server` 发布模式有意移除引擎 `--path/--scene`，改由发布主场景 bootstrap 路由到同一 worker。这不是场景参数丢失缺陷。
- **日志与 ready 在正常链路按同一随机 instance_id 对应。** 重启使用新日志，旧 ready 在 spawn 前删除；ready 验证同时绑定 room、port、PID、instance、authority host mode，日志不是路由就绪的判据。
- 本批只读生产源码，并执行 Python 源码断言（退出码 0）。**没有运行 Godot，没有启动子进程，没有读取新运行的日志/ready，因此不是发布包或多进程运行验收。** 发布包实际 feature、PCK 主场景和日志重定向仍需主代理后续验收。

## 启动链与参数账本

证据：`scripts/net/server/server_room_manager.gd:177–195,329–367`；`server_bootstrap.gd:56–93`；`server_room_worker.gd:27–59`。

### 源码 / 非 fate_server

```text
OS.get_executable_path()
--headless --audio-driver Dummy
--path <globalized res://>
--log-file <room-directory>/engine.<instance_id>.log
--scene res://assets/scenes/main_menu/server_room_worker.tscn
-- --server-room-worker <config.json> <approved-data-root> <storage-root>
```

### fate_server 发布模式

```text
OS.get_executable_path()
--headless --audio-driver Dummy
--log-file <room-directory>/engine.<instance_id>.log
-- --server-room-worker <config.json> <approved-data-root> <storage-root>
```

- `process_arguments()` 只在 `OS.has_feature("fate_server")` 为真时变换；只移除分隔符之前的 `--path/--scene` 及紧跟的值。遇到第一个 `--` 后保留整个余段，因而不误删用户路径或职责参数。
- 两处 manager 构造各只有一个 `--` 和一个 worker flag；不是在父进程 argv 上追加，不继承父进程的 `--config`、gateway flag、父日志或父场景。
- worker 从 `OS.get_cmdline_user_args()` 删除 worker flag 后要求恰好三个位置参数：配置、独立批准数据根、独立批准存储根。配置中的 `directory/data_root/id` 再和这些根、配置位置交叉核对；不由恢复配置自报授权根。
- native binding 逐项转为 UTF-8 字符串（`addons/fate_server_signals/src/process_owner_binding.cpp:26–29`），没有追加父 argv。Windows 对可执行文件和每项参数分别加引号并处理反斜杠/引号（`process_owner_core.cpp:48–66,134–145`）；Linux 构造 `argv[0]=executable` 后逐项追加并 `execve`（150–174）。环境变量会继承，命令行不会继承；路径含空格在源码设计上不会拆词。

## 场景和 bootstrap 账本

| 模式 | 入口 | 最终脚本 | 证据 |
|---|---|---|---|
| 源码子进程 | 显式 `--scene .../server_room_worker.tscn` | `scripts/net/server/server_room_worker.gd` | worker 场景第 3–6 行 |
| fate_server 子进程 | `run/main_scene.fate_server` 指向 bootstrap | worker flag 路由相同 worker 场景 | `project.godot:25`；bootstrap:77,93 |
| 未声明职责的 bootstrap | 默认 gateway / server_cli 场景 | CLI 仍检查 `--config` 参数 | bootstrap:89；server_cli:15–19 |

Linux/Windows 服务端 preset 都声明 `custom_features="fate_server"`，并导出全部资源（`export_presets.cfg:124–155`）；源码中目标场景未被排除。这里只确认配置，不证明旧发布包与源码一致。

bootstrap 对五种职责逐个检查：同一 flag 多次或同时出现两种职责时退出 2（82–87），不会依赖最后一个 flag 覆盖前一个。bootstrap 没有删除 worker flag，场景切换也没有新建进程，所以 worker 消费的是原始用户参数。`LoadGame._ready()` 因 fate_server 或 worker flag 跳过默认数据加载（`scripts/system/global/load_game.gd:13–16`）；worker 再从批准隔离目录 `reload_game()`（145–147），不是在开场菜单提前加载后沿用错误数据。

## 日志、ready、主管与管理 IPC 对应

- 创建：同一个局部 instance_id 写入 `config.json`、引擎日志名和 manager 登记（manager:177–195）。恢复：生成新 ID、发布 config、清旧 ready、构造新日志、spawn、成功后更新登记（329–367）。spawn 失败会尝试还原配置 ID，不把失败子进程声明为 ready。
- worker 从 config 给 `_control.instance_id/room_id/authority_host_mode` 赋值（57–59）；控制器构造时产生的随机默认 ID被覆盖，**没有第二套管理实例标识**。
- ready 在实际 host、数据校验/发布和必要审计初始化后写 `ready.json.tmp`、flush，再 rename 为 `ready.json`（worker:155–202）。PID 是 worker 自身 PID；`instance` 与 `instance_id` 都来自 `_control.instance_id`。
- manager 每帧读的是登记房间目录的 ready，严格核对身份、端口、权威位置与能力 bool，且 native process state 必须 RUNNING（100–106,210–235）。gateway pending 到 attach 再做绑定和 native 所有权核对（`server_gateway.gd:60–74`）。旧日志出现 READY 文本不会让新实例就绪。
- worker 退出时只删除自身 PID + instance 对应的 ready（350–355），旧进程晚退出不能删除新实例报告。
- 心跳使用同一 room/PID/instance（manager:370–378，worker:205–216）。管理请求/回执绑定 room、PID、instance、authority_host_mode（`server_room_control.gd:35,43–47`）。
- 默认非对局录制事务审计名也绑定实例：`transactions.<instance_id>.log`（worker:186–187）；启用对局录制时使用 recorder 的 transactions.log，这是对局存档日志，不是 worker 引擎日志。

## 静态发现的防御/可观测性缺口（未修）

1. **直接 worker 场景入口不强制要求职责 flag 存在。** worker 只 `erase()` 再检查三项路径；手工指定 worker 场景且只给三个路径也能进入启动校验。源码模式不经过 bootstrap 的职责互斥检查。不过 manager 生成的 argv 始终含 flag；缺 flag 也不会绕过批准路径、配置和实例校验，不能据此称正常链路错误加载。若要求所有入口同一职责契约，应在 worker 独立检查 flag 恰好一次，并拒绝其他职责 flag。
2. **bootstrap 延迟换场景未检查返回值。** 第 93 行的 deferred `change_scene_to_file` 没有显式失败退出；旧/损坏发布包缺场景时可能留在 bootstrap，父主管最终报启动超时，而不是立即得到可定位的路由失败。正常源码目标存在；属于发布损坏时失败诊断不足。
3. **日志关联依赖主管登记/文件名，ready 没有 log_file 字段。** `SERVER_ROOM_READY` 文本只打印 room id（worker:202），不打印 PID/instance/host mode。因此单独复制一条日志文本不能证明对应实例；应按 config/manager + `engine.<instance_id>.log` + ready 的身份字段联合核对。当前 manager 不扫描日志，故不会造成旧日志误判 ready。

## 已执行的检查与未执行项

Python 直接读取当前生产文件并断言：两处启动参数前缀一致；各只有一个 worker flag/分隔符；worker 要求三个路径；发布变换保留 `--` 后余段；bootstrap 拒绝重复/冲突职责；项目 fate_server 主场景正确；恢复清 ready 在 spawn 前；实例日志命名、ready 验证及退出清理绑定存在。实际返回：`PASS ... Source assertions only; Godot not executed.`，退出码 0。

这是源码契约检查，不是用 Python 重写 worker 执行器，也不是 Godot 解析/运行验证。未执行：源码 worker 启动、发布 EXE/PCK 启动、含中文/空格路径运行、崩溃后恢复、ready/log 实际 PID 对账、多机网络验收。未修改任何生产文件；本批唯一交付文件为此文档。
