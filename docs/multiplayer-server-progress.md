# 独立服务端启动与当前验收边界

## 独立导出包与 Linux WSL2 新增验收

- 新增复核：Windows release 控制台建房与管理专项 42 条通过；Linux release 建房、双房间配额、保存及真实中局崩溃恢复至终局 35 条通过。后者日志为 `server-dist/linux-recovery-managed-window.log`，不再把只到恢复中局的早期日志当作全套通过。
- 身份增量：源码 CLI 与 Windows release 的密钥挑战、自动登记、落盘及认证后建房各 22 条通过；真实窗口登记、同密钥改名、管理员入口实时授予/撤销 11 条通过，截图已原生检查。这些结果对应后续恢复密钥绑定安全补丁合并前的版本，合并后必须复跑。
- 系统信号增量：Windows 源码服务端真实中局 Ctrl+C 保存式关服专项 22 条通过，已确认真实进程正常退出、就绪标记清理及存档重放同一中局。未录制拒绝分支的行为断言已通过，但夹具读取不存在的存档目录产生引擎错误；夹具已改为先检查目录，干净复跑仍待执行。Windows/Linux release 信号分支尚未验，不能据此替换原 `stop` 的发行包证据。

- Linux 中局崩溃恢复新增通过：`net_server_linux_recovery_test` 27 条窗口断言全绿，真实终止 Linux 房间子进程、原真人凭据重连、恢复同一中局并继续终局，截图已检查。日志 `server-dist/linux-recovery-managed-window.log`；受控执行脚本 `D:/LinuxVirtual/run_recovery_acceptance.py` 同时管理测试网关与客机生命周期。此前中断和超时日志保留，不算通过。Linux 房间写 Ubuntu 原生文件系统，Windows 客机同步目录独立放在 E 盘；不可把客机文件通过 WSL UNC 写入服务器目录再据此判断网络性能。
- 恢复测试的无凭据反例已修正 `join_server` 参数顺序，确保真正请求被测房间，而非误把提示文字当作房间 ID。

- Windows release：`tests/net_server_export_test.tscn` 12 条断言通过，包含启动、服务器名称及公告、独立房间子进程、客户端加入与网关异常退出后的孤儿清理。日志：`E:/Projects/Godot/FateDomination/test/server-dist/export-runtime-info-test.log`。
- Linux release 已导出至 `E:/Projects/Godot/FateDomination/test/server-dist/linux/`，需要一起部署 `FateServer.x86_64`、`FateServer.pck`、原生扩展库和外置 `data` 目录。Linux 使用 `./FateServer.x86_64 --headless -- --config server.cfg`；首次生成配置后退出，检查配置再启动。
- 实测环境：WSL2 发行版 `FateLinux`，Ubuntu 24.04.5，普通用户 `fate`，虚拟磁盘位于 `D:/LinuxVirtual/Ubuntu`。Windows 客户端经 WSL 网卡地址连接 Linux 服务端，而不是在 Windows 上执行 Linux 模板。
- `net_server_remote_test`：8 条通过。实际建房、中文信息、204 项批准清单及文件下载，大小和 SHA256 一致。
- `net_server_linux_match_test -- window`：13 条通过，两名 Windows 客户端完成同步、选人和规则操作直到终局，私有手牌保持过滤，客户端未执行本地规则。截图已原生检查；日志为 `server-dist/linux-fullmatch-window.log`。
- `net_server_linux_preflight_test`：14 条通过。初始目录仅作为候选；Linux release 真正启动隔离校验子进程并运行随机模拟，报告返回后由房主确认，才发布数据并下载实际内容。
- 远端测试地址和端口通过 `FATE_TEST_SERVER_ADDRESS`、`FATE_TEST_SERVER_PORT` 显式传入，WSL 重启可能改变地址，不把某次 IP 固定为部署配置。
- 仍未验：公网/异地 NAT、Linux 系统信号安全关服和长期负载。WSL2 通过不代表这些项目通过；身份恢复绑定、密码安全边界和各模式名单权限仍按主计划继续实施。

## 启动

### 角色与信令预算

- `server.cfg` 的 `[server] roles` 支持 `["game"]`、`["relay"]` 或两者同时启用。纯信令无需游戏数据或房间存储目录，不监听游戏 UDP；旧 `p2p_signaling` 仍兼容，但与显式角色冲突时拒绝启动。
- `[relay]` 已接入 `signal_rate_limit`、`max_packet_bytes`、`ice_timeout_sec` 与 `rooms_per_ip`。消息速率按连接计，建房配额按真实 TCP 来源 IP 计；客机加入不占建房配额，房主断开释放配额。
- Windows release 纯信令验收：14 条通过，日志 `server-dist/export-roles-test.log`。Linux release 在 WSL2 中实际运行：7 条通过，覆盖真实 WebSocket 握手、建房、限流断开、游戏 UDP 未监听和无引擎错误；探针与结果在 `D:/LinuxVirtual/verify_relay_release.py`、`D:/LinuxVirtual/relay-release-summary.json`。
- 两平台均已更新导出包。上述结果不包括密码、管理权限、终端命令、房间码过期、STUN 下发和公网 NAT 验收。

使用 Godot 4.7.2 控制台或 Linux Godot 命令行运行本项目：

```text
godot --headless --audio-driver Dummy --path 游戏目录 --scene res://assets/scenes/main_menu/server_cli.tscn -- --server-gateway --config 服务端配置.json
```

配置必须显式声明 `port`、`data_root`、`storage_root`。例如：

