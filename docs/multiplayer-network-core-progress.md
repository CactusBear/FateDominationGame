# 联机网络基础组件实施记录

## 本批实际完成

- `scripts/net/enet_transport.gd`：真实 ENet UDP 通信，自选端口且端口冲突不自动改端口；可靠消息、连接来源 ID、基础数据白名单、包长和每次 poll 包数限制。
- `scripts/net/room_state.gd`：显式容量、选人模式、AI 数量、准备状态、房主转让和踢人、断线保留座位；不会将真人断线转成 AI。
- `scripts/net/lobby_session.gd`：真实消息接入房间状态，客机身份取自传输层而不是消息 actor；请求序号拒绝重复，主机广播快照。
- `assets/scenes/main_menu/multiplayer_lobby.tscn` 与 `scripts/net/lobby_screen.gd`：独立功能验证大厅，建房、自选端口连接、已有选人模式、AI 设置、成员与准备状态、离开与清缓存。未改主菜单入口，未开放进入正式游戏。
- `scripts/net/data_catalog.gd`：扫描已有类别的模板和同目录素材，SHA-256 内容清单，房主选中集合的去重与显式冲突来源选择；检查已声明的 requires。
- `scripts/net/content_cache.gd`：哈希命名、大小和内容校验、临时文件落盘、引用保护、损坏缓存拒绝、主动清理未使用内容。

## 实际验收

完整输出见 `multiplayer-network-core-results.json`，逐套真实执行：

| 套件 | checks | 结果 |
|---|---:|---|
| net_transport | 11 | 通过；端口占用反例产生预期 ENet 建监听错误 |
| net_room | 16 | 通过，无运行错误 |
| net_lobby | 9 | 通过，无运行错误；真实本机 ENet 并非 mock |
| net_data_catalog | 78 | 通过，无运行错误；实际项目 data 扫描 |
| net_cache | 10 | 通过，无运行错误；真实写入、篡改与清理测试专属目录 |
| net_lobby_window | 5 | 通过，无运行错误；真实鼠标点击建房、加入客机、准备、保存画面 |

窗口图 `tests/runtime_reports/net_lobby.png` 已原生查看。当前大厅仅功能验证布局，尚未做最终视觉设计。

## 未完成及边界

这不是完整联机交付。尚无跨设备或公网验证，也没有可玩的完整网络对局。

- P2：合法操作、私有提示、全部显示字段、镜像与 v2 接线仍待做。
- 房间：设置变化后的主机/客机 UI 完整回填、模式切换容量重算、踢人与房主转让 UI、观战入口、选人协议、成员重新认证和重连凭据未做。进入 selecting 仅验证状态传播，不能称为已完成选人。
- 连接：超时 UI、密码或凭据认证、限速与恶意客户端资源保护需补充。ENet 基础通道不是安全加密通道。
- 数据：尚未传输分块或组装房间 data；模板内部图片路径和 JSON 字段完整安全检查、原语安全边界、全体确认 hash、跨条目资源引用、requires 全量补写未做。当前同目录清单是保守收集，不是已证明最小依赖闭包。
- 缓存：尚无跨组件共享的 pin 生命周期、总容量 LRU、断点续传。正式数据同步接入前不能把当前清缓存按钮当作完整使用中保护验收。
- 服务端：多房间单入口、房间子进程、控制台、配置文件、Windows/Linux 启动包未做。
- P2P：信令与 NAT 打洞未做，绝不以转发游戏流量替代。
- 死循环：预检和运行时保护未做。
- 存档：普通菜单录制/恢复接线与更多中局 UI 覆盖未做，沿用 P1 限制。

## 本批错误与修正

- 房间状态最初使用 disconnect 方法名与 Object 原生方法冲突，改为 mark_disconnected，随后真实专项通过。
- 房间消息最初未同步：Godot 字典点赋值生成 StringName 键，被传输层字符串键白名单拒绝；允许 String/StringName 字典键后实际 ENet 同步通过，仍拒绝 Object。
- 数据清单局部变量推断失败，显式 String 类型后通过真实扫描测试。

## 决策问题

本批没有新增必须由用户决定的问题。后续需要决定的事项只写 `multiplayer-open-questions.md`，不将技术实现未完成伪装成待用户确认。
