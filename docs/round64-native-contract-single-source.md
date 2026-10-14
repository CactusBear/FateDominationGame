# Round64：可信 status 原生能力合同唯一显式来源

## 完成范围

- 新增 `scripts/io/native_method_contract.gd`，只包含原显式四类十三方法声明，无 `class_name`、全局定位器、ClassDB 查询、实例化或原生调用。
- `server_bootstrap.gd` 与 `server_console_channel.gd` 的 `NATIVE_METHOD_CONTRACT` 均引用 `NativeMethodContract.REQUIRED_METHODS`；bootstrap 原校验局部变量改为引用此别名。
- 两份原声明逐项及顺序一致，没有需要保留的语义差异。保留原 `FateServerSignals` 四方法、`FateProcessOwner` 六方法、`FateAtomicFileReplace` 一方法、`FateCollectionIdentity` 两方法。没有自动枚举或把 `tree_observe` / `remove_verified` 等额外 wrapper 接口升级为最低要求。
- `native_capability_view.gd` 字节未变：`observe(method_contract)` 仍只接受显式参数，只使用 ClassDB 的存在性查询；不 instantiate、不执行被观察方法、不加载扩展。
- 本轮生产 diff 仅合同声明与引用；status 原七字段、可信本机拒绝门、manager 已应用策略、console close/write_json/control 协议、shutdown/CLI/信令加载时序均未改。改前快照与逆向局部恢复证明见 `newtests/round64_native_source_proof.json`，其余 channel/bootstrap 字节完全相同；只读 manager/CLI/shutdown/DLL 与基线 SHA 无漂移。

## 真实验收

最终统一冻结：`E:/scratch/isolated-d3fdd5577c874ddcab6fd7b6055b7e87/manifest.json`，顶层 `passed=true`，命令 exit 0。

| 项目 | 真实结果 |
|---|---|
| cold resource import | exit 0，无 SCRIPT ERROR/ERROR |
| 原 runtime/status contract | 47 checks，failures=[]，exit 0 |
| 原 net_server_console_channel | 25 checks，failures=[]，exit 0 |
| 既有 deployment/default-policy 专项 | 13 checks，failures=[]，exit 0；保留模板15、已有61.25不覆盖、reload拒绝后已应用15不变及真实child六项 |
| 新共享合同专项 | 8 checks，failures=[]，exit 0；对比实际 source 声明与两个消费者，保留原集合/顺序并排除额外接口 |
| 实际 bootstrap 旧 DLL 接受 | 1 check，failures=[]，exit 0，SERVER_SIGNALING_NATIVE_READY |
| 合同漂移 RED | 仅隔离 channel 的 owner 合同移除 available；8 checks，恰好三项合同/观察差异失败，exit 1，无引擎错误 |
| 同冻结恢复 GREEN | 精确恢复冻结 channel 字节；8 checks，failures=[]，exit 0 |
| 缺方法，改前/共享后 | 两者同首错 `信令原生方法缺失：FateServerSignals.round64_missing_method`，exit 2；仅一条预期 ERROR，无 READY |
| ClassDB 未注册，改前/共享后 | 两者同首错 `信令原生能力未注册：Round64UnregisteredClass`，exit 2；仅一条预期 ERROR，无 READY |
| 正式 CLI / 原 console 文件 IPC | 两个独立预算15/61.25均读回实际已应用声明、四类十三方法存在、旧七字段等价、错实例拒绝；正式 stop 后自然 exit 0 |
| 收尾 | 全部自有 Job ActiveProcesses=0、日志句柄释放，generated_removed；所有 frozen source 与当前 source 无漂移 |

源级 RED 在改生产前真实执行，exit 1：明确报告缺单一来源及双声明；生产补丁后同一源级 gate failures=[]。行为 RED/GREEN 使用真实 ClassDB、实际 bootstrap/channel 与冻结源码，不以缺依赖或解析错误充当 RED。

## 命令及交付

```bash
PYTHONDONTWRITEBYTECODE=1 python newtests/round64_native_contract_source_test.py
PYTHONDONTWRITEBYTECODE=1 python newtests/round64_native_contract_runner.py --phase round64-final-source-contract --ipc
```

新增 `newtests/round64_native_contract_test.gd/.tscn`、`round64_native_rejection_test.gd/.tscn`、`round64_native_contract_source_test.py`、`round64_native_contract_runner.py`、`round64_native_source_proof.json` 与 `round64_baseline/` 改前快照/SHA。测试执行器复用原隔离 runner 的挂起创建、Job 拥有、每进程180秒预算及精确回收；引擎、全部生成物、APPDATA/LOCALAPPDATA均为独占物理 E 根，不修改原引擎或正式DLL。

原测试断言不改；旧 channel 测试历史固定输出路径仅在隔离副本改成此次自有 E fixture，转换 SHA 记入 manifest。bootstrap 专项采用无 autoload、无自动发现 descriptor 的最小独立项目；继承原 bootstrap，仅测试夹具 `_ready` 抑制角色路由，原加载/首错/exit函数不覆写。外置测试 descriptor 只将 library 路径转换成冻结 DLL 绝对路径，正式 descriptor不改。

实际旧 Windows release DLL SHA-256：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`；另一个正式 editor DLL 也未修改。没有构建新 DLL、没有权限扩张或秘密输出。

## 失败证据与边界

- 首次新增夹具错误：对 preload 类直接调用非静态 `get_script_constant_map` 导致解析错误/180秒超时；归档 `isolated-c6ed87dad9bf4cbeb4bf54983da18725`。不是功能 RED。
- 第二次夹具误将常量映射副本的引用身份当成共享声明，并对已自动加载的 descriptor 再用绝对路径重复加载；归档 `isolated-8fcf6f9fc303444d90b74aeb17940c78`。改成实际常量值与源级引用门检查，不要求编译器共享字典引用身份。
- 第三次最小项目仍使用 res:// library 路径，真实库缺失；归档 `isolated-c2edda197cd5455687989b49890bea8e`。仅测试 descriptor 转换修复，未放宽错误解析器。
- 最终对每个负向严格校验唯一预期 ERROR、精确 reason 和 exit 2。所有失败日志保留，失败生成树均已按自有 Job 退出证明回收。
- 此为当前源码与原 DLL 的 headless 证据，**未导出、不能追认旧 PCK/release 包**；未验 GUI、真人多人、跨网、完整 authority 恢复/保存/随机模拟全链。既有 default-policy 此处明确为窄部署专项，不冒充更宽 `server_simulation_default_budget` 或自然终局验收。
