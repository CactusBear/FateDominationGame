# Round74 F15/F16：关闭／owner-binding 只读交接专项

## 结论

原 round71 collector 合同和 `ledger.preview_proven → Collector.collect → Policy.select → Collector.revalidate` 调用已经覆盖完整 binding、源对象身份、代际与 lease epoch；本轮不重写生产代码，只补可复跑负向合同测试。正式 console 调度仍走普通 preview，不是完整 registrar 的生产接线。

新增：`round74_cleanup_handoff_contract_test.gd/.tscn`、`run_round74_cleanup_handoff.py`（均在 newtests）。没有第二 registry、删除调用或生产启用配置，没有读取活体 worker 发布树、日志、身份或 keys。

## 实测

```text
python -B newtests/run_round74_cleanup_handoff.py --mutation-binding
python -B newtests/run_round74_cleanup_handoff.py
```

- RED：仅冻结 collector 副本绕过 member.binding 精确比较，真实 Godot exit=1；四项 room/PID/instance/mode 错配测试明确失败，无 SCRIPT ERROR。这是敏感性 mutation，不是发现生产缺陷。
- GREEN：原 Godot 4.7.2，exit=0，25/25 CHECK，RESULT passed=true，无 SCRIPT ERROR/ERROR。覆盖完整诊断资格但始终 blocked、四字段错配、身份/状态 UNKNOWN、模拟 native 缺失、未释放 HANDLE、active Job、member/registry/lease 代际漂移、漏枚举、非法字段、RUNNING policy 拒选、更换观察源、旧执行入口阻断。
- 所有 registration/lease/member、consumed 台账证据均为显式 contract-test injection，不是生产登记、保存退出链或跨进程 lease。文件读取和策略/collector/ledger 为真实 GDScript。artifact 和 ledger 均独立重开、SHA 不变；removed_files=0。
- 正式旧 DLL 副本真实加载；自有测试 owner 的无认领 token + 当前测试 PID 查询 `state` 实得 -1/UNKNOWN；旧 DLL 实际没有 `tree_observe`。未 spawn/terminate/release，不声称实际 Job0。
- APPDATA/LOCALAPPDATA/TMP/TEMP/TMPDIR 显式在自有 E 目录，Godot 实际 user_data_dir 也在 E。未跑全量、窗口、测速或 manager/worker 生命周期；未清理任何目录。

GREEN 原件：`E:/scratch/round74-cleanup-handoff-53b6687393e04b04824a1df4dd2c1a7b/`。
RED 原件：`E:/scratch/round74-cleanup-handoff-44f2b0ffae5846cf8da4fd350caf90ea/`。
各含 `freeze.json`、`godot.log`、`verification.json`、`project/result.json`；拒绝文件仍保留。

首轮测试夹具错误：把 GDExtensionManager.LoadStatus 声明为 Error 导致解析错误及自有看门狗退出，已改为 int 并重跑；该轮不计 RED，原件保留在 `E:/scratch/round74-cleanup-handoff-7b130673527f427e9b658affc1a4a370/`。

## 生产 SHA-256（前后相同）

```text
collector 42bb452dd63b90816c70ea2ff3fa299a2d69221222bec564316d8d003f48e692
ledger    62c42e4d427efa5a54d4942c02255f45902610c52227621ee9b2350c8b59b5ac
policy    1267c21231bc52b9592efde775828fcfcec8f599b9ee4f70e8f374803e10dc51
旧DLL     92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd
```

## 真正剩余阻断

仍缺 before-start 到全部句柄释放的生产 canonical 完整登记、独立成员见证、可验证 native release readback、覆盖所有 scope writers 的跨进程文件租约，以及全程 lease/intent/recovery/native deletion 接线。旧 bool release、closed history、单个 owner 或字符串见证不可补造这些证明。默认保留正式存档和未确认关闭证据，生产清理继续保守禁用；本专项不是 F15/F16 整链 PASS。
