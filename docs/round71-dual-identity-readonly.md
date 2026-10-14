# 同机双客户端身份隔离：只读证据复核

**结论：完整身份隔离未通过验收（未生成身份，不能验证身份 SHA 不同/未覆盖）。**
已确认双客户端真实启动、APPDATA 运行数据目录分离、先后启动并发共存、正常退出 Job0、日志无 SCRIPT ERROR。
**old_artifact=true / nonfinal=true；不能写成最终包通过。**

## 证据来源与本次边界
- 复用既有唯一完整 headless 回执：`E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\evidence.json`；SHA `229489919390511071eabd9952f700b9cc20a619a60e4321990781c1f9453431`。
- 本次追加客户端启动次数 0；不是重新跑一轮。原脚本 `newtests/round71_dual_identity_readonly_once.py` 未改。
- 前任还留有 `round71-dual-identity-once-23212` 的非 headless 中断回执，缺最终退出/Job0；排除，不能当成通过。历史整体并非只有一次尝试。
- 本次只新增只读后处理器与其单测；无窗口输入、无开局/建房/联机、无全量/测速。只操作 E 盘文件。
- 未读取打印身份内容、票据、口令；若需 SHA，仅读字节计算摘要，不解析。
- PID 17120/28100 均不在原自有 Job 的观测 PID 集合；本次不终止任何进程。
- 原回执 39 个快照，180s 看门狗未触发，最后耗时 22.228s。

## 验证点
| 点 | 真实证据 | 结论 |
|---|---|---|
| ① launcher 不重置变量 | START-CLIENT.cmd 1–5 行仅 echo/setlocal/cd/rem/EXE %*；没有 APPDATA 或 LOCALAPPDATA 赋值。APPDATA 下两侧实际产生独立运行数据。 | 静态两变量保留；APPDATA 动态已证实。LOCALAPPDATA 为空，无子进程环境直接回执，不冒充动态已证实。 |
| ② 不同身份目录/文件 | 全部快照 host=0、guest=0；最终两侧 net_identity 都不存在。 | 未验证，不通过；无身份文件名/SHA可对比。目录路径字符串不同不等于身份生成。 |
| ③ 先后与并发、不覆盖 | host 先启动，guest 后启动；自有 Job 在 2.154–20.187s 的观测快照内 active=6；对应两个真实 EXE PID。 | 共存通过；身份覆盖检查未验证（不存在身份），不得空集判成功。未做“host完全退出后再开guest”的另一轮。 |
| ④ 退出、Job0、日志 | total=6, active=0, terminated=0；6 个已观察进程退出码均0；两角色两份日志的 SCRIPT ERROR/Parse Error/ERROR: 均0。 | 原 headless 启动/退出专项通过；当前候选 EXE 残留数量=0。 |

## 原始真实命令与 PID/退出码
原调用给每个角色设置如下进程级环境；临时目录也在 E 盘。`--quit-after 180` 是迭代数，不是 180s，另有独立墙钟看门狗。额外 `--max-fps 10` 来自原真实命令。

### host
```bat
set "APPDATA=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\host\appdata"
set "LOCALAPPDATA=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\host\localappdata"
set "TEMP=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\host\temp"
set "TMP=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\host\temp"
set "TMPDIR=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\host\temp"
"C:\Windows\system32\cmd.exe" /d /s /c ""E:\Caches\Hermes\cache\scratch\round71-human-test-candidate-validation-v3\client\START-CLIENT.cmd" --headless --audio-driver Dummy --rendering-method gl_compatibility --max-fps 10 --quit-after 180 --log-file "E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\host.engine.log""
```
- CMD PID `7584`，退出码 `0`；EXE PID `[33356]`，退出码 0。

### guest
```bat
set "APPDATA=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\guest\appdata"
set "LOCALAPPDATA=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\guest\localappdata"
set "TEMP=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\guest\temp"
set "TMP=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\guest\temp"
set "TMPDIR=E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\guest\temp"
"C:\Windows\system32\cmd.exe" /d /s /c ""E:\Caches\Hermes\cache\scratch\round71-human-test-candidate-validation-v3\client\START-CLIENT.cmd" --headless --audio-driver Dummy --rendering-method gl_compatibility --max-fps 10 --quit-after 180 --log-file "E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\guest.engine.log""
```
- CMD PID `31336`，退出码 `0`；EXE PID `[34180]`，退出码 0。

所有被持有句柄的自有进程（含 CMD/EXE 与未命名辅助进程，不猜辅助角色）：
```json
[
  {
    "pid": 7584,
    "exit_code": 0
  },
  {
    "pid": 31832,
    "exit_code": 0
  },
  {
    "pid": 33356,
    "exit_code": 0
  },
  {
    "pid": 31336,
    "exit_code": 0
  },
  {
    "pid": 25468,
    "exit_code": 0
  },
  {
    "pid": 34180,
    "exit_code": 0
  }
]
```

