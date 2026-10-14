# Round30：纯信令隔离与生命周期

## 结论

- 新增 `tests/pure_signal_lifecycle_contract_test.gd/.tscn`，在无 autoload 的独立工程中实际执行：`RESULT pure_signal_lifecycle_contract checks=55 failures=0`，退出码 0。
- 正式生产 `server_bootstrap.gd` 的 `--server-signaling --config` 路由实际 READY，核对本次日志 PID 与持有进程句柄、实际 TCP 可连接；发送真实 CTRL_BREAK_EVENT 后自身退出 0，未使用测试 READY、`--quit-after` 或测试 shutdown 替身。
- 本轮未复现信令脚本原生 ERROR、引用环或未关闭连接。已验证 weakref 释放、正在握手的 TCP 回收、WebSocket 回收、重复 close、关闭后 poll、同对象重新 listen。因此 **不对已有生产信令脚本作无根因改动**。其已有工作树改动保留，不覆盖其他人的内容。

## 耦合与边界

`server_cli.gd` 属于 game/gateway 入口，relay-only 显式拒绝；纯信令由 `server_bootstrap.gd` 独立无 autoload 路由启动。只复制生产 bootstrap、process-signals、signal-server、invite、webrtc-link 与原生 signals 扩展；不复制规则、data、session、authority、gateway、manager、worker。邀请码校验器复用原有 SDP/ICE 白名单，未改变任何 ICE 或游戏政策。

仓库内未找到名为 `server_cli` 且支持 `mode signal` 的外层发行启动器；**本报告不宣称外层启动器/Job owner 已验收**。本轮实际执行的是生产 GDScript 单进程入口。发行工具由另一个写入者独占，未修改。

## 实际验收

- 真实 WebSocket create/join、成对 offer/answer 转送。
- 未配对 answer、nonce 不匹配、重复 offer/answer 拒绝。
- `game_command`、`snapshot`、`approve_data`、`archive`、`restore` 消息拒绝，其他客户端未收到载荷。
- create 中夹带 data_root/storage_root 拒绝。
- 畸形 UTF-8 WebSocket 文本真实断开，没有原生错误。
- 房主断开删除信令房间，客机收到 room_closed；关闭清空 clients/rooms，连接进入 CLOSED。
- 原始 TCP 已接受但尚未 Upgrade 的连接关闭回收。
- 服务及邀请码校验器/transport weakref 全部释放。
- 三次正式入口负向配置分别夹带 data_root、storage_root、record_matches：全部退出 2，无 READY。这些拒绝用例的 `push_error` 是预期配置拒绝，不计为正常生命周期原生异常。
- 正式单进程 READY：PID 31948、TCP port 9255、roles=[relay]；CTRL_BREAK_EVENT 自身退出 0；正常日志无 ERROR/SCRIPT ERROR/ObjectDB leaked。

## 命令与隔离

Godot：`D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`。

专项：`--headless --fixed-fps 60 --path E:/hermes-runs/round30-signaling-isolation --scene res://tests/pure_signal_lifecycle_contract_test.tscn`。

生产入口：`--headless --fixed-fps 60 --path E:/hermes-runs/round30-signaling-isolation --scene res://bootstrap.tscn -- --server-signaling --config E:/hermes-runs/round30-signaling-isolation/signaling.json`。

每次最终验收显式重定向 APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 至独占 E 目录；实际 `OS.get_user_data_dir()` = `E:/hermes-runs/round30-signaling-isolation/environment/APPDATA/Round30PureSignal`。180 秒专项看门狗，无窗口。

初次尝试错误地仅使用绝对 custom_user_dir，Godot 实际退回 C:/Users/Administrator/AppData/Roaming/Round30PureSignal；追加实际路径断言后发现并修正夹具环境，最终所有用例在 E 盘重跑。初次启动轮次还误读旧 native-entry.log，导致 READY PID 判据失败并仅回收自己持有的 Popen 进程；最终删除旧日志后使用本次 READY + 句柄核对，不将这些初次结果拼入最终通过。

## 证据与缺口

证据归档：`E:/hermes-runs/round30-signaling-evidence/`，含 contract.log、entry-result.json、entry.log/native-entry.log、三份负向日志与 negative-results.json、真实入口驱动脚本、最终拥有文件 SHA256、无残留自有 Godot 进程快照。隔离工程及运行数据随后回收。

尚未覆盖：外层 mode signal 启动器和原生 Job owner 强制终止；跨网络 NAT/真实 ICE；窗口 X。测试 offer/answer 是协议合法的最小 SDP，不宣称建立 WebRTC 游戏数据通道或规则权威。这些边界不能由本次本机信令专项替代。
