# 原生进程所有权补丁 v6（只读交接）

## 交付与已验证结果

- 完整补丁：`ownership-v6.patch`；对应文件：`overlay/`；原文件快照：`baseline/`；哈希清单：`manifest.json`。
- 补丁共 8 个文件：原生核心 `.hpp/.cpp`、GDExtension 绑定 `.cpp`、注册入口、SConstruct、房间管理器、两个既有 GDScript 测试。
- Windows MSVC 和 Linux GCC 都实际编译、链接了完整 GDExtension，不仅是原生核心。
- Windows 和 Linux 都实际启动了独立 C++ 测试子进程，验证令牌/PID 错配拒绝、退出检测、句柄定向终止、存活句柄禁止释放、析构清理和参数引用。
- Linux 额外通过真实 seccomp 过滤器禁用 clone3，确认能力检查与 spawn 失败关闭，不回退为 fork+PID kill；额外验证外部 reaper 已回收子进程后 pidfd 仍能准确报告退出。
- `verify_all.py` 的 7 个阶段退出码均为 0，完整日志在 `logs/`。GDScript 使用 gdtoolkit 4.5.0 静态解析；生产基线 SHA-256 未变；`git apply --check` 成功。
- **未运行 Godot、未修改生产、未接触凭证、未 commit。** 这不是 Godot 运行验收，也不是 LAN/P2P 或崩溃后对局恢复验收。

## 查明的现状

1. 当前 `process_ownership_available()` 无条件返回 false；create/recover/poll/stop 因此被显式阻断。
2. 现有 `FateServerSignals` 只有系统信号收集/工作进程保护，不含进程所有权实现。不能把它的存在误认为已经取得进程句柄。
3. 原管理器创建、轮询、恢复、停止及析构仍有 OS.create_process / OS.is_process_running / OS.kill 调用。仅开放 availability 或补一个 Callable 会留存 PID 复用误杀路径。
4. 现有 GDExtension 入口为 `fate_server_signals_init`，SCENE 级注册，兼容最低 Godot 4.4，Windows/Linux x86_64 的库名已声明。保持这些配置不变。
5. README 声明 godot-cpp 固定提交 `714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa`。本次实际从该提交归档构建；归档的 extension_api.json 标明 Godot 4.4.0 stable official。既有 build_profile 的 RefCounted/OS 足够，不需要额外引擎类。
6. 原 SConstruct 的 MinGW `-static-*` 无条件用于所有 Windows 编译器。补丁限定仅 use_mingw 时添加，并为所有 Windows 工具链链接 bcrypt，实际 MSVC 构建通过。
7. 两个既有测试仍引用可注入 Callable，其中一个声称注入 true 可通 ready。这与真正 OS 所有权相冲突，本补丁去除注入正例，改为合成登记/伪造令牌不得授予所有权。

## 真实身份契约

`FateProcessOwner` 为每个房间管理器独立持有的 RefCounted 对象。它的原生私有表按 128 位随机 token 索引 `{PID, OS身份}`。token 使用 Windows BCryptGenRandom / Linux getrandom；不依赖时间、PID、ready 字符串或自报实例 ID。

| 方法 | 成功语义 | 安全失败 |
|---|---|---|
| available() | 系统具备所需原生接口，随机数可用 | false，禁止启动与恢复；它不是某个 PID 的所有权证明 |
| spawn(executable,args) | 直接启动进程并先取得 OS 身份，返回 `{pid,token}` | `{pid:-1,token:""}`；绝不回退为 OS.create_process |
| state(token,pid) | 1=所持同一 OS 实例运行；0=所持同一 OS 实例已退出 | -1=未知/错配/错误，不得当作退出 |
| verify(token,pid) | 严格 bool，仅 state==1 时 true | false |
| terminate(token,pid) | 针对所持 OS 身份，等待确认退出；已退出幂等成功 | false，保留登记/原目录；绝不按 PID 查找新进程 |
| release(token,pid) | 只对确认退出的对应实例释放句柄与表项 | 存活/未知/错配全部 false |

### Windows

