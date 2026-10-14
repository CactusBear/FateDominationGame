# Round69：WinSock 观察器开销收敛与仍保留的恢复禁用

## 结论

完成了真实 profiling、整文件 bulk read、逐 process/module-load 静态缓存、最小事件读取、三个缺失小 case，以及独立无 debugger 对照。**没有运行真实游戏或恢复；仍不能授权恢复观测。**

本轮复现的约 5.6 秒暂停发生在 startup 的 CREATE_PROCESS 和初始 breakpoint/IAT-install，而非已经连接后的模块加载。原 round68 只记录总计/最大值，没有逐事件阶段；不能把本轮新 trace 冒充历史那条 trace。

优化后的网络活动期仍有 6–36 毫秒 handler 总暂停，原 handshake/close 的同输入网络窗口分别比独立对照长 10.443 / 17.533 毫秒。没有 zero-perturbation、任意性能阈值或生产授权。

## 写入与安全边界

仓库仅改 `tools/diagnostics/round68_owned_winsock_observer.py/.cpp`，新增 `tools/tests/test_round69_winsock_overhead.py` 与本文。原生产、测试、engine/DLL、round63/round67、隔离 runner、compiler helper 均只读。

- 自有 E UUID 根；上层 held-Job 在启动前绑定，debugger 只 `DEBUG_ONLY_THIS_PROCESS` 创建自己的 fixture，没有 attach。
- 原 raw 的两个线程、两 socket、seq1–3、64 字节普通字节和 3000ms socket timeout 保持；观察器只读 `[0,12)` header。ENet 原 8000ms fixture deadline 不变，没有修改引擎、timeout、checksum/compression。
- 对照使用另一独立子进程、同一 binary/script/端口/参数，但无 DEBUG flag、无 breakpoint、无 packet reader。顺序执行，每组各一次；不能把 n=1 当总体统计或冷磁盘结果。
- 优化前后复用本轮批准端口 59611、59612，先独占绑定确认空闲再关闭预约。新增比较根的端口格式/范围检查在 bind **之前**，拒绝 28100、字符串端口、重复或越界值；不检查/绑定用户 28100。
- native helper 只接受自身 raw actor 或固定 SHA 的 Godot 路径、固定 `--headless --path <own generated/project> --script res://fixture.gd -- <ports> <case>`。生成脚本 SHA 固定校验，没有任意 EXE 入口。仍只通过受控 Python 入口使用它，不是通用产品 debugger。
- 预解析仅 observer 自身静态 PE；引擎/系统模块在自有 child 的 module-load 事件才解析。启动前 artifact/hash 验证不是引擎解析缓存预热。文件获取最多三次，失败 fail closed；没有不限次数文件重试。

## Root-cause profiling（优化前真实基线）

证据：`E:/scratch/isolated-1c355d5264d2466e80c19ef1d9f0db47/`。

基线仅加计时和独立对照，仍使用原逐字节 `istreambuf_iterator` 和重复 `Image` 构造。原 engine 和生成 ENet 配置没有改；每个原 case 与无 debugger 对照各运行一次，全部 exit0、Job0。

handshake 的实际分解：

| 项目 | 实测 |
|---|---:|
| CREATE_PROCESS event #0（code=3，startup） | 5577.499900 ms |
| 初始 breakpoint event #39（code=1，startup） | 5600.975900 ms |
| 其中 IAT-install inclusive | 5600.922000 ms |
| startup 全文件读取 | 60 次，418540448 字节，12798.849600 ms |
| startup PE header parse | 60 次，0.498600 ms |
| export resolve inclusive | 7 次，91.990800 ms |
| import-name inclusive | 28 次，0.018000 ms |
| startup module lookup | 4 次，0.008700 ms |
| network-active module lookup | 10 次，0.020700 ms |

IAT-install 重新读取了 180858888 字节的 engine；CREATE_PROCESS 也读取它。重复磁盘读取/逐字节迭代才是秒级主因，不能把极小的 header parse 或 module lookup 当主因。inclusive 阶段互相包含，**不能相加**。

