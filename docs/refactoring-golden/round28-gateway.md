# Round28 — Gateway 默认监听与安全重监听生命周期

## 结果

最终冻结真实主仓库 headless 验收：Gateway 新专项 41 项、默认网关成员身份 44 项、身份安全 23 项、ENet 恢复 26 项、P2P 恢复 19 项全部 exit 0、failures=[]；两个安全关闭旧专项均 PASS / exit 0。默认身份专项始终设置 `FD_IDENTITY_DEFAULT_GATEWAY=1`，跳过旧夹具 `accepting_rooms=true` 补开门语句，不修改旧测试。

新专项还实际启动主仓库独立 room worker，经原生可信所有权句柄 ready、公开 console close、真实保存回执、真实退出 release、保留 recovery.json 后显式重监听。不是仅靠同进程路由替身证明独立 worker 生命周期。

## 根因与生产入口

- 已读 `round27-identity-fixtures.md` 与默认 Gateway 反例。`server_bootstrap.gd` 的公开 `--server-gateway` 路由进入 `server_cli.tscn`；`server_cli.gd:138` 在验证本机配置/数据/身份策略后调用 Gateway.listen，生产调用方没有另行设置 accepting_rooms=true。这段 bootstrap/CLI 为静态追踪，本轮没有另起完整 CLI 部署验收。
- listen 先 close，而 close 将 accepting_rooms=false、_close_requested=true；监听成功也没开始新生命周期。真实基线成员专项 exit 1，11 项，失败“通过真实网关附着回环工作连接”。
- listen 还忽略 close 返回 pending，会替换仍需保存/退出监督的 transport。新专项基线 exit 1，20 项，明确捕获 UNKNOWN/在途监督重监听及资源保留失败。
- 加入真实 worker 后发现第二个生命周期边界：manager 在确认保存与原生 EXITED 后 release 并撤销句柄。此后 process_state_for_binding 返回 UNKNOWN，不能把它继续当作活动实例永久阻断重监听；也不能泛化为所有 pid=-1 都安全。正式 manager.closed_binding_for_request 能证明已 release 的当前实例关闭历史。

## V4A 修改解释与解耦

只在唯一拥有的 `scripts/net/server/server_gateway.gd` 修改两个局部区域；已有共享工作树的其他 Gateway 修改保持原样，git diff 相对 HEAD 不等于本轮增量。其他生产和旧测试只读。

1. `listen` 复用 close 的公开结果，不增加独立开门 operation、不在 CLI 或测试补救。close 未完成返回 ERR_BUSY，仍保持拒绝并保留旧传输/房间资源。目录无效或真实 ENet 监听失败不开放。只有真实 listen 返回 OK 后清 error、_close_requested=false、accepting_rooms=true，明确启新生命周期。
2. `close` 复用 manager 的既有关闭历史查询；只认可同 room、instance_id、authority_host_mode 的正式 closed_binding_for_request。仍有 close_supervision 时永不完成；无历史的 UNKNOWN/裸 pid=-1、错实例旧历史仍拒绝。普通 poll、保存关停完成均不自动开门，必须再次显式 listen。
3. 新 `tests/gateway_relisten_acceptance_test.gd/.tscn` 使用真实 ENet 成功、占端口失败、close/重监听、真实请求关闭拒绝，以及原生 manager 的未知/监督负向；另外真实独立 worker 经公开 create_room/console close 证明在途保存不能重监听，保存退出释放完成后才可重监听。选人模式从正式 selection_modes.json 的 default_mode 读取，不把测试模式冒充正式规则。

没有调整 RSA、票据、房间绑定、恢复文件安全路径、落盘或保存回执契约。

## 真实命令与证据

所有运行器、日志、APPDATA、TMPDIR、FATE_TEST_SCRATCH_ROOT、worker 存储位于物理 E 盘独占根：

`E:/Caches/Hermes/cache/scratch/round28-gateway/`

