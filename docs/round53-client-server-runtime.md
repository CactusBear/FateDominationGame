# Round53：当前导出客户端/服务端独立运行验收

## 结论

**PARTIAL，不是 runtime green。** 当前正式客户端主入口最短 headless 启动及正常退出已实跑；同一当前服务端 EXE 分别以本机 JSON、CFG 配置达到 READY，再经正式 console `stop` 正常退出。四类完整 ClassDB 注册/方法读回、RSA 客户端建房与 settings15、保存大厅后 worker EXITED/native release **没有完成**，不能用历史 Round49 的23项充抵。

这是对已成功导出两角色的另行授权独立 scope，不是继续 Round52 已停止的信令导入 run。信令产物仍为空；没有暖重试、重新导出或修改原件。

## 单一来源与不可变性

- parent manifest：`E:/FateCandidates/round52-current-roles-20261010-sa1/manifest.json`
- manifest SHA256：`5a6f9013bbb09a29798a12b999ca1428222f0e3c061f1caf7fd005c0b72230f0`
- 新独占证据根：`E:/Caches/Hermes/cache/scratch/round53-exported-runtime-sa3/`
- 本次运行清单：上述根下 `runtime.json`，包括完整 argv、精确 PID、原始 stdout/stderr SHA、退出码、Job accounting、配置和回执。

每次启动前/退出后及最终归档均重新核对 parent `package_files` 完整集合。32批核验中，client209文件、server210文件，无 added/removed/changed；不只检查 EXE/PCK。parent manifest未改。

|产物|当前 SHA256|
|---|---|
|client EXE|`8b30b9e04970272ed3d70a4c530838570922550208ae1e1817ccb30cc0458730`|
|client PCK|`e1a01aa3a8f510f16a4eb22c573178ba66c08b9fd7fa9a5b023bcb61c14bcf44`|
|server EXE|`d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`|
|server PCK|`bb2d733b04e110c554c20f0035643a2ffea402637cdeaac269d172c882fe77b7`|

两包包内正式 cfg 的15秒仍只有 parent PCK静态审计证明。本次本机部署文件声明 enabled=true/budget15，正式 CLI 实际接受；**未取得包内 cfg runtime getter 或房间 settings 的15秒读回**，不将配置写入当作设置回执。

## 实跑结果

所有正常新 root 以 `CREATE_SUSPENDED` 创建，先加入私有 Win32 Job再恢复；没有按进程名清理。服务端 Job不启用 kill-on-close，READY未知/未保存不得强杀。每个进程180秒上限；后续外层 Python调用预算更长，避免与子进程上限同时截断。

|步骤|PID|exit|墙秒|实际证据|
|---|---:|---:|---:|---|
|client正式主入口|22720|0|2.460612|opening_background真实加载、无错误、Job active0|
|client release帮助|10984|0|0.093009|当前模板实际CLI支持列表|
|server CFG部署|37668|0|9.640653|READY pid37668/UDP57712，console stop后正常退出|
|server JSON部署|15332|0|9.431572|READY pid15332/UDP57764，console stop后正常退出|
|缺 JSON配置|28528|1|0.719207|未READY，精确拒绝日志|
|缺批准data_root|32368|1|1.232575|未READY，唯一要求显式根的拒绝|
|client包内正式validation职责用户回执|17136|1|见runtime.json|预期坏manifest拒绝；真实E用户根、pool20落盘并读回|
|server包内正式validation职责用户回执|22080|1|见runtime.json|同上，非源码注入|

另外6个正式 console进程各执行一次 `status`、`rooms`、`stop`，均exit0/无错误/Job active0。`rooms`的实际结果为空数组；`stop`即时回执为 pending/stopped=false，**不把它冒充最终保存成功**。最终真实服务端exit0及Job active0证明空服务端已退出。未生成房间，所以没有大厅保存或完整对局保存证明。

典型真实命令（完整原始argv在运行清单）：

```text
<当前client/FateDomination.exe> --headless --audio-driver Dummy --rendering-method gl_compatibility --verbose --fixed-fps 60 --quit-after 180 --log-file <独占日志>
<当前server/FateServer.exe> --headless --audio-driver Dummy --rendering-method gl_compatibility --verbose --log-file <独占日志> -- --server-gateway --config <独占deployment.cfg或json>
<当前server/FateServer.exe> --headless --audio-driver Dummy --rendering-method gl_compatibility --log-file <独占日志> -- --server-console <独占console目录>
```

console stdin实际送入 `status\nexit\n`、`rooms\nexit\n`、`stop\nexit\n`，没有Python替代网关或保存逻辑。对外/内部端口由本机UDP bind0读取，释放到正式bind是非原子交接；没有监听失败重选重试。固定批准data_root是当前server包的只读完整data目录，storage/config/console只写本次E根。

## 首个探针事故与当前阻断

