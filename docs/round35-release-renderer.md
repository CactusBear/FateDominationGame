# Round35 显式发行渲染器与首次 import 门禁

## 结论：代码 GREEN，全链真实验收 BLOCK

- `release_prepare.py` 新增显式 `--rendering-method {forward_plus,mobile,gl_compatibility}`，API 对应关键字参数 `rendering_method`。import/export 复用同一 Godot 命令前缀；不传保持原命令，不按 client/server/signaling 猜测，不改开发 `project.godot`。
- 非零步骤继续 fail closed，诊断增加原始退出码及 32 位十六进制值。`3221225477` 与 `-1073741819` 均显示 `0xC0000005`；没有自动重试、吞错或放宽 `check_export_log`。
- 专项与相关发行单测真实通过：**14 项，exit 0**。
- **三次新冻结候选通过生产入口执行，首次 import 均为 `3221225477 (0xC0000005)`，release CLI 均 exit 1；export、外置依赖复制、PCK 审计、EXE READY / CTRL_BREAK 因此均未执行。不能将本轮标记全链通过。**
- 仅诊断同一失败副本重入 gl import 时 exit 0、stdout 1087 bytes、stderr 0。此结果不属于发行验收，不能替代首次失败。Round32 成功记录不证明 gl 可保证干净项目首次导入成功。

## 改动范围与解耦

修改仅限 `tools/release/release_prepare.py`；新增 `tools/tests/test_round35_release_renderer.py` 及本报告。渲染器是调用方显式本机命令参数，不是角色规则、工程设置或包契约字段。候选仍使用原 freeze、release contract、package audit；没有修改 freeze/runtime/package 审计、生产 GDScript、开发预设或渲染设置，也没有新增另一种 runtime 审计。

共享 Godot 前缀为：

```text
<console Godot> --headless [--rendering-method <显式值>]
```

import 后接 `--editor --path <freeze> --import`；export 后接 `--path <freeze> --export-release <preset> <exe>`。参数直接作为 argv 元素传递，未知值在 API/argparse 拒绝。

## RED / GREEN 证据

独占物理根：`E:/Caches/Hermes/cache/scratch/round35-release-renderer-v4a/`。TMPDIR/TEMP/TMP 与 LOCALAPPDATA 在测试子进程中显式规范化到本轮 E 根，不改生产路径安全函数。

1. `unit-red.log`：新增参数测试先跑，exit 1；真实断言失败为 `plan() got an unexpected keyword argument 'rendering_method'`。
2. 首次 GREEN 夹具缺少游戏角色 data 目录，补齐测试契约；第一次综合回归还发现继承 Round32 LOCALAPPDATA 导致 scratch 根不同。原失败保留于 `unit-green.log`、`unit-green-all.log`，只修测试声明与隔离运行环境。
3. `native-diagnostic-red.log`：增加原始非零退出码/十六进制诊断断言后，exit 1；原入口仅报告日志路径，6 个非零子例真实失败。
4. 最终 `final-with-cli-unit-green.log`：下述命令 exit 0，14 项通过。

```text
python -B -m unittest tools.tests.test_round35_release_renderer tools.tests.test_release_prepare tools.tests.test_release_freeze tools.tests.test_release_roles -v
```

专项覆盖三角色显式传参和原默认完整命令、三种允许渲染器、真实 CLI dry-run 有/无参数接线、非法 API/CLI 值、开发项目未改，以及 import/export 各阶段的 unsigned/signed access violation、139、零码 Parse Error / ERROR 日志立即拒绝且不产成功清单。仅外部 Godot 返回值在拒绝路径单测中模拟；下面的 native 失败来自真实 Godot，不是模拟输出。

## 真实生产入口与 native 阻断

Godot 实际版本：`4.7.2.stable.official.ed1daf0bf`。每轮通过未修改的 `freeze_prepare.py --prepare` 新建独占信令候选：14 个源文件，加生成的 release contract；显式角色 signaling、`FateServer Windows`、`FateSignaling.exe`，唯一运行依赖为 fate server signals Windows release DLL。模板从已安装源只读复制并 SHA 校验到本轮 E APPDATA。

实际生产调用如下，其中 `B` 分别为三个新根，完整 argv/PID/退出码保留在各根 `release-prepare-result.json`：

```text
python -B tools/release/release_prepare.py --project <B>/project --output <B>/export --godot D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe --preset "FateServer Windows" --platform windows --role signaling --manifest <B>/release.json --freeze-manifest <B>/freeze.json --allowed-root <B> --execute --credential-free-project --rendering-method gl_compatibility
```

| 新独占根 | 验证差异 | 首次 import | release CLI |
|---|---|---|---|
| `round35-release-renderer-v4a` | 独占干净 APPDATA，普通父进程 | 0xC0000005 | 1 |
| `round35-release-renderer-v4a2` | 新候选，发行 Python 持有独立真实 Windows 控制台 | 0xC0000005 | 1 |
| `round35-release-renderer-v4a3` | 新候选，仅复制前轮本机编辑器设置/文档缓存 | 0xC0000005 | 1 |

三份首次日志相同 SHA：`4e77f72115586f97577867985bf131e2e11cf52157f8c51e2f810a068ef2205d`。只输出正常 filesystem、脚本全局类、编辑器布局初始化，stderr 空，无 SCRIPT ERROR / ERROR；不能称为 ParseError。

`v4a3/diagnostic-reentry-import.json` 记录完全相同 gl 命令在同一已导入副本重入 exit 0（1087/0 bytes）。“独立控制台可解决”及“仅暖全局编辑器缓存可解决”均未得到支持；项目首次导入/退出阶段的 native 问题尚未定位。没有擅改 Godot、native DLL、冻结校验或线程设置。重入生成了额外 `.godot` 文件，严格 verify 不允许直接拿暖副本再充作原冻结候选。

## 版本漂移、旧证据和清理

- 各候选 `source-version-drift.json` 的 `changed_since_round32={}`；14 个信令闭包源文件 SHA 与 Round32 相同。收尾再次与当前源树逐项比对，仍全部相同。这不表示整个并行工作树已锁定或没有其他文件变化。
- 候选分类保留 `CANDIDATE_SOURCE_NOT_LOCKED`，**不是 final**。源码版本一致不消除冷/暖导入状态差异。
- 只读 freeze/package/runtime/path/contract 工具本轮前后 SHA 相同；旧 Round30 `signaling-export.log`、`signaling-export-gl/stderr.log`、`result.json` 前后 SHA 相同，见各根 `preserved-evidence.json`。旧 139 与 ParseError 证据未覆盖、未删除；旧 result 记录 stderr 68201 bytes，本轮实存日志为 69035 bytes，保留原两者，不强行修正历史。
- 本轮自有进程使用创建时间与持有句柄登记；只按登记句柄清理本轮残留控制台。`owned-processes.json` 保留完整登记和处置记录。收尾进程查询未发现 Godot 4.7.2 或 FateSignaling 残留。
- 三轮冻结 project、导出目录、模板 APPDATA、TMP 与测试临时副本均已回收；首次失败日志先归档为各根 `failed-first-import.log`，小型证据 JSON 和单测日志保留。清理明细为 `v4a/cleanup-summary.json`。

**待完成：定位干净候选首次 native import 崩溃后，重新通过同一 release_prepare 入口执行 import/export/PCK 审计，再复用既有 runtime_audit 验证 READY 与合法 CTRL_BREAK 退出 0。当前没有本轮新包或本轮运行时通过记录，不能拼接 Round32 成功记录关闭此项。**
