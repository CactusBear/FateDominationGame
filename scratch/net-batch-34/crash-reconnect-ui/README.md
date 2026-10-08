# crash-reconnect-ui

## 目标

这是只读仓库的最小 V4A 交接包。它把本机权威 worker 崩溃恢复接入现有两个重连控件入口：大厅 `lobby_screen.gd` 与战局 v2 `v2_view_presenter.gd`。

## 代码说明

- `scripts/net/session/lobby_session.gd`
  - 新增 `reconnect_after_worker_crash()`，不创建新状态模型。
  - 只在当前 `authority_host` 存在、且其 `diagnostics()` 明确返回 `worker_crash_waiting == true` 时调用既有 `recover_worker()`。
  - 恢复失败立即返回 `ERR_UNAUTHORIZED`，不继续走重连；只写入固定的“本机权威恢复未获批准”，不携带认证密钥、指纹、恢复票据、PID、实例号或文件内容。
  - 恢复成功后清理已有错误并调用原 `reconnect()`，因此恢复进度仍由现有 `recovery.json`/worker 恢复链负责。
  - 没有 `authority_host`、没有崩溃等待状态，或诊断未声明该字段时，保持原重连路径。
- 两个 UI 补丁
  - 真实 `Reconnect.pressed` 仍进入现有 `_reconnect()`，只是把调用从 `session.reconnect()` 换成集中入口。
  - 没有自动认领、没有客户端自报身份、没有新增恢复票据或数据模型。
- `crash_reconnect_ui_test.gd/.tscn`
  - 场景里是真实 Godot `Control` 和 `Button`。
  - 测试通过 `Reconnect.pressed` 信号进入继承的生产 `_reconnect()`，不是直接调用 `recover_worker()`。
  - 覆盖：崩溃等待→恢复→重连；恢复拒绝→不重连且脱敏；非崩溃→不恢复且沿用普通重连。

## 预期静态/运行命令

在补丁应用到仓库后，使用项目 Godot 运行：

```sh
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe \
  --headless --fixed-fps 60 --path . \
  --scene res://scratch/net-batch-34/crash-reconnect-ui/crash_reconnect_ui_test.tscn
```

本交接轮按要求未启动 Godot；因此没有伪报 `RESULT`。
