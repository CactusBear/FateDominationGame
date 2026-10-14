# Round30 G05 候选发行 EXE 运行报告

## 结论

- **客户端候选：静态审计通过，EXE 自身 headless 启动通过；非 final。**
- **游戏服务端候选：静态审计通过，EXE 自身 `SERVER_GATEWAY_READY` 通过，并由 `CTRL_BREAK` 进入正式保存关停，`SERVER_STOP_COMPLETE`、exit 0；非 final。**
- **纯信令候选：BLOCKED。** 首次独立 export 仍保留原始 exit 139 日志；按要求暂停该分支。不得把 gl_compatibility 的 import/export exit 0 或最后日志解释成信令运行通过：gl export 的完整 stderr 含 GDScript Parse Error，故仍 blocked。
- **客户端 UI 未启动窗口**，没有创建第二个窗口；本轮只做正式候选 EXE 的 headless 自身入口冒烟。需要窗口验收时保留唯一窗口执行者边界。

## 冻结与源指纹

冻结目标均为 E 盘新独占 scratch，开发 `project.godot`、`export_presets.cfg` 未修改。候选分类保持 `CANDIDATE_SOURCE_NOT_LOCKED`；未复用旧包。

| 项 | SHA-256 |
|---|---|
| 源 `project.godot` | `986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a` |
| 源 `export_presets.cfg` | `f8f6afbbeb520f780deab5d7f7d5a59e9f5b2f33e02db4cb64c6823a428da091` |
| `tools/release/freeze_prepare.py` | `4ed223a966fbd74acfb53837185b91273510529457fdb39cd597c7d6588662e3` |
| client freeze manifest | `1cd5ac71e6ab177ad7afe31b783463f080b614e61972588a649d1ed3dc815049` |
| server freeze manifest | `3e977cf52adbb62174da94398c7ba2bcbcca87a88a7d2d3a3bb679caa12c6c98` |
| signaling freeze manifest | `5fa22684b51a26d2a83d61288374f92aa401aa70069cf29df279eb7d2db65150` |

client/server 冻结副本均读回 `worker_pool/max_threads=20`；PCK 审计读取的是各自新导出，不是旧包。

## client/server 实证

静态审计归档：
`E:/Caches/Hermes/cache/scratch/round30-g05-release-runtime/{client,server}-audit.json`

两者均为 `STATIC_PASS_RUNTIME_PENDING`，`blockers=[]`，data 205 个文件缺失/额外/变更均为空，PCK 各 1085 条目；外置 native DLL SHA 与包内目标一致：

- fate server signals：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`
- WebRTC：`3a8053d325a874493f596630b0f165f3a83e265c61d9fd87d82da6cb4c2a81fd`

候选产物指纹：

- client EXE `8b30b9e04970272ed3d70a4c530838570922550208ae1e1817ccb30cc0458730`
- client PCK `f0113947fc2eb2a2104c1f6ce9747dbe9910bd4036648db8b7577e08a653d85b`
- server EXE `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`
- server PCK `6f40f2785e4f1c4b9cc5d895b4ce93e6b7feee36053dd4b08f4b3e1d1a2a75d6`

client 自身命令以 PID `26048` 运行，exit 0；Godot 版本为 `4.7.2.stable.official.ed1daf0bf`，无 stderr。服务端运行证据：`server-runtime-v2.json`，READY PID `35160`，端口 `24871`，`roles=[game]`，合法关停为 `ctrl_break_shutdown`，exit 0，含 `SERVER_STOP_COMPLETE`。

配置缺失负向也由候选 EXE 自身执行：服务端 missing-config exit 1，输出配置不可读错误；未改用源码 Godot 替代。

## signal 分支（暂停）

原首次 export 证据未覆盖：

- 原日志：`.../signaling-export.log`，原进程 PID `10064`，bash 观察 exit `139`；日志保留，未覆盖。
- 原失败阶段在 `update_scripts_classes`、`MatchPacketFragments` 附近；仅凭最后位置不判定根因。
- 使用 console.exe + Python `subprocess` 独占短复现，保存完整 stdout/stderr、PID、return code：
  - import：PID `27216`，`--rendering-method gl_compatibility`，return 0，stderr 0；`signaling-crash-repro/{result.json,stdout.log,stderr.log}`。
  - export：PID `31032`，`--rendering-method gl_compatibility`，return 0，但 stderr 68201 bytes，含 `SCRIPT ERROR: Parse Error`（例如 `json_maker/json_maker_ui.gd` 类型推断及 `JsonMaker/LoadHelper` 未声明）；`signaling-export-gl/{result.json,stdout.log,stderr.log}`。

这两个结果都不能关闭原始 139 的根因，也不能生成可验收信令包；未删除类、未放宽审计、未复用旧包。原始 139 与 gl 复现的完整日志、stderr、命令、cwd、PID、字节数均保留。

## 修改文件

- `tools/release/freeze_prepare.py`：纯信令冻结副本去除 autoload、固定独立 bootstrap、补齐信令入口资源；保留 20 线程配置，不触碰开发工程。
- `tools/release/runtime_audit.py`：候选 EXE 自身 READY、缺配置负向、Windows CTRL_BREAK 正式关停审计。
- `tools/tests/test_round30_release.py`：G05 证据回归测试。
- 本报告：`docs/round30-release-runtime.md`。

旧 client/server package 与 freeze 在证据归档后回收；信令 139 原失败日志及 gl import/export 完整证据保留。最终仍是候选/blocked，不宣称完整发行通过。