## 目录/文件比对（本次文件系统读取）
下表 SHA 是复核时的现存运行数据 SHA，不是运行时身份 SHA；原快照仅保存运行文件路径/大小。
| 角色/变量 | 目录存在 | 文件数量 | 相对文件名与 SHA-256 |
|---|---|---|---|
| host/APPDATA: `E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\host\appdata` | True | 1 | `FateDomination\game_data\stored_jsons.dat` (373328 bytes), `e006f79791e85ea79bc5dc844eb1d80d1ad01ee7074ff3980f9277bbb0f37121` |
| host/LOCALAPPDATA: `E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\host\localappdata` | True | 0 | 无文件，SHA=N/A |
| guest/APPDATA: `E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\guest\appdata` | True | 1 | `FateDomination\game_data\stored_jsons.dat` (373328 bytes), `e006f79791e85ea79bc5dc844eb1d80d1ad01ee7074ff3980f9277bbb0f37121` |
| guest/LOCALAPPDATA: `E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\guest\localappdata` | True | 0 | 无文件，SHA=N/A |

- host 身份目录：`E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\host\appdata\FateDomination\net_identity`；存在=False，文件数=0，文件名/SHA=N/A。
- guest 身份目录：`E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\test-users\guest\appdata\FateDomination\net_identity`；存在=False，文件数=0，文件名/SHA=N/A。

两个 stored_jsons.dat 是公共游戏数据缓存；相同 SHA 不意味着同一个身份。空身份集合也不能证明未覆盖。

## 日志关键行（本次重新扫描）
- `E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\host.engine.log`：2 行；SCRIPT ERROR=0，Parse Error=0，ERROR:=0。
  - L1: `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org`
- `E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\host.stdout.log`：2 行；SCRIPT ERROR=0，Parse Error=0，ERROR:=0。
  - L1: `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org`
- `E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\guest.engine.log`：2 行；SCRIPT ERROR=0，Parse Error=0，ERROR:=0。
  - L1: `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org`
- `E:\Caches\Hermes\cache\scratch\round71-dual-identity-once-12796\guest.stdout.log`：2 行；SCRIPT ERROR=0，Parse Error=0，ERROR:=0。
  - L1: `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org`

## 来源核对、说明一致性与最小建议
- launcher L2 `setlocal` 保留调用环境，L3 `cd /d "%~dp0"` 只改工作目录，L5 `"FateDomination.exe" %*` 透传参数。与 quickstart L25–29、L36–40 的隔离命令不冲突；**没有证据要求修 launcher**。
- quickstart L43 明确还需进入联机大厅、填写合法用户名/昵称。不能把只启动主菜单的 headless 过程写成执行了这一条。
- 当前源码 `scripts/net/ui/lobby_screen.gd:24–25` 声明身份文件路径；L42–44 在身份按钮调用 `_prepare_identity()`，L355–360 在合法用户名后调用 `configure_identity()`，L374–376 在创建房间前准备身份。这是源码解释线索，不冒充旧 PCK 行为已按此链验证。
- 最小文档建议（只报告）：在 quickstart L19 后补“设置环境变量只隔离 user:// 落点；仅启动主菜单不会自动生成身份。身份须经大厅合法用户名/昵称及身份准备操作生成。headless 启动不能替代身份生成/覆盖验收。”
- 真正补齐验收须另获批准：同一最终候选在两个隔离目录经正式身份准备入口各生成身份；只记录路径/数量/文件名/SHA；保留先后与共存时的非空 SHA 快照，再核对退出 Job0。不要伪造或复制身份文件，也不要用直接调用密钥生成替代 launcher/UI 链。
- 当前候选 EXE 与旧诊断 EXE 的 SHA 相同；三个原追踪文件的运行前后 SHA 一致且本次复核仍一致。原运行未保存 PCK/DLL SHA，不能扩大成整个包未变或最新源码已打包。

| 文件 | 原前/后/本次 SHA-256 |
|---|---|
| `E:\Caches\Hermes\cache\scratch\round71-human-test-candidate-validation-v3\client\START-CLIENT.cmd` | `379e5ae6f9ea58dc745291edef07de0289ca9316e9da5ce73b6b6f2b1ef798ea` |
| `E:\Caches\Hermes\cache\scratch\round71-human-test-candidate-validation-v3\client\FateDomination.exe` | `8b30b9e04970272ed3d70a4c530838570922550208ae1e1817ccb30cc0458730` |
| `E:\FateCandidates\round71-build-only-4f7fb4194e19acdf-91306a82\artifacts\client\FateDomination.exe` | `8b30b9e04970272ed3d70a4c530838570922550208ae1e1817ccb30cc0458730` |

## 本次只读核对命令（报告文件已存在时工具拒绝覆盖）
```bash
PYTHONDONTWRITEBYTECODE=1 python newtests/tools/test_round71_dual_identity_report.py
PYTHONDONTWRITEBYTECODE=1 python newtests/tools/round71_dual_identity_evidence_report.py
```
JSON 明细：`E:\Projects\Godot\FateDominationGame-master\docs\round71-dual-identity-readonly-evidence.json`。只读后处理工具退出0表示报告生成成功，不表示身份验收通过。
