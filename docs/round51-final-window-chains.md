# Round51：当前生产三条非 headless GUI 链

## 结论

当前三链**未达到 `currentUIchainGREEN`**，不拼接不同冻结或旧 headless 结果：

- host 终局链：当前冻结 `17 checks / failures=[] / exit 0`，无 `SCRIPT ERROR`、`ERROR:`、超时。
- net v2 输入链：`46 checks / 13 failures / exit 1`，无脚本/引擎错误；失败从第一张牌主动入口未得到 authority pending 开始，后续翻面、提交、战场、令咒和阶段结束检查连锁失败。
- server countdown 链：`71 checks / 3 failures / exit 1`，无脚本/引擎错误；当前运行失败为完成态后台提示、风险确认提示和后续正式按钮可见性。

旧 `72`、旧 `15`、headless 终局和其它冻结均未并入上述结论。

## 唯一当前三链冻结

最终合并运行根：`E:/HermesScratch/round51-final-window-82fc85d0e6fd47e6acbba26e4c3f77c9/`

- `manifest.json`：三套均在同一 `single_freeze=true` 上顺序运行。
- `source-hashes.json` / `freeze-hashes.json`：3466 项，冻结创建时 `source_freeze_mismatch={}`。
- Godot 4.7.2 console SHA256：`c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`。
- 三个 scene 均不带 `--headless`，每套 180 秒自有 PID 树上限；本次均未超时，generated project/user 树已回收，证据目录保留。
- 运行期间另一个写入者改动了 `tests/round51_default_settings_trace_test.gd`；manifest 的 `source_drift` 已如实记录，不能把本次冻结称为当前全树无漂移。

## GUI 证据

### 1. host 自然终局 → accepted → 正式大厅

命令等价于：

```text
Godot --fixed-fps 60 --path <freeze> --scene res://tests/round47_host_lifecycle_board_test.tscn -- window
```

窗口分支实际完成自然终局、正式终局控件输入、accepted、单次大厅替换；结果 17 checks 全绿。原生读图确认终局页和大厅页存在：

- `evidence/host_lifecycle/images/APPDATA/FateDomination/round47-terminal-before.png`
- `evidence/host_lifecycle/images/APPDATA/FateDomination/round47-lobby-after.png`

### 2. net v2 手牌输入与共享渲染

命令等价于：

```text
Godot --fixed-fps 60 --path <freeze> --scene res://tests/net_v2_ui_input_parity_window_test.tscn -- window
```

同一冻结下真实非 headless Vulkan/NVIDIA 窗口完成 46 项检查，但 13 项业务失败。已确认的正向输出包括手牌、身份块、费用 `4`、剩余魔力 `6`、共享威力预览 `6`、日志 modal 阻断和原生截图；失败链从主动按钮点击后的 authority pending 未出现开始。现有 GUI test/fixture 未改，也未补生产 compat 字段。

- `evidence/net_v2_input/images/runtime_reports/net_v2_ui_input_parity.png`

### 3. server validation countdown

命令等价于：

```text
Godot --fixed-fps 60 --path <freeze> --scene res://tests/server_validation_countdown_test.tscn -- --config <owned-user>/FateDomination/countdown.cfg
```

这次同冻结结果为 71 checks、3 failures、exit 1；未拼入另一次冻结中出现的 `72/72`。本次截图保留并原生读回：

- `panel-early`、`panel-later`
- `lobby-background-early`、`lobby-background-later`
- `completed`、`risk-confirmation`、`applied`、`zero-budget`
- `cancelled` 未在该次失败路径产生

证据位于：`evidence/countdown/images/APPDATA/FateDomination/countdown-4916/`。

## 边界与未完成项

- 截图为 viewport 原生 PNG（1920×1080，原生模型读图时缩放显示）；客户区尺寸与 viewport 尺寸的 DPI 分离本轮**未验证**，不作通过声明。
- 未修改生产脚本、既有 GUI test/tscn 或 adapter fixture。新增文件仅：
  - `tests/round51_final_window_chains_runner.py`
  - `docs/round51-final-window-chains.md`
- 下一修复边界：先由 main 根因处理 net v2 adapter/fixture 的 authority pending/输入接线，以及 countdown 完成态提示/按钮可见性；在同一当前源码重新冻结并重跑三链。只有三套各自唯一 RESULT、exit 0、无错误、GUI branch checks 全满足，才能改称 `currentUIchainGREEN`。
