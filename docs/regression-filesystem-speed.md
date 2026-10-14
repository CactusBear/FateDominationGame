# 文件安全监控：单步去重与功能验收

## 交付边界

用户中途取消性能测量；未运行旧新三轮计时、依赖规模模拟或分位统计，不提供倍率、全量性能或全量回归结论。

仅修改 `tools/run_isolated_godot_test.py:no_links`：每个路径／祖先直接一次 `lstat`，跳过 `FileNotFoundError` 后继续检查祖先；symlink mode 或 `st_file_attributes & 0x400` 仍拒绝。权限／未知错误不吞掉，不沿链接检查目标，不跨轮缓存。

`tree_bytes` 的逐节点／祖先检查、`os.walk(followlinks=False)`、最终 `stat`、原子消失跳过政策原样保留。扫描间隔、字节／时间／空间预算、所有权清理门及 Windows Job 均未修改。源码 AST 去掉 `no_links` 后与保存的原版完全一致。statwalk 仍只查元数据，不打开内容 HANDLE；未引入 `read_bytes`。

修改前检查进程，得到 `NO_ACTIVE_GENERIC_OR_FULL_OWNER`；没有覆盖活跃旧执行器的收尾函数。既有非本次进程未操作。

## 测试

证据根：`E:/scratch/filesystem-speed-68ca61b923734a5dabac5fbcf3fec015/`

```bash
ISOLATED_TEST_ROOT='E:/scratch/filesystem-speed-68ca61b923734a5dabac5fbcf3fec015/fixtures' python -B -m unittest tools.tests.test_isolated_godot_test -v
python -B E:/scratch/filesystem-speed-68ca61b923734a5dabac5fbcf3fec015/smoke.py
```

- 确定性去重断言先在旧版 RED，再在修改后 GREEN；不以时间阈值验收。初版只拦截 `os.stat/lstat` 的计数漏掉 Python 3.14 Windows 原生 `exists/islink`，已修正工具并保存有效 RED。计数是 API 请求而非内核 syscall 计数，不作性能结论。
- `units.log`：25 项，23 通过、2 skip、0 失败，exit 0。
- 新增覆盖：普通／多层缺失路径、旧新字节数一致、不持内容句柄、实际线程 rename 与消失、最终 stat 时消失、permission／未知元数据错误保守拒绝、invalid path、非 symlink reparse 属性、真实 ancestor junction／missing leaf、树扫描与删除拒绝，及权限许可时的真实／悬空 symlink。
- 真实 junction 成功创建并验证拒绝；symlink 因 WinError 1314（缺创建特权）skip。没有把 skip 记为通过。
- 原有预算、派生进程、Job 生命周期、未知所有权、兄弟路径保留及严格 RESULT 测试通过。
- 原有四模式 Godot 可选测试因未设 `ISOLATED_GODOT` skip；按本次只允许一个短场景的范围，另行仅执行下面一次真实 freeze smoke，不补跑四模式或大场景。

## 单次真实 Godot smoke

通过当前 generic runner 启动独占物理 E 引擎副本、真实主／worker probe、freeze import 与一个短 scene。真实 `user://` 写入并读回成功；`RESULT filesystem_safety_smoke checks=2 failures=[]`，exit 0。probe/import/scene 均记录 Job ActiveProcesses=0、exit 0、log handles released；两个 probe 实际物理路径均在该次 generated 独占 E 子树。generated 已由原删除门清理，独占引擎副本也已删除。

manifest：`smoke-runs/isolated-f52d116000e845f8b19d481a6f8c90b3/manifest.json`

|指纹|SHA-256|
|---|---|
|原 generic 源码|`87df79c87c2ad0f60e184c4c7dbbf057102377e716fb613ea7ac11dd0e54e5b3`|
|修改后 generic 源码|`a048b2291ab5d0548501489cb3dd7b701b2e0f89c75480804b185376479801bb`|
|smoke manifest|`2c436ee0e7cdb75cdd7bafd270b9492fd9edcc1a6ef7219b17bea80b30cf952d`|
|Godot 原件与 E 副本|`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`|

`verification.json` 保存摘要；原版 runner、RED、单元日志及原始 smoke logs/manifest 保留。`tools/diagnostics/filesystem_monitor_microbench.py` 仅保留旧函数 oracle 与去重断言计数器，计时／规模代码已经移除。

## 未声明的结论

没有测量提速、没有全量或长恢复、没有读取真实 secret 内容。单次 probe／短场景不认证完整生产恢复／多人联机；真实 symlink 创建路径仍受本机权限限制。路径检查没有新增原子 OS 句柄绑定能力，也不声称消除了既有 TOCTOU 窗口。
