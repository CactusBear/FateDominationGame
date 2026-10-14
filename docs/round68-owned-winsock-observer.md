# Round68：可运行的最小自有 WinSock header 观察器

## 已交付及实际执行

- 新增 `tools/diagnostics/round68_owned_winsock_observer.py` 和同名 `.cpp`；未改 engine、DLL、生产代码、原测试、round63/round67 工具。Python 是受限执行入口；C++ helper 是内部 fixture 调试器，不是可用于游戏/恢复的通用抓包工具。
- 真实 MSVC 编译 exit0；纯 C++ ENet parser **63 case / exit0**。
- 普通 UDP **exit0**：两个线程、两个不同登记 socket，各发送/接收 seq1–3；12 次 header 读取全部只有 `[0,12)`，datagram 后52字节没有被观察器读取。18 个 API entry/return 完整配对，最大同时 pending=2。
- 两次无效 recv buffer 地址 `1` 实际返回 **-1 / WSAEFAULT 10014**；actor 的立即 `WSAGetLastError()` 与调试器同线程 TEB+0x68 一致。这两个返回的 buffer 读取次数为0；不是把预想的10035当事实。sendto 成功返回也完整配对，**未单独运行 sendto 错误返回 case**。
- 原版 Godot SHA256 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`，两个 bare `ENetConnection` 同进程分别绑定 loopback，握手、显式 `peer_disconnect()` **各一次 / exit0**。没有运行游戏项目、RSA/save/recover，未改 ENet timeout。
- handshake：10 API pairs / 18 header read regions，双向 CONNECT 与 ACK；close：14 pairs / 30 regions，双向 CONNECT/ACK，随后 DISCONNECT reliable seq2 与 ACK2。VERIFY_CONNECT 按白名单要求记 unknown，不读取其 connectID。
- 本轮合计 **42 API pairs / 60 header read regions**。编译、unit、raw、handshake、close 均有独立 held-Job 退出/active_owned_processes=0；报告和离线加强核验文件均真实读回。

证据根：`E:/scratch/isolated-ade1b96e02db40efac298cbb4c3c8489/`。

可执行产物：`generated/observer.exe`；冻结 C++：`generated/observer.cpp`；原始 stdout/stderr、`report.json`、`verification.json` 位于 `evidence/`。为交 main 保留此自有根，未删除产物。

```text
python -B tools/diagnostics/round68_owned_winsock_observer.py --execute
python -B tools/diagnostics/round68_owned_winsock_observer.py --execute --raw-only
python -B tools/diagnostics/round68_owned_winsock_observer.py --verify E:/scratch/isolated-ade1b96e02db40efac298cbb4c3c8489
```

最后一条已执行成功；它只离线读回，不重新启动 Godot，不覆盖既有 verification，因此对同根再次执行会明确拒绝覆盖。当前 Python 比执行时仅增加了离线 verifier 与更严的 evidence assertions；C++、已编译 binary 和冻结源哈希一致。

- C++ SHA256：`b2de931cd00dcc89c802545f55a8fc858446ec3b32dbfb71747aa15fa7257511`。
- verification SHA256：`8bd4f3223004542a302a99b259ad5d0961094a65ac96ac8f898ce7235f8b56c5`。

## 读取与返回配对边界

1. 仅 `CreateProcessW(DEBUG_ONLY_THIS_PROCESS)` 自己创建的 fixture，持有 process/thread handle；没有 attach 入口。上层 existing OwnedJob 在根线程恢复前绑定 Job，helper 核对 child 已在 Job，登记 PID 与 GetProcessTimes creation FILETIME。
2. 逐子进程模块登记 base/size/path，从子进程 actual IAT 取得 function address；解析该模块磁盘 PE 的实际导出和 forwarder，再核对 child code8。没有拿本机函数绝对地址套远程。编译 fixture 的 WSOCK32 imports 实际是 ordinal，按对应模块 export ordinal/name table 解析；Godot 是 named imports。
3. 三个实际 child 均验证 `sendto → WS2_32.dll+0x7980`、`recvfrom → wsock32.dll+0x1090`，以及 bind/closesocket；没有误挂统一 WS2_32 recvfrom。
4. bind 成功且 sockaddr 为批准的127.0.0.1、IPv4-mapped loopback 或 ::1、批准本轮两个端口才登记 socket；closesocket 成功注销。send 只批准登记 local 与批准 remote；recv 只有返回>0且长度不超 entry buffer capacity，source address 也在批准端点时才调用 header reader。不批准 scope 不读取 packet buffer。
5. 每线程 pending 栈和每 return site 引用计数；返回须匹配该线程栈顶 PC。API error 在任何 child 继续执行前从同线程 TEB 读取。软件断点恢复原字节、回退 RIP、single-step、重装；单步期间暂停其他自有线程。已排队的其他线程 breakpoint 延后处理，避免互相 SuspendThread。return sites 持续保留到 owned process 退出，不在最后一次已知返回时删除，避免排队 INT3 成为未知异常。
6. 模块卸载涉及任何 watched entry/return site，未知模块、越界、无法读/写、线程退出尚有 pending、未清 socket、second-chance 均 fail closed 并只终止持有的 owned child。**模块卸载负向分支与真正递归重入分支尚未额外造例执行**；已执行的是两线程并发共用 return sites。
7. packet reader 是精确 `(offset,size)` callback；不先读全包。ENet datagram header 2/4字节；checksum 额外4字节只跳过，压缩/未知 checksum 不读取 command stream。多 command 按官方固定结构大小与各 SEND/fragment 的 dataLength 跳过 payload，只读取下一 command header。CONNECT/DISCONNECT 只读取4字节 command header，connectID/data 不取；ACK允许额外4字节，输出仅可靠序号，PING允许 header。未知类型输出 unknown。

unit 覆盖5类 SEND/fragment payload skip 后继续 PING、checksum 有/无/未知与 compressed flag、52个截断长度；callback 对 payload 区域直接拒绝，证明不是整包读取后脱敏。普通 raw fixture 的 actor 可以自行比较64字节已知普通数据，但 observer 仅读取其12字节自造 header；这不涉及真实应用数据。

checksum=0 仅限本轮 generated bare ENetConnection：准确 commit `ed1daf0bf001b61586d9930840f2f1394092c079` 的 `host.c:89` 显式 `host->checksum = NULL`，`enet_connection.cpp:306–320` `_create` 直接调用 enet_host_create，生成脚本未调用任何 checksum/compression setter。原件 `evidence/official-host.c` SHA256 `7a4a2dd3a146c742c17df00237481b07c76a284bc167f0282bdac2d34c086e97`。这不是生产 host 配置证明；不授权观察生产。

## 暂停开销，不能宣称无扰动

| case | event-handler 暂停总计 ms | 最大单次 ms |
|---|---:|---:|
| raw | 468.194300 | 128.479000 |
| handshake | 12124.259300 | 5326.303800 |
| close | 12153.702800 | 5342.019000 |

这是 WaitForDebugEvent 返回后至 ContinueDebugEvent 前的 handler 测量，**不含事件投递延迟及单步期间其他线程暂停的调度间隔，是下界**。加载模块/反复读取 PE 磁盘文件开销很大；没有做无调试器对照，不能声称不改变时序或用来判断真实游戏 timeout 原因。

`SCRIPT_CLOSE` 是生成脚本的请求记录；`NATIVE_CONTROLLER` 是脚本打印 native ENetConnection.service 返回事件，不是 native 函数断点；`WIRE` 则是系统 API buffer 中按白名单读出的 header。三者分别保存，不混作同一种证据。

## 实际遇到的问题及未覆盖范围

前置尝试保留在各自 E UUID 根，未伪装成系统工具权限失败：MSVC min/max 宏冲突、中文编译输出 UTF-8 解码、compiler service 留在 Job、fixture import ordinal 未处理、并发已排队 breakpoint 的暂停处理、无效 buffer 的错误码预期不正确，以及一次 observer second-chance。最终冻结 source 的三 case 才是上述 GREEN；早期失败不能擦除，也不能把已通过小 fixture 升格为生产工具验收。

网络源文件获取曾遇到 web_extract private-address 拒绝及 GitHub API 403 rate-limit；随后 raw 官方 URL 的 curl 实际 exit0，原件已核哈希。没有下载 SDK，没有整引擎重编译。

尚未做 sendto 错误负向、真正同线程递归嵌套 API、module-unload 负向、无调试器时序对照、stop-service case、多进程双端 ENet。C++ helper 内部参数不是面向任意 EXE 的安全产品接口；**只能通过受控 Python 入口运行它生成的 fixtures**。恢复、真实 payload、实际用户28100、历史原因、发布验收均不在本轮结果内。
