# Round32 纯信令冻结与导出

## 结论

- 纯信令候选已按 **V4A / E 盘独占**路径验证：`E:/Caches/Hermes/cache/scratch/round32-signal-freeze-v4a2/`。
- 修复只改 `tools/release/freeze_prepare.py`：闭包根使用信令变换后的 `project.godot`，GDScript 只沿 `preload/load` 依赖走；不会把 `PROCESS_ROUTES` 中未执行的 server/UI 路由字符串当成资源依赖。
- 信令输入清单为 bootstrap、process-signals、p2p signal server、p2p invite、WebRTC link、server bootstrap 场景、fate signals GDExtension 及其 Windows release DLL；不复制 `json_maker`、游戏规则、data、server gateway/worker、`scripts/net/ui` 或游戏场景。
- 保留 `worker_pool/max_threads=20`；冻结项目无 autoload，主场景为 `server_bootstrap.tscn`，显式 `signaling_only=true`。
- 本候选仍是 `CANDIDATE_SOURCE_NOT_LOCKED`，不是 final。

## Python RED/GREEN

- RED（修复前同一测试）：`python -B -m unittest tests.test_round32_signal_release -v`；旧闭包从源 `project.godot` 追到不存在的开发 UI `opening_background.tscn` 并失败，证明它没有以独立 bootstrap 为根。
- GREEN（修复后）：同一命令 `exit 0`，`1` 项通过。实际清单为 `14` 个冻结源文件，另加显式生成的 `release_contract.json`；无 `json_maker`、UI、游戏场景。
- 相关冻结安全测试通过：`test_release_freeze` 的 `5` 项、`test_release_roles` 的 `3` 项、`test_release_prepare` 的 `3` 项。未修改 `package_audit.py`。
- 全部旧发行单测中仍有 `test_package_audit` 的 `2` 个既有夹具失败；与本次信令闭包改动无关，未用放宽规则掩盖。

## 真实 console import/export

隔离工程使用 Godot `4.7.2.stable.official.ed1daf0bf`，命令显式加入 `--rendering-method gl_compatibility`；stdout/stderr 分开保留，未全局忽略 stderr：

- import：`returncode=0`，stdout `1087` bytes，stderr `0` bytes；无 `SCRIPT ERROR`、`Parse Error`、`ERROR:`。
- export `FateServer Windows` → `FateSignaling.exe`：`returncode=0`，stdout `3088` bytes，stderr `0` bytes；无 `SCRIPT ERROR`、`Parse Error`、`ERROR:`。
- 静态包审计：`STATIC_PASS_RUNTIME_PENDING`，`blockers=[]`，PCK `20` 条目；无 `res://data/`，无 match/system/game_scene/operations/json_maker 规则路径。运行 DLL 映射与哈希匹配。

证据：

- `E:/Caches/Hermes/cache/scratch/round32-signal-freeze-v4a2/manual-export.stdout.log`
- `E:/Caches/Hermes/cache/scratch/round32-signal-freeze-v4a2/manual-export.stderr.log`
- `E:/Caches/Hermes/cache/scratch/round32-signal-freeze-v4a2/manual-audit.json`
- `E:/Caches/Hermes/cache/scratch/round32-signal-freeze-v4a2/runtime.json`

## 实际 EXE 生命周期与边界

- `FateSignaling.exe` 自身输出 `SERVER_SIGNALING_READY`，PID `4120`，端口 `24873`，`roles=[relay]`。
- 真实停止方式为 `ctrl_break`，EXE `exit_code=0`；没有创建客户端、房间、offer/answer、存档或游戏数据流量。
- READY 日志明确写出“只帮助玩家建立直连，不运行对局”；包内没有 data 或游戏规则路径。
- 本轮唯一由本轮启动且残留的 Godot console 子进程已回收；回收后无 `Godot_v4.7.2-stable_win64_console.exe`。

## release_prepare 诊断交接

未把非零退出误报成 ParseError。使用当前 `release_prepare.py` 原始 import 命令、未加渲染参数时，**新冻结副本首次**返回 Windows `3221225477`（`0xC0000005`），stdout 只到正常编辑器布局流程，stderr 为空；这是 Godot/native import 崩溃，不是脚本解析错误。之后同项目用 Python 直接捕获确认同一命令可重入返回 `0`，但不改变首次非零事实。

加入 `--rendering-method gl_compatibility` 后，Python 直接捕获的真实 import/export 均 `exit 0` 且 stderr 为空。`release_prepare.py` 当前没有该参数入口；未修改它（不在本轮写入权限内）。主代理若要让发行编排复现本轮真实通过路径，应精确接管“console Godot 命令补充 gl compatibility / 首次 native crash 诊断”，而不是放宽 `check_export_log`。

## 旧证据保留

未覆盖或删除 Round30 证据：

- 原始信令 `139`：`E:/Caches/Hermes/cache/scratch/round30-g05-release-runtime/signaling-export.log`。
- gl export 完整 stderr：`E:/Caches/Hermes/cache/scratch/round30-g05-release-runtime/signaling-export-gl/stderr.log`，`68201` bytes，包含旧 `SCRIPT ERROR: Parse Error`；对应 `result.json` 保留 `returncode=0` 与完整日志路径。

## 修改文件

- `tools/release/freeze_prepare.py`
- `tests/test_round32_signal_release.py`
- `docs/round32-signaling-export.md`

冻结副本、导出包、模板镜像和运行环境属于本轮独占产物，验收证据记录后回收；Round30 旧日志不动。