```json
{
  "port": 24680,
  "bind_address": "*",
  "data_root": "E:/Projects/Godot/FateDominationGame-master/data",
  "storage_root": "E:/FateServer/rooms",
  "max_rooms": 16,
  "max_clients": 96,
  "internal_port_base": 52000,
  "internal_port_count": 128,
  "startup_seconds": 30
}
```

Linux 使用本机实际绝对路径替换这两个目录。以上 Linux 命令尚未在 Linux 主机运行，不代表跨平台导出已经验收。

- 仅对外开放 `port` 的 UDP；内部房间只监听 `127.0.0.1`。
- 防火墙与端口映射均由部署者配置，不自动放行。
- `max_rooms`、`max_clients` 与启动时限是部署预算，不是游戏规则上限。
- `internal_port_base` 与 `internal_port_count` 明确内部 UDP 端口范围；未声明数量时默认 128。房间管理器跳过本进程已分配和实际无法绑定的端口，不修改 Windows 排除项、不越过配置范围。范围全不可用时在启动子进程前拒绝。对外 `port` 仍严格使用配置值，不自动换端口。
- 探测 socket 关闭后到子进程绑定之间存在竞争窗口；预探测不是原子预留，最终仍以子进程实际绑定与就绪报告为准。
- `data_root` 是服务端管理员指定的本机数据。房间初始采用该目录批准数据集；大厅房主现可显式勾选客机提供的条目，由服务端下载、隔离校验和重新批准，客机不执行本地规则。完整副本不因提供者掉线或撤回共享失效。
- 不接受远端文件路径、脚本路径、进程参数或报告位置。
- 可选 `status_file` 写出实际监听端口及当前 PID 的 JSON 状态报告。
- 网关转发仅属于独立服务端模式；P2P 的信令辅助服务器不得套用此游戏流量转发逻辑。

## 游戏内入口

联机大厅选择“独立服务端”，填地址与端口。

- 创建：填房间名称，点击“在服务端创建房间”。创建后房间 ID 出现在输入栏，可复制给其他玩家。
- 加入：填房间 ID，点击“加入”；观战开关沿用现有入口。
- 房主管理、AI 数量、准备、同步、选人和进入对局沿用现有大厅。
- 客机必须实际下载并校验批准清单，再发确认，才能开局。
- 服务端不占人类席位，首位玩家成为房间房主；规则仍仅在独立房间进程运算。

## 实测

- `net_server_rooms_test`：真实启动两间房间、独立 PID 和缓存、接入客户端、杀死其中一间，另一间继续存活；退出房间可从原 `config.json` 重启，复用逐文件校验通过的数据目录，并用原恢复凭据重新连接、恢复成员与房主权限，23 条断言通过。对局存档自动恢复入口已接线，但完整“对局中崩溃—所有真人重连—恢复到同一局面”专项仍需单独验收。
- 内部端口专项：真实占住配置范围首端口后，两间权威进程仍分别使用范围内其他端口；范围全部占用时不启动子进程。CLI 夹具确认公开入口 TCP 与 UDP 均可绑定，实际子进程遵守配置的内部范围。`tests/runtime_reports/server_internal_port_regression/final-summary.json` 四套共 50 条通过，无引擎错误；含服务端窗口完整对局 12 条，并已原生查看终局截图。最初网络回归的双房间失败使用了 Windows UDP 排除范围内的 50152、50153，原失败证据保留，未改成通过。
- `net_server_gateway_test`：两个客户端通过同一外部端口进入同一房间、接收快照、下载实际字节、拒绝非房主管理。
- `net_server_cli_test`：真实 CLI 子进程监听、房间列表、启动权威子进程并响应大厅请求、网关突然退出后主管心跳停止，房间自行退出并撤销就绪报告。
- `net_server_lobby_window_test -- window`：真实创建与加入按钮、房间 ID、AI 控件及管理权转让；原生查看 `server_lobby.png`。
- `net_server_match_test -- window`：两个客机完整下载批准内容、校验并确认、选人、两个人类席位提交网络指令、真实独立权威进程达到游戏结束；正式 v2 全程渲染，隐私手牌持续过滤，本机规则玩家数据未被修改。原生查看 `net_server_match.png`。
- 批准文件大清单已支持分片，网关按同一可靠素材通道转发完整清单及其分片。底层改动后服务端完整窗口对局 12 条通过；大清单、直连分帧和真实卡图的最新专项见 `docs/multiplayer-transfer-progress.md`。该证据不等于服务端端内重新批准已接齐。

测试仅在本机 Windows 执行。完整对局的决策策略复用现有网络测试代理，不代表所有决策都逐次点击界面完成。

## 未验收与待做

- Linux 实机及 Windows/Linux 导出包。
- 公网、防火墙、异地多人、高延迟与丢包。
- 房间发现的游戏内列表与服务端房间停服管理入口。
- 房间持久化、存档菜单、存储回收策略与服务端完整开局预检。
- 网关主管存活保护不等于规则死循环保护；规则执行挂住的检测与最后可信存档保护尚未实现。
- 提供者目录分片已接通并验证超 1 MiB 目录经公开网关双向到达、重新批准及原字节下载；进度见 `docs/multiplayer-transfer-progress.md`。多客机文件上传和所有下载与解码入口的完整预算覆盖仍待做。
- 本机 C 盘本轮曾降至约 8 MB；只清理本轮失败测试产生的两份目录，后续服务端测试使用 E 盘输出。不清除用户存档或其他缓存。
