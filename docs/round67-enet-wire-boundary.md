# Round67：ENet wire 替代观察预检——明确缺验证，不运行恢复

## 结果

`TOOLBLOCK_WIRE_OBSERVER_NOT_VALIDATED`，真实预检 **exit2**。已验证源码调用链、实际宿主 import/IAT 槽以及本机系统导出的真实归属；**没有已验证的 live wire observer**，所以按预检门槛停止。独立 ENet 三 case、RSA/saveclose/recover、continuation 均 **0 次**，不报 sourcePASS、timeout 或根治，也不能排除收到对端 explicit DISCONNECT 或判定哪端先发。

新增代码是可执行的安全预检，不是伪装完整工具的 stub。它只读 EXE/DLL/source 元数据及本进程加载的导出代码8字节，不启动进程、不 attach、不装断点、不打开 socket、不读取任何 datagram/业务 payload/票据/密钥/恢复内容。不触碰用户28100。没有新 owner，因此新 Job0 为“不适用：未创建进程”，不能拿历史 Job0 冒充本轮验收；安全控制记录空数组，恢复场景 exit 为 null（未启动），不是 exit0。

## 新发现：import DLL 与导出真实归属不能猜

- 宿主 SHA256 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。官方完整 commit `ed1daf0bf001b61586d9930840f2f1394092c079`，URL/下载成功或错误、字节数及逐文件SHA已归档。
- 同提交 `modules/enet/SCsub:13–28` 编入的是 **thirdparty/enet/enet_godot.cpp**，不是传统 ENet win32 scatter/gather 实现。
- `enet_godot.cpp:584–621` 将 ENetBuffers 拼成一个 datagram，调用 Godot socket `sendto`；624–647 收包经 `recvfrom`。普通 ENetUDP 经 NetSocket，DTLS 则另有路径；这里只建立普通路径源码关系，不冒称恢复现场动态走过。
- `drivers/windows/net_socket_winsock.cpp:428,485` 实际使用 **::recvfrom / ::sendto**。实际宿主 PE imports 证实两者来自 **WSOCK32.dll**，对应磁盘 IAT 槽 RVA `0xad801c0` / `0xad801d8`；不是内部 ENet RVA，不作断点。
- 宿主没有 `WSASendTo/WSARecvFrom` imports。不能因为 WS2_32 提供它们就假设 Godot 走这些入口。
- 按现 round63 API debugger 的方法：先 GetProcAddress，再 GetModuleHandleEx(FROM_ADDRESS) 取得真实 owner module，核对磁盘 PE export 与本进程代码8字节。实测 **WSOCK32!sendto 解到 WS2_32.dll+0x7980，但 WSOCK32!recvfrom 解到 wsock32.DLL+0x1090**，接收存在 shim；随便统一挂 WS2_32!recvfrom 不等于已验证宿主导入入口。
- DLL SHA256：WS2_32 `df6c9b538a8cba3042f34bba94b30ca479b3cf790f14d6cad4eae0e647fa0976`；WSOCK32 `7c6658e8ddb19e10679c13050bc7febc33d190b162b653ebafb0da6e7d292519`。上述是**本进程导出验证**，不是 owned gateway/worker remote bytes 或 live resolved IAT 验证。完整记录显式 `owned_remote_address_verified=false`。

## 停止的具体验证缺口

1. 现 `round63_observer_lock_contract.py:168–180` 有实际模块/remote bytes 导出验证，但 main 针对文件 API；没有已运行的 sendto/recvfrom entry+return 配对、同线程 API 错误读取、成功 recvfrom 实际长度和 source address 绑定。原 native debugger 更不支持安全 wire 分类；本轮均未改。
2. 没有已验证的自有进程 creation-time、登记 socket 生命周期及双向 loopback local/remote tuple 过滤器。端口号本身不能授权读取所有 socket，也不能把 unknown remote 当已登记 worker。
3. `protocol.c:1031–1033` 的 headerSize 是2或4字节，再由 **host->checksum 配置**决定额外4字节；checksum 无独立 wire flag。没有真实配置证明时不能猜偏移，否则 checksum 字节可能伪装成 DISCONNECT。
4. `protocol.c:1053–1087` 先解压 command stream，再验 checksum。压缩段包含 SEND data，读取/解压它违反本轮“严禁读取业务payload”边界；必须只保留长度/方向 unknown。这样有覆盖空洞，不能以未见 explicit packet 证明不存在。
5. `protocol.c:1097–1186` 为多 command；`protocol.h:146–175` 声明各 SEND/fragment header 的 dataLength。安全读取器必须只读白名单控制字段，并按已验证的固定长度跳过 SEND payload。不能先 ReadProcessMemory 全包再 redact；CONNECT/DISCONNECT 的 data/connectID 等也不应随整结构输出。当前没有这样的安全 reader/parser 已经通过 truncation、多command、fragment、未知checksum和compression门槛。
6. 普通 ENet 双端三小case（自然握手、显式close、停止peer service的已声明负向）每个一次尚未运行；debugger pause/观测开销也未测。没有这些验证就启动真实恢复，会将 debugger 诱发断线与自然原因混淆。

这是**缺实现和缺验证的预检阻断，不是 WinSock 替代观察在原理上不可行**。没有开始长期搭 debugger；不猜内部地址，不搜近似PDB，不改timeout/setter，不重试seed，不给production patch。Round63 原结论及旧约4.95秒gap的 unknown 边界保持。

## 执行与产物

```text
python -B tools/diagnostics/round67_owned_enet_wire_observer.py --self-test
python -B tools/diagnostics/round67_owned_enet_wire_observer.py --root E:/scratch/isolated-3cf9de2ed3ee48ecb4243b9ccf60d788
```

- self-test 最终真实 **3 tests / exit0**：实际宿主 imports、实际系统导出/代码一致、PE越界拒绝。仅证明分析器，不是协议分型三case或产品测试。
- 首次 self-test 曾因错误假设 imports 来自 WS2_32 而 exit1；真实列出 imports 后修正为 WSOCK32，并验证 shim；没有改宿主或忽略失败来宣通过。
- 预检 **exit2**，报告读回 SHA256 `2e132e2ed8fa97e63aada83cb8ce546461964fa1ce218b2898c6b994587c4e76`。
- 新诊断源码与 `executor.py` SHA256 `22dee334a3cd1ecfabaa3a66a39abbd7a88dc3062b7f6713cade5a7cea671785`。
- 同根：`report.json`、`executor.py`、`downloads.json`、`source/`、`preflight-unit.stdout.log`、`preflight-unit.stderr.log`、`preflight.stdout.log`、`preflight.stderr.log`。
- 当前 lobby_session SHA256 `9541688289a80f59677a396e24ac7e885eb6552558a3edf0ab16baacf72b9e3b`，本次13个只读相关输入before/after一致；这是当前源码采样，不是已执行的自足恢复freeze。没有合并旧恢复记录。
- 下载过程中错误路径404和compress.c TLS EOF保留于downloads；实际网络调用路径/协议原件已取得并核哈希，未捏造缺失源码。

仓库仅新增 `tools/diagnostics/round67_owned_enet_wire_observer.py` 与本文；原engine/DLL、production/session/transport/probe/runner/测试全部未写。尚未取得首worker断线前双向packet、ACK停止、脚本close状态的同窗口因果证据。
