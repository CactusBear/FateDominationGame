# start 请求模块交接

**模块完成、生产未接线。** 本次未写 `lobby_session.gd`、`selection_authority.gd`、`room_state.gd`、规则或数据。

## 接口与边界

```gdscript
receive_start(actor:int, is_owner:Callable, can_start:Callable, data_ready:Callable, prepare_selection:Callable, start:Callable) -> bool
```

- `is_owner(actor)` → `can_start()` → `data_ready()` → `prepare_selection()` 按原顺序短路；全部 true 才唯一调用 `start(actor)`，原样返回 bool。
- owner/阶段等规则由 Session 提供能力；模块不判 owner、不读 phase，不保存能力或状态。
- start 原请求没有载荷字段，因此不新增 args、actor 范围或其它限制。
- 发布、失败 reason、请求尾部发布/回执留在 Session，不传发布能力。
- 移除本次新增的七行后，文件 SHA256 与 initial freeze 中原文件完全一致：`EXISTING_MODULE_BYTES_PRESERVED True`，旧 handles/receive/set_settings/receive_choice 保持逐字不变。

## 生产接线精确 anchor 与 payload（仅交接，未应用）

目标：`scripts/net/session/lobby_session.gd`。交接时整文件 SHA256：
`f50835e933514b9a24e1571d86d4fbdfcdf6f0fa8d073dc163a2f4579d0a31ff`

共享 owner 正在修改该文件；此 hash 仅为读取时刻证据，main 应重新读取并断言以下 anchor 恰好出现一次，不按漂移行号写入。此次读取 `START_ANCHOR_COUNT 1`。

Anchor（保留真实 TAB 缩进）：
```gdscript
		"start":
			if sender == room.owner and room.can_start() and data_ready() and _prepare_selection():
				ok = room.start(sender)
				if ok:
					_publish_selection()
```

Payload：
```gdscript
		"start":
			var start_room = room
			ok = _host_room_inbox.receive_start(
				sender,
				func(actor:int) -> bool: return actor == start_room.owner,
				start_room.can_start,
				data_ready,
				_prepare_selection,
				start_room.start
			)
			if ok:
				_publish_selection()
```

owner 闭包仅捕获局部 Room；不 bind 或替换 actor。其它能力同步传入且不被模块保存。不改相邻 choose_master、失败 reason、seq/认证/在线门或请求末尾 `_publish()`。**此 payload 尚未应用或完成生产接线验收，交 main 单独小任务。**

## 真实 Godot 契约证据

命令（仓库根执行）：
```text
python -B newtests/host_room_start_request_runner.py initial
python -B newtests/host_room_start_request_runner.py green E:/scratch/pw-e392b13a
python -B newtests/host_room_start_request_runner.py mutation E:/scratch/pw-e392b13a
python -B newtests/host_room_start_request_runner.py green E:/scratch/pw-e392b13a
```

四次 runner exit 均为 0（按各阶段预期核验）；各 Godot 结果：

| 阶段 | PID | Godot exit | CHECK | failures | Job active |
|---|---:|---:|---:|---|---:|
| initial RED | 38116 | 1 | 1，API 缺失 false | independent start API exists | 0 |
| 首次 GREEN | 35760 | 0 | 24 true | [] | 0 |
| 独占副本 actor+1 变异 RED | 2684 | 1 | 24，2 false | sender reaches owner predicate and start unchanged; adapter adds no actor range restriction | 0 |
| 恢复源码最终 GREEN | 39016 | 0 | 24 true | [] | 0 |

最终实际输出：
```text
RESULT {"checks":24,"failures":[],"suite":"host_room_start_request"}
```

CHECK 覆盖：合法调用次序与唯一性；actor 透传 owner 谓词及 start；四个前置逐一 false 时返回 false、后续短路、start 未调用；错 actor 由提供的谓词拒绝且不替换、不分派；start 自身 false 原样返回且不重试；不新增 actor 范围限制；请求能力 WeakRef 释放；旧 handles 不吞 start。

测试只运行真实 Godot 的独立模块契约，注入的能力是调用观察探针，不建立房间/选人/数据规则替身，也不改生产 setter。未声称已验证 Session 接线。

完整证据：`E:/scratch/pw-e392b13a/evidence/{initial,mutation,green}-verified.json` 与对应 stdout/stderr。
最终 stdout：`green.stdout.log`，24 条 CHECK 均 true；stderr 为空；无 SCRIPT ERROR；`timeout=false`；Windows Job Object `active_owned_processes=0`、日志句柄已释放。

Godot 实际命令：
```text
E:/scratch/pw-e392b13a/engine/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path E:/scratch/pw-e392b13a/project --scene res://newtests/host_room_start_request_test.tscn
```

180 秒独占 PID 树看门狗。APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 全在独占 E 盘；实际 `USER_PATH E:/scratch/pw-e392b13a/appdata/FateDomination`。原引擎及原 DLL 字节 hash 相同，无替身 DLL。无 GUI、长局、全量、测速；未监听或连接 28100；未输出配置、身份或票据。

## SHA256

| 文件 | SHA256 |
|---|---|
| scripts/net/session/host_room_inbox.gd | fb4a14e16b28d8ab2d844176014aff528c476e4b9223fb512bda4f5dadacc799 |
| newtests/host_room_start_request_test.gd | 425b9ec7aee3ba77f26b0f840163f90eca14bea4b0f5a1c66741157b86784ab5 |
| newtests/host_room_start_request_test.tscn | e9916192c77c3d8d424d303c9ff73d2e38f2f989af6cfd534d3536c8bfb982e9 |
| newtests/host_room_start_request_runner.py | 04685a2b0862a82c4fff0a660a4c56884c6f34201292b2ffd52bb961afebd997 |
| 原 Godot console exe | c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643 |
| 原 fate_server_signals DLL | 92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd |

最终冻结的三份生产/契约源码 hash 与工作树相等。共享树全局 `git diff --check` 曾返回 exit 2，输出含既有文件 CRLF 警告；未在本任务追查共享改动。改用仅自有文件范围检查 exit 0，未改其它文件。
