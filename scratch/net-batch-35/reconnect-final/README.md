# batch35 reconnect-final

## 结论
batch34 候选不能直接应用：它虽然可调用现有 `authority_host.diagnostics()`，但 `recover_worker()` 成功后又调用普通 `reconnect()`。现有 `recover_worker()` 已执行 `_prepare_reconnect()`、替换 worker 实例并清理旧路由；继续走 `reconnect()` 会再次进入 connection driver 的重连/关闭路径，可能破坏本机 `authority_host`。

## 单一替代
`change.v4a` 不新增接口，复用现有 `diagnostics()`。`reconnect_after_worker_crash()` 在 crash-waiting 时调用既有 `recover_worker()`；成功直接返回 `OK`，由既有 `authority_host.poll()` 异步接入新的 loopback，绝不再次调用 `reconnect()`。非崩溃状态仍原样走 `reconnect()`，恢复拒绝返回 `ERR_UNAUTHORIZED`，不伪造成功。

## 验证
应用候选后运行：

```sh
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy --fixed-fps 60 --path E:/Projects/Godot/FateDominationGame-master --scene res://scratch/net-batch-35/reconnect-final/crash_reconnect_ui_test.tscn
```

测试使用真实 `Button.pressed` 信号和生产 `lobby_session.gd`，覆盖：恢复成功后等待 poll（不再 reconnect）、恢复拒绝脱敏、非崩溃保持原 reconnect 且失败不冒充成功。