Path.resolve 已核对物理根。每测试进程 180 秒看门狗；无窗口；只在超时 kill 本次 Popen PID，无按进程名称清理。真实 worker 从主仓库 `res://assets/scenes/main_menu/server_room_worker.tscn` 启动，生产 manager 原生 spawn 持有其本次 token。未创建仓库副本，故无副本可回收；保留日志及真实恢复文件作为证据。

```text
python E:/Caches/Hermes/cache/scratch/round28-gateway/run.py red gateway_relisten_acceptance net_member_identity_binding
python E:/Caches/Hermes/cache/scratch/round28-gateway/run.py freeze gateway_relisten_acceptance net_member_identity_binding net_identity_security_regression net_resume_identity net_p2p_resume_identity gateway_disconnect_safe_close round11_safe_close
```

运行器实际命令：

```text
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master --scene res://tests/<name>_test.tscn
```

| 最终日志 freeze-*.log | 退出码 | 结果 |
|---|---:|---|
| gateway_relisten_acceptance | 0 | checks=41 failures=[] |
| net_member_identity_binding | 0 | checks=44 failures=[]，默认真实 RSA/ENet 入房 |
| net_identity_security_regression | 0 | checks=23 failures=[] |
| net_resume_identity | 0 | checks=26 failures=[] |
| net_p2p_resume_identity | 0 | checks=19 failures=[] |
| gateway_disconnect_safe_close | 0 | PASS errors=0 |
| round11_safe_close | 0 | PASS errors=0 |

冻结 worker 输出目录：
`freeze-gateway_relisten_acceptance/worker-rooms/4d17f270c5ce985a02d493c9fe720f96/`

- 原生日志 `engine.1db6fd72269e8d17e558851905a5d828.log` 无 ERROR/WARNING/SCRIPT ERROR/leaked。
- 控制回执 `control/f2ac988f96b1cdef391475248521e18f.response.json` 实际读取 ok=true、saved=true；pid=21128，验收后系统进程查询未存活。生产 manager 本轮已验证原生退出并释放，不用事后裸 PID 查询代替原生身份验证。
- recovery.json 实际存在；新专项读取可信关闭历史，临时更换 instance_id 反例仍 ERR_BUSY，恢复原登记才允许显式监听。

## 过程问题与日志口径

- 第一次 green 身份票据前置失败不是 Gateway 回退：运行器 Windows Path 字符串提供反斜杠 TMPDIR，违反既有规范路径安全门。改为 as_posix 的 E 盘根后 44 项通过；未放宽生产保存路径检查。保留 `green-*` 失败证据。
- 第一轮 native worker 正式拒绝 selection_mode=test；读取正式 default_mode 后通过。保留 `native-*` 日志，不把这次配置错误当生产生命周期 RED。
- 第二轮 native-final 捕获 release 后重监听阻塞，促成仅认可正式当前关闭历史的补丁。
- Gateway 占端口负向故意触发唯一预期原生 `ERROR: Couldn't create an ENet host.`；最终新专项 exit 0 且对应拒绝断言通过，不宣称整份主日志无 ERROR。其余冻结专项无 ERROR/WARNING/SCRIPT ERROR/leaked。
- `git diff --check -- scripts/net/server/server_gateway.gd` exit 0。旧成员测试 SHA256 与 round27 完全一致，证明未改旧测试补开门路径。

## 冻结 SHA256（终端实算）

- Gateway：`c93b92cba86fa317c7f8eed027d3ae73dc544650869e142d2ad38dcb084a4112`
- 新专项 gd：`e86ea9a2da0911f22b85c67ff9c883eb0d89af17b53fe27b76c47317cb81c9a6`
- 新专项 tscn：`6c46f177404b0cf8421af477c8882ced896f9e98a4e3858c6ecb0fe471c52ab1`
- 只读成员旧测试：`b59fc0b75757902b177ee0642075bc9381647d30de856fe7f46fa3cdcb761d7e`

未提交；未读取用户密钥/secret；没有窗口、真人、多机或跨网验收。P2P 恢复旧专项仍保持 round27 同进程权威夹具范围，不冒充独立 P2P worker 整链。
