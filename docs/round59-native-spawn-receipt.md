# Round59：invalid-iterator 修复后的隔离 native receipt

## 结论

- 当前 parent 的 Windows-only `slot = inserted.first` 修复已由新的隔离 DLL 验证为 **RED → fresh GREEN**。
- 最终 runtime、signals、正式 full cold freeze 三个 scope 均 `ok=true`；不是正式包发布，也不是 manager/status/autocleanup registry GREEN。
- production core、binding、SDK、已有静态库、正式 `bin/`、descriptor、Godot、SConstruct 和旧 gateway `28100` 未由本轮修改或关闭。
- 旧失败回执保留原字节，未用新 PID/token 改写旧结果。

## 固定构建输入

- 构建命令：
  `python -B tools/diagnostics/round55_native_build.py --output E:/FateDiagnostics/round59-native-build-20261010-1 --stage build`
- 构建退出码：`0`；manifest `laststage=COMPLETE`。
- 新 DLL：`E:/FateDiagnostics/round59-native-build-20261010-1/libfate_server_signals.windows.template_release.x86_64.dll`
- 新 DLL：452608 bytes，SHA256 `9c14b69f1ccd859b91658e3333ccfd55c51d5d6055ff3861a702bacc75480895`
- build manifest 的当前 native `.cpp/.hpp` 摘要逐项匹配；正式 DLL 摘要未变；只读 source→DLL 关联行保存在每个 scope 的 `metadata.json`：
  `fa81534359e7634eafeed02dd3d9a47c48d720811348db27417d4aa120f5dd4b->9c14b69f1ccd859b91658e3333ccfd55c51d5d6055ff3861a702bacc75480895`
- 正式 release DLL 仍为 `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。

## 最终实际运行

| scope | 命令根 | engine | functional | Job readback |
|---|---|---|---|---|
| runtime | `E:/FateDiagnostics/round59-native-runtime-20261010-3` | `0x00000000` | 217 checks，旧 158 项标签全部保留，failures=[] | active=0, terminated=0, handles_released=true |
| signals | `E:/FateDiagnostics/round59-native-signals-20261010-1` | `0x00000000` | 37 checks，旧 31 项保留，failures=[] | active=0, terminated=0, handles_released=true |
| cold | `E:/FateDiagnostics/round59-native-cold-20261010-1` | `0x00000000` | 正式 full freeze cold scope | active=0, terminated=0, handles_released=true |

三个 scope 都使用全新物理 E 根和重定向 user/cache；没有 warm/retry/recovery mode。cold 仅声明项目/cache fresh，不冒充 OS 文件缓存 cold。

## ProcessOwner receipt

- 连续 4 次合法 spawn 均取得非空 32 字符 token、合法 PID；每个 receipt 的 token/root_pid/state 与实际登记绑定，active/total=1，live release 均拒绝，结束后自然退出并 release。
- 不存在 executable 和空 executable 均返回 `pid=-1`、空 token；失败不得产生可用 token。
- normal、真实异常 `0xE0570001` crash、root-only terminate 都使用 root-child-grandchild。root 退出且 descendants 仍活时 `release=false`；只有整树 active=0 后才 `release=true`。
- stale token、错误 PID、UNKNOWN 均拒绝；没有 root-only active 误判。
- 析构专例真实确认：owner 析构后 root/child/grandchild 仍为 WAIT_TIMEOUT，`saved=false`，没有 kill still-live unsaved tree。engine HANDLE count 实测为 baseline 290、析构后 286；记录为 cache/owner fluctuation observation，不猜测 leak。
- 外层 Job 每个 scope 最终 `active=0`、`terminated=0`、句柄关闭完成。

## signals receipt

- sender 日志保存 keeper、engine、sender PID 及三者完整创建 FILETIME。
- collect/protect 各真实广播一次；每次广播前两次枚举都恰为 keeper、engine、sender，未知 console member 不发送。
- sender 等待 engine 侧真实 handler event ack 后才 `FreeConsole`；无 `Sleep`、无忽略退出码。最终两个 sender exit=0。
- 原历史 self-control 退出码 `0xC000013A` 保留在 round57 失败证据中；本轮没有改写该回执，也没有把旧异常改成新成功。

## atomic / registration 保留项

- `remove_verified` 15 次实际调用，15 次独立 controller readback；原四类 ClassDB 均实际注册/实例化，原 13 methods 加 `tree_observe`、`remove_verified` 两个新增方法均做真实 `has_method` 查询并调用。
- symlink 项实际返回 `WinError1314: no symlink privilege`，按真实权限列为 SKIP，未冒充 PASS；其他链接/目录/身份/size/hash/lock/outside/`..` 分支保留拒绝证据。
- `failure_must_be_false=true`；失败不会被补成成功。`no_automatic_cleanup_green=true`、`not_production_package=true`。

## 旧失败与未知边界

- 原 runtime 失败回执：`E:/FateDiagnostics/round57-native-runtime-20261010-2/result.json`，SHA256 `0abeac44d23d6cc97a6f0c50bd19cdc3d7f6dba5a87522d1910df1393c7de8dc`；本轮 readback unchanged。
- 新增的早期诊断脚本解析失败和 NUL bridge 测试假设失败均未归因 native；原始根完整保留。没有新的 first-syscall、native crash receipt 或 stack 证据，因此这些边界保持 **UNKNOWN**，未循环猜测或伪造定位。
- 本轮只交付隔离 native candidate runtime/cold evidence；不 ship formal bin，不创建新 manager/status proof，不改变 source policy。