首个包外 `--script` ClassDB探针 PID30432 只输出引擎banner，没有 `ROUND53_NATIVE` 或落盘注册回执，却生成正式 LoadGame JSON内容快照。外层terminal在180秒截断初版执行器，**未取得该PID实际exit和Job最终accounting**；后续精确OpenProcess error87证明当前PID已不存在，但不能追认为正常退出。完整首轮原始数据保留，不重跑该探针，不标AV。

当前release EXE的真实 `--help` 标明 release export template，CLI支持列表没有 `--script`、`--scene`、`--main-loop`、`--path`覆盖入口。Godot4.7官方 `main/main.cpp` 的 `OVERRIDE_PATH_ENABLED`分支关闭时会清空script/game_path/main_loop_type；实际现象与该限制一致。未通过更换模板/引擎、PCK override、autoload注入或源码替身绕开。

因此停止依赖包外脚本的四类读回与RSA客户端夹具链，**不是 settings15失败，也没有房间启动超时事故可以交给 sa-1 trace**。没有启动RSA建房，更没有复用历史settings成功。现有 GUI owner `sa-2-c4f0f589`可能从正式界面继续认证链，但不属于本代理结果。

要求实际读回的类/方法均保持未验：

- FateServerSignals：`enable/protect_worker/disable/take_request`
- FateProcessOwner：`available/spawn/state/verify/terminate/release`
- FateAtomicFileReplace：`replace_validated_file`
- FateCollectionIdentity：`is_supported/candidate_key`

正式服务端系统信号入口确实运行不等于全部四类注册及完整方法列表已经读取。包外原生/RSA夹具仅新增并保留，不能报运行通过。

## E用户路径与负向合同

客户端主入口stdout实际显示 `WorkerThreadPool: 20 threads`，加载包内opening场景，并在独占E `appdata/FateDomination/game_data/stored_jsons.dat`产生正式数据，SHA `e006f79791e85ea79bc5dc844eb1d80d1ad01ee7074ff3980f9277bbb0f37121`。没有 headless输入跃迁至battle；不能扩大为完整开局或GUI验收。

两包另用**已经存在于官方PCK的正式** `--room-data-validation-worker`职责和原 `HERMES_VALIDATION_USER_PROBE=1`读取 `OS.get_user_data_dir()`、PID、pool20，输出后再故意以 `{}`而非数组manifest拒绝。真实落盘JSON与stdout逐字段相同：

- client：`.../users/client-official-user-worker/appdata/FateDomination`，PID17136。
- server：`.../users/server-official-user-worker/appdata/FateDomination`，PID22080。

此负向worker没有加载规则/模拟，只验证既有正式职责的用户根生产者，**不替代客户端主入口，也不证明别的gateway PID已调用user根getter**。gateway/config/storage/console均为显式E路径；环境变量单独不作为用户根证明。没有用户路径junction操作、身份清理或密钥值读取。

实际缺配置合同：

- 缺JSON：exit1，恰有 `Parse JSON failed. Error at line 0: Unknown error getting token` 与 `服务端配置无效，CFG 只接受 server、data 与 relay 段` 两个已知诊断，没有READY。保留解析器伴随错误，不声称只有一条ERROR。
- 缺批准根：exit1，唯一 `必须显式声明 port；游戏服务还需 data_root、storage_root`，没有READY。
- 坏validation manifest：exit1，无引擎错误；落盘errors恰为 `批准清单不是数组`。

所有实际15个PID最终OpenProcess均error87。除首轮外部截断外，14个完整回收run均Job active0，stdout/stderr可重新排他打开。未将原生单进程句柄release冒充发行包的新Job树能力。

## 归档与回收

`runtime-evidence.zip`包含56个当次文件，CRC和完整逐文件SHA读回通过；SHA256：`1ed53ff08e78ad474c93062807317b45006f2e400640b53278deb0a3c0eca414`。

归档后只回收已证明正常退出的client主入口自己生成的JSON内容缓存副本1文件/373328字节，归档摘要匹配且删除后不存在；没有删除身份、真实存档、首轮事故原件、候选包或parent清单。没有复制新的完整发行包可回收。

## 文件与剩余

本代理仅新增：

- `tools/diagnostics/round53_exported_runtime.py`
- 包外夹具 `round53_native_readback.gd`、`round53_authenticated_client.gd`（编辑器可能自动生成相应.uid）
- 本报告。

Python工具语法检查通过，实际覆盖包核对、官方启动/CLI、日志审计、归档；另实测C根/项目根/批准scratch根本身均拒绝、空私有Job active0、已有deployment拒绝覆盖。夹具受当前release覆盖限制，未宣称Godot运行通过。

仍开放：完整四类native/runtime cfg15；RSA客户端房间settings15；保存大厅→worker EXITED+release；完整battle链/GUI、完整对局save/恢复；signal成功产物；新WindowsJobLease与TemporaryCleanupLease/delete_approved_temporary发行及全cleanup接线；多机跨网。**本次外层测试Job不等于这些新native能力已发行。**