## 缓存实现及没有削弱的校验

1. `filebytes` 按长度一次分配并 bulk read，BCrypt SHA256 对本次实际内容计算摘要；没有 mtime-only 信任。MSVC 仍未添加 `/O2`，没有用缩短场景/timeout 制造加速。
2. `Image` 只在模块加载时建立 section、WinSock imports、named/ordinal exports、forwarder 的静态索引；静态结构只保存 RVA/token，不保存跨进程绝对地址。仅自身 PE 可在创建 raw child 前预解析；加载时重新验证该文件内容摘要。
3. `Module` 保存本进程 creation FILETIME、base、size、path/name、imagehash 和静态 Image；注册核对实际 child 的 DOS/NT headers、SizeOfImage、Machine、TimeDateStamp。`module()` 检查 creation/size/hash，并用区间索引查地址。
4. IAT-install 使用 cached RVA 索引，但**重新读 live child IAT slot**，解析实际 child 的 forwarder，并校验 remote code8 对应 source bytes。没有套本机 API 地址。
5. 新 breakpoint（含 return site）还检查 live first byte 对 cached source byte；每 breakpoint event 检查 source byte 与实际 INT3。事件期不重读磁盘 PE，只读必要 registers/stack、API error、sockaddr 和批准 header。
6. UNLOAD 先删除模块缓存，输出 `CACHE_INVALIDATE`，涉及 watched entry/return site 则拒绝；不能复用已卸载地址。原每线程 pending 栈、返回 site 引用数、排队 breakpoint/single-step 暂停恢复逻辑保留。
7. ENet exact-range reader 与 parser 不变；未知/压缩 stream 不读 payload，SEND/fragment 按长度跳过。原 parser 63 case 真实 exit0，cache-unit 5 个真实自身静态文件/内存身份控制 exit0。cache-unit 的人为 creation/base 控制不是系统事件 trace。

## 优化前后 handler 暂停（ms）

优化后证据：`E:/scratch/isolated-1b426974e3e240dbb87b8d329b53abfc/`。

startup 截止 first bind entry；network-active 从该 entry 到 child exit，**含 teardown**。bind 所在事件划入 active。它不是“仅 socket 已连接期”。

| case | 前 startup Sum / Max | 后 startup Sum / Max | 前 active Sum / Max | 后 active Sum / Max |
|---|---:|---:|---:|---:|
| raw | 476.579100 / 126.705000 | 57.764200 / 17.210700 | 8.336500 / 4.020400 | 5.718200 / 1.349000 |
| handshake | 12825.370800 / 5600.975900 | 743.654700 / 505.072200 | 10.112200 / 0.965100 | 11.990900 / 1.544000 |
| close | 12699.383600 / 5601.244700 | 840.603900 / 563.052300 | 14.202700 / 0.948600 | 21.683800 / 1.736900 |
| handshake-tail（新扩展） | 未运行 | 976.428700 / 690.503800 | 未运行 | 35.606700 / 1.605000 |

优化后 handshake startup 磁盘读取 48 次 / 234542136 字节 / 578.990600ms，内容 hash 99.781900ms，静态索引 inclusive 56.368600ms，IAT-install 0.179000ms。峰值现在是 CREATE_PROCESS 的首次完整 engine 校验，不是活动期 PE 重读。raw 活动期仍出现一次真实 DLL load，其 module-load inclusive 1.250500ms。

这些是 WaitForDebugEvent 返回后到 ContinueDebugEvent 前的 handler 测量下界。未包含事件投递、ContinueDebugEvent 或 single-step 调度间隔。新版本把 event snapshot 的复制放入计时，基线未包含这部分；保留的 JSON `pause_scope` 是兼容旧记录的宽泛描述，以此处和冻结源码的精确范围为准。raw actor 与 helper 同 binary，新增 BCrypt 静态依赖也可能改变 startup module 数；不能把整个 wall 差当单一变量的纯因果估计。

