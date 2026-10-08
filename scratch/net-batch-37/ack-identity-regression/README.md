# ACK / 身份桥 Godot Node 反例专项

## 范围
- 直接 preload 生产 `MatchLobbySession`，覆盖旧 ACK、当前 ACK、未来/负数/错误类型 ACK。
- 直接 preload 生产 `LanWorkerIdentityBridge`，覆盖已认证 pending 过 deadline、未认证原 deadline 超时、恢复期间 pending 保留。
- 不启动真实规则重放；只用最小传输/账本/控制边界替身驱动真实模块入口。
- 不修改生产文件；本目录仅为 scratch 交接产物。

## 主代理运行
在项目根目录执行：

```text
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . --scene res://scratch/net-batch-37/ack-identity-regression/ack_identity_regression_test.tscn
```

预期输出 `RESULT ack_identity_regression PASS`，并生成 `runtime_evidence.json`。

## 本次静态核对
- `gdparse`：退出码 0。
- 当前子代理未运行 Godot；运行验收由主代理执行。