- CreateProcessW 原子提供进程 PID 和进程 HANDLE；原生表持有 hProcess，立即关闭 hThread。
- lpApplicationName 显式传入，不走 shell，不继承句柄。UTF-8 转 UTF-16 使用严格转换；CRT 参数引用保留空参数、空格、引号、尾部反斜杠；含 NUL 参数直接拒绝。
- 存活/退出使用 WaitForSingleObject；终止使用原句柄上的 TerminateProcess，最多等 5 秒；释放使用 CloseHandle。
- **没有 OpenProcess(PID) 认领路径。** PID 复用不改变旧 HANDLE 指向的内核进程对象。

### Linux

- 使用 **clone3(CLONE_PIDFD)**，内核原子产生 PID 与 pidfd。不能使用 fork 后 pidfd_open 子 PID 的非原子方案：外部强杀 + 引擎 reaper + PID 复用仍可能落在取得 pidfd 之前。
- available 用零长度 clone3 请求探测接口（不创建进程），用自身 pidfd 探测 pidfd_send_signal，并用 P_PIDFD waitid 对非子进程应返回 ECHILD 的语义确认回收接口可用。这只是能力探测，不作为工作进程验证。
- 子进程在执行之前等待父进程门闩；父进程已持有原子 pidfd 后才放行。使用 CLOEXEC socketpair 和 MSG_NOSIGNAL，外部提前杀死子进程不会让主管因 SIGPIPE 退出。
- fork-like clone 的子分支不分配内存、不获取 C++/Godot 锁、不调用引擎；参数在主管中准备，子分支仅 close/read/execve/write/_exit。exec_error 管道 CLOEXEC EOF 区分 exec 成功，exec 握手等待预算为 5 秒。
- state 对 pidfd poll；检测退出后用 waitid(P_PIDFD) 回收直接子进程，但保留 pidfd，旧实例仍能稳定返回 EXITED。允许引擎 reaper 提前回收导致的 ECHILD。
- 终止只用 pidfd_send_signal(SIGKILL)，以单调时钟约束 5 秒等待；不使用 kill(PID)，不靠 /proc/PID/starttime 前后采样，不用 waitpid(PID) 回收生产进程。
- 要求 Linux >=5.4、相应 Linux 头文件、允许 clone3/pidfd/getrandom 的系统策略。旧内核或 seccomp 不允许时失败关闭，**不会为了可用性牺牲身份验证**。某些容器默认禁 clone3，必须显式调整部署策略，不提供弱安全 fallback。

## 代码职责与 GDScript 接线