## 独立无 debugger 对照与对齐的 wall 差（ms）

比较使用实际 fixture 的单调时钟窗口：raw 从首个 socket/bind loop 前到 cleanup 后；ENet 从 create_host_bound 前到 destroy 后。两边执行相同脚本/actor、参数和网络输入。基线没有该内部 marker，不能补造基线网络 wall。

| case | debug child wall | control child wall | child 差 | debug fixture 网络窗口 | control 同窗口 | 网络窗口差 |
|---|---:|---:|---:|---:|---:|---:|
| raw | 105.989100 | 37.462900 | 68.526200 | 11.424200 | 1.893400 | 9.530800 |
| handshake | 1098.697900 | 337.840500 | 760.857400 | 27.426000 | 16.983000 | 10.443000 |
| close | 1210.814900 | 345.137500 | 865.677400 | 43.968000 | 26.435000 | 17.533000 |
| handshake-tail | 1546.950000 | 531.190800 | 1015.759200 | 286.527000 | 270.406000 | 16.121000 |

child 差扣除 fixture 网络窗口差，分别为 58.995400 / 750.414400 / 848.144400 / 999.638200ms；这部分包含 startup **和**窗口外的最后退出，不能称精确 startup wall error。对照缺少与 debugger first-bind event 同步的跨进程 QPC marker，精确 startup-only wall 分离仍是缺口。样本都是 n=1、顺序 warm 条件，wall 差没有置信区间，也不是无扰动上界。

原 `report.json.wall_comparison.active_wall_delta_ms` 使用 debug bind→exit 减 control fixture 窗口，结束点不同，不能用于 causal 判断。保留原件不覆盖；实际离线重算的 **`verification.json.cases.*.aligned_wall_comparison`** 才是上表同窗口结果。当前 Python 已改为直接写对齐结果。

### 握手后真实短窗口

独立生成的 handshake-tail 不替代原 handshake：两端真实 EVENT_CONNECT 后显式发送三次无 payload PING，继续 service 约 250ms，随后 destroy。仍是**一个 Godot 自有子进程内的两个 ENetConnection**，不是两个独立 worker。

实际 `HANDSHAKE_TAIL pings=3 elapsed_us=250373`；观察到六条 PING wire rows（send/recv 两方向读取），22 API pairs。以首次 fixture PING→exit 作为已握手后 subset：68 events，PauseSum **21.210500ms**、PauseMax **1.582500ms**，仍含 teardown。这个完整退出的小窗口可以交 main 阅读，但其暂停相对于原 2ms service loop 并非零扰动；**目前仍不可拿它运行真实恢复或证明历史恢复 timeout**。

## 缺失小 case 的真实补齐

同冻结完整运行同时执行：

- **sendto error**：INVALID_SOCKET、无效 buffer 指针1，系统实际 `-1 / WSAENOTSOCK 10038`；同线程 TEB error 与立即 WSAGetLastError 一致。未登记 socket、approved=0，零 packet-buffer 读取；不把它冒充 registered socket 的 WSAEFAULT。
- **同线程递归返回配对**：自有 noinline 导出 `Round69Recursive(3)`，四层 ENTRY、相同递归 return PC，真实按 seq4→3→2→1 返回，depth4→0。只能证明调用栈/共用返回地址控制；**没有构造或声称系统 WinSock API 真递归**。
- **module unload 拒绝**：同冻结 C++ 通过独立 DLL 编译分支生成 `owned-unload.dll`；真实 LoadLibrary→导出 marker→FreeLibrary。`ACTOR_UNLOAD requested=1` 后先失效缓存，再 `OBSERVER_FAIL_CLOSED watched_module_unload`，helper 预期 exit2；没有成功返回 FreeLibrary 的假记录，Job0。

之前 native-only 独立根 `E:/scratch/isolated-00e2427ab1094a7c9cd12f5794ede613/` 也真实通过这些控制，但完整运行证据以上述最终根为准，不拼不同冻结。

