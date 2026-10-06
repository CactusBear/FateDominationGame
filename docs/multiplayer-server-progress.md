# 独立服务端启动与当前验收边界

## 启动

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
  "startup_seconds": 30
}
```

Linux 使用本机实际绝对路径替换这两个目录。以上 Linux 命令尚未在 Linux 主机运行，不代表跨平台导出已经验收。

- 仅对外开放 `port` 的 UDP；内部房间只监听 `127.0.0.1`。
- 防火墙与端口映射均由部署者配置，不自动放行。
- `max_rooms`、`max_clients` 与启动时限是部署预算，不是游戏规则上限。
- `data_root` 是服务端管理员指定的本机数据。当前房间使用该目录完整批准数据集；客机上传数据的房主选择、服务端端内重新批准入口尚未接齐。
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

- `net_server_rooms_test`：真实启动两间房间、独立 PID 和缓存、接入客户端、杀死其中一间，另一间继续存活。
- `net_server_gateway_test`：两个客户端通过同一外部端口进入同一房间、接收快照、下载实际字节、拒绝非房主管理。
- `net_server_cli_test`：真实 CLI 子进程监听、房间列表、启动权威子进程并响应大厅请求、网关突然退出后主管心跳停止，房间自行退出并撤销就绪报告。
- `net_server_lobby_window_test -- window`：真实创建与加入按钮、房间 ID、AI 控件及管理权转让；原生查看 `server_lobby.png`。
- `net_server_match_test -- window`：两个客机完整下载批准内容、校验并确认、选人、两个人类席位提交网络指令、真实独立权威进程达到游戏结束；正式 v2 全程渲染，隐私手牌持续过滤，本机规则玩家数据未被修改。原生查看 `net_server_match.png`。

测试仅在本机 Windows 执行。完整对局的决策策略复用现有网络测试代理，不代表所有决策都逐次点击界面完成。

## 未验收与待做

- Linux 实机及 Windows/Linux 导出包。
- 公网、防火墙、异地多人、高延迟与丢包。
- 房间发现的游戏内列表与服务端房间停服管理入口。
- 房间持久化、存档菜单、存储回收策略与服务端完整开局预检。
- 网关主管存活保护不等于规则死循环保护；规则执行挂住的检测与最后可信存档保护尚未实现。
- 大清单分片、多客机上传、总内存与图片解码预算。
- 本机 C 盘本轮曾降至约 8 MB；只清理本轮失败测试产生的两份目录，后续服务端测试使用 E 盘输出。不清除用户存档或其他缓存。