- `process_owner_core.hpp/.cpp`：单一职责为本机直接子进程的 OS 身份/资源生命周期，无 Godot、房间规则、恢复文件或网络逻辑。
- `process_owner_binding.cpp`：只做 Godot Variant/String 与核心接口转换，注册 available/spawn/state/verify/terminate/release。
- `server_signals.cpp`：只增加同一 SCENE 初始化中的新类注册；信号处理器、旧 API 与信号职责不变。
- `SConstruct`：保持 src/*.cpp 发现方式及现有库名，只增加 bcrypt 与编译器区分。
- `server_room_manager.gd`：懒创建原生所有者；移除可注入 verifier。两处创建都使用 native spawn，私有 room.process_token 关联 PID、业务 instance_id、room 与 authority_host_mode。
- 保留现有业务 instance_id（配置/ready/路由版本）与原生 token（OS 能力）的不同职责。token 不写配置/ready/心跳、不发网络；ready 的任何字符串都不能创建原生表项。
- poll、心跳、ready 与 is_ready 均依赖原生状态/验证；UNKNOWN 撤销 ready。失败进程仍按保留句柄尝试停止，不丢弃登记，也不继续为错误实例发心跳。
- recover 对正 PID 要求旧原生实例确实 EXITED；新 native spawn 成功后再释放旧实例并换 PID/token/业务 instance_id。UNKNOWN 和仍运行都拒绝恢复。
- stop_room 使用定向 terminate + release，两者成功才删登记。close/PREDELETE 使用同一接口；原生析构最后只针对持有的身份清理。
- discover_rooms 仍只恢复房间业务登记，PID=-1；**不认领旧 PID，不把持久化字符串转换成所有权能力。** 从磁盘登记启动的是另一个新实例，不是对旧进程的所有权恢复。旧主管崩溃留下的未知孤儿不能被本补丁验证/杀死；现有工作进程主管超时自退机制和端口冲突只是部署/资源约束，不是身份验证。该并发/孤儿场景仍需正式 Godot 验收，不声明已解决。

## 构建命令

补丁应用前可直接在本 scratch 文件夹重做本次完整验证（固定本机路径）：

```sh
python verify_all.py
```

需要重新下载依赖时：`python fetch_deps.py`。本次 tools-env 内为 SCons 4.11.1、gdtoolkit 4.5.0；`build_windows.cmd` 先初始化本机 VS2022，再构建 overlay。`verify_windows.cmd` 编译并运行独立 C++ 子进程测试，不启动 Godot。

在批准将补丁应用到生产后的扩展目录，通用命令如下，CPP_DIR 为上述固定提交的源码路径：

```sh
# Linux
scons platform=linux target=template_release arch=x86_64 godot_cpp_dir="$CPP_DIR" build_profile=build_profile.json -j2
# Windows MinGW（保持原项目发行方式；本轮没有验证该工具链）
scons platform=windows use_mingw=yes target=template_release arch=x86_64 godot_cpp_dir="$CPP_DIR" build_profile=build_profile.json -j2
# Windows MSVC（在 Developer Command Prompt 中；本轮实际使用）
scons platform=windows use_mingw=no target=template_release arch=x86_64 godot_cpp_dir="%CPP_DIR%" build_profile=build_profile.json -j2
```

直接 Linux 核心测试：

```sh
g++ -std=c++17 -Wall -Wextra -Werror -pthread -Ioverlay/addons/fate_server_signals/src native_test.cpp overlay/addons/fate_server_signals/src/process_owner_core.cpp -o native_test_linux
./native_test_linux
./native_test_linux --blocked
```

MSVC 构建产物需要匹配 VC++ Runtime；MinGW 构建保留原静态 C++ Runtime 策略。Linux .so 使用目标系统的 glibc/libstdc++，本机 WSL 的构建不能冒充所有 Linux 发行版的 ABI 验收。

源码补丁不携带编译后的二进制 diff。scratch 中有实际构建产物：
- `overlay/addons/fate_server_signals/bin/libfate_server_signals.windows.x86_64.dll`
- `overlay/addons/fate_server_signals/bin/libfate_server_signals.linux.x86_64.so`

本轮仅执行 `git apply --check ownership-v6.patch`，未执行 apply。生产源码尚未改变，因此生产旧 DLL/SO 仍然不具备新类；正式应用补丁后必须重编译并替换对应库，不能只改 GDScript。

## 尚未验收、不能夸大的边界

1. 未启动 Godot，无法宣称 Godot 类加载、真实 worker ready、路由、配置失败回滚或保存后关闭已运行通过。gdtoolkit 语法解析不是 Godot 类型/运行验证。
2. 未强行制造真实 PID wrap/reuse。原生测试验证真实独立进程、令牌/PID 错配和退出后仍持有身份；不误杀复用 PID 的实现依据是全生命周期只操作稳定 HANDLE/pidfd，不存在重新按 PID 查找/发送信号的路径。
3. 未验收 Windows Unicode 路径、控制台包装器、MinGW 发行 DLL、正式打包、跨机 LAN/P2P 或网络中断。启动目标必须是实际 Godot 可执行文件，而非会再派生工作进程的外部包装器；本契约只拥有直接创建的进程，不冒充整个后代进程树管理。
4. 主管硬崩溃/断电不会执行 RAII；Windows 没有 Job Object kill-on-close，Linux 没有在子分支植入跨主管生命周期的持久凭证。本补丁不保证主管被强杀后子进程立即退出，不认领未知孤儿。
5. 终止等待上限是每个进程 5 秒，Linux exec 握手另有 5 秒；原生调用目前同步。可能影响故障关闭期间的帧耗时。无法确认退出时严格报告失败，不声称 OS 一定杀得掉不可中断/权限改变的进程。
6. 此补丁实现的是系统身份契约与进程重启接线，不是对局回滚、真实成员身份恢复或存档恢复成功的证明。

## 主代理建议的后续验收（需另获允许运行 Godot）

在合入并重编译后串行验收：无扩展/旧扩展失败关闭；真实创建与 ready；伪造 token/PID/ready 拒绝；子进程自然退出及崩溃后的恢复；旧绑定停止/恢复不影响新实例；close/PREDELETE 清理；保存后正常关闭；主管强杀后孤儿超时与磁盘登记恢复；正式 Windows/Linux 包加载扩展。保留独立日志，不用旧 ready/日志替代新实例成功。