## 真实执行与全局冻结缺口

本轮三个执行根分别为 profiling 基线、native-only 控制、优化后完整小组，没有重复运行真实恢复。

完整组：MSVC `/utf-8 /W3 /WX` 编译 exit0、无 compiler warning；63 parser case + 5 cache identity case；raw/handshake/close/tail 与各独立 control 均 exit0；unload 预期 exit2。正常观察 case 合计 **64 API pairs / 114 header read regions**。14 个持有 Job 的编译/执行记录都 `exited=true, active_owned_processes=0`。

但总命令 exit1、原 `report.json.passed=false`：2058 份只读指纹中，两份其他 helper 在该执行窗口发生变化：

- `tools/tests/test_round71_final_candidate_scheduler.py`
- `tools/tests/test_round71_private_consumer_retirement.py`

本代理没有写这两份文件。原前后 hash 全保存在 report/verification；具体改写者不由这份 trace 证明。其余记录（含生产/测试/engine/DLL、round68 旧证据）前后相同。**不能将局部小 case 全通过改标全仓同冻结 GREEN。**

离线 verifier 真实 exit0，验证源/binary/DLL/script/log 原件和全部实际 case，但明确输出 `overall_passed=false, same_global_freeze=false`。它不重跑 child、不修改原报告，也不授权生产。专属 unit **11 tests / exit0**，消费真实 archive、拒绝历史无 profile 的 trace、拒绝不合格端口，并保证 readonly failure 不被 relabel GREEN；unit GREEN 不消除总冻结缺口。

```text
python -B tools/diagnostics/round68_owned_winsock_observer.py --execute --compare-root E:/scratch/isolated-1c355d5264d2466e80c19ef1d9f0db47
# 实际 exit1：小 case 均完成，但其他 helper 只读指纹变化。
python -B tools/diagnostics/round68_owned_winsock_observer.py --verify E:/scratch/isolated-1b426974e3e240dbb87b8d329b53abfc
# 已实际 exit0，只验证真实证据；再次调用拒绝覆盖 verification.json。
ROUND69_EVIDENCE=E:/scratch/isolated-1b426974e3e240dbb87b8d329b53abfc python -B tools/tests/test_round69_winsock_overhead.py
# 11 tests / exit0，无新增网络/游戏执行。
```

## Artifact fingerprints 与交接

- 最终 native C++/generated source：`2f58cbed9458d8fa055b7f132633729baadd62c8bca514e0503d6a2cb63da38e`。
- 最终 observer.exe：`2e5ea4ce799d7c1bcab2f4ba343c86fcfc93a197acdf841e96bb0638ce647248`。
- 最终 owned-unload.dll：`ba6de9ad7e4e298f21109d214646e7adc964929e599aac56a7e38017d174ca8c`。
- 实际执行冻结 launcher：`edb74766f45db25a7fef5f10249840ad5393eb44e95e88191b18896232fcaef5`；当前 Python 后续仅修离线对齐 wall/blocked-readback 与静态 pre-bind/artifact gate，未改 native/scenario source，未补造 runtime trace。最终 verifier fingerprint 自记于 verification。
- verification.json：`cd18fd41f5a74c3e7d29e74402e9417b124a5ec9bb23943a87c2bf70bb939c4b`。
- round68 原 C++/generated source：`b2de931cd00dcc89c802545f55a8fc858446ec3b32dbfb71747aa15fa7257511`；原 verification：`8bd4f3223004542a302a99b259ad5d0961094a65ac96ac8f898ce7235f8b56c5`，原件未覆盖。

给 main：读取最终 `evidence/verification.json`、四组 stdout/control logs 与冻结 source；保留 active 仍有扰动、startup-only control wall 未精确分离、全仓 readonly 同冻结未通过、没有系统 API 真递归/多进程双端/真实恢复验收这几项边界。没有新生产授权。
