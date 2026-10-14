# Round50：本机管理员请求 codec 边界

## 交付结果

- 生产只写 `scripts/net/server/server_console_channel.gd`，新增 `scripts/net/server/server_admin_request_codec.gd`；新增真实 Godot 帧循环专项 `tests/server_admin_request_codec_loop_test.gd/.tscn`。没有修改 manager/gateway/worker/server_cli/room_control/cleanup ledger/executor/policy/native/gate、引擎或原工程配置。
- 最终同一冻结四套 **149 CHECK、failures=[]、全部 exit0、无 SCRIPT ERROR/ERROR**：新 codec loop 71，旧 command line 15，旧 console channel 25，真实 worker 保存关闭/relisten 38。顶层 manifest passed=true；不是拼接不同冻结的通过记录。
- 另一次扩展冻结中的旧中局 console save **整套未通过**：保存、种子及磁盘日志对应检查已经实际通过，随后恢复阶段出现客户端断线负向 CHECK，收尾触及 180 秒预算，exit125；该次旧 console close 尚未执行。不能宣称完整中局恢复或旧 close 套件通过。

## 当前原合同及解耦说明

原 console 把命令行重排、信封 JSON、连接/PID 格式和房间实例关联比较混在命令/文件 transport/生命周期逻辑中。新 codec 只有数据解释能力，无 gateway、manager、signaling、DirAccess、OS、Time、handler、trusted_local 或 cleanup ledger 依赖。

1. **文件信封仍是恰好 `{instance, command}` 两字段**；没有新增 action/args wire schema。`read_request` 复用已打开 FileAccess 的 get_length/get_as_text 与 JSON 原语；文件开关、目录扫描、响应落盘和请求退休仍在 channel。`parse_object` 也被 channel 的 ready/request/response 读取复用，不复制扫描、执行或存档规则。
2. `decode_command` 复用原 `server_command_line.parse`，保持引号、转义、空参数和 room 参数位置重排；输出 action+PackedStringArray args。`valid_arguments` 只比较原 commands 声明的参数数。命令白名单及 handler、未知命令错误、可信本机权限检查顺序仍在 execute owner，codec 不授权执行。
3. 整数规则不统一收紧：连接号仍是原 `is_valid_int` 和 2..2147483647；`room kick` 先维持原整数形状，再由 owner 检查房间归属、走 _kick 范围门。legacy PID 仍要求规范十进制文本回转相等，没有新增正数/PID 最大值政策。JSON PID 与既有 binding 使用原相等比较，保留 JSON 数字原语的 float 表现，不发明 int-only 门。
4. ready/binding/response 关联比较抽为纯判断。当前/retired/closed binding 的选择、UNKNOWN/RUNNING/EXITED 判定、保存证据、release/cancel/retire 与消费时间/摘要仍由原 owner 执行。worker action 白名单和执行循环未迁移，也没有新增 worker/action 服务。
5. `valid_id` 原静态入口保留并委托 codec；仍仅 32 位小写 hex。预算仍是原 `max_request_bytes=4096`、`requests_per_poll=4`、`max_room_requests=128`，所有使用者可继续传原 owner 的值，未增加新数字上限。只扫描 `*.request.json`，invalid id/response/tmp 不读、不执行。
6. 唯一有意行为修正：原 console 对已有同 ID response 的重新投递仍会执行命令，RED 真实复现配置从 7 被改到 99。现在采用已有 worker 通道方式：已有 response 就不再次执行、不覆盖原回执，并退休重复 request。已有回执的文件名是 console 的请求绑定；**没有悄悄给 console response 加 worker 的五字段协议**。这里 duplicate 指同 request ID 重投；JSON 原语的重复键语义没有被擅自替换或宣称严格拒绝。原 write_json 返回失败时请求保留/可能重试的合同也没有改成新的持久 exactly-once 服务。
7. malformed/oversize/foreign instance/错误 args/未知 action/未闭合引号都保留原拒绝。没有新增原始 request、command 参数、身份或摘要的诊断日志；负向测试的载荷标记 `NEVER_PRINT_ADMIN_PAYLOAD` 在 stdout/stderr 中不存在。

按 RED 冻结原 channel 与交付版本逐函数比较，`write_json`、configure_cleanup_schedule、poll_cleanup_schedule、configure_cleanup_ledger、cleanup_temporary、_room_save、_room_close、saved_close_receipt、_room_consumed、acknowledge_close_result、_room_forget 函数块逐字相同。_poll_room_closes 仅把原字段比较改为 codec 委托，后面的生命周期分支不变。

## 保存、消费及公开 cleanup 保守门

- `saved_close_receipt` 仍要求 bool ok=true、bool closing=true，以及 bool saved=true 或 bool room_state_saved=true；closing 或整数 saved=1 不是保存证据。
- 请求提交仍只返回 pending；save 的 pending.saved=false；成功保存及真实 EXITED/release 的历史关联选择不变。result 读取和内部 poll 不是消费确认。
- consumed 仍必须可信本机 execute；原 acknowledge_close_result 检查配置、保存成功、64 字节摘要绑定及 manager.closed history 后调用原 ledger.consume_close；未把 codec 变成权限或 cleanup 服务。
- 新专项显式启用本机 schedule 后，due 结果仍 blocked=true、removed_files=0，missing_capabilities 保留 complete_instance_registry/cross_process_file_exclusion，原成功 response 的 hash 保持。preview 的诊断 ok 字段不能解释为删除许可；没有删除 proof，不能声称实际清理成功。

## RED / GREEN / 真实执行证据

### RED

`E:/scratch/isolated-53a359e30b1049b189b091b4195b7eca/manifest.json`：7 CHECK，唯一失败 `duplicate request ID cannot execute side effect again`，exit1；不是缺模块/语法错误作为 RED。Godot Node._process 实际泵送 production channel.poll，文件请求执行 production relay.configure 后同 ID 重投改变了真实配置。

修复后的初轮 GREEN 为 `isolated-51584481b4f44afe9bbf3ed217d56000`，新 loop 7、旧 command line 15、旧 channel 25 全部 exit0。之后扩大专项覆盖并再次独立冻结；这条初轮记录不加入最终149。

### 最终同冻 GREEN

命令：

```text
python -B E:/scratch/round50-admin-codec/run.py server_admin_request_codec_loop net_server_command_line net_server_console_channel gateway_relisten_acceptance
```

所有真实场景进程命令使用同一独占 E 引擎副本：

```text
Godot.exe --headless --fixed-fps 60 --path <UUID>/generated/project --scene res://tests/<suite>_test.tscn -- <UUID>/generated/fixture-<suite>
```

manifest：`E:/scratch/isolated-c6ffeea100b8438185946484054c5ace/manifest.json`

SHA256：`45c2047dc853fb1ed8dcf7a00457ec214bd57d612e0a8636ad3949ac2b181fba`

|套件|CHECK|exit|墙钟秒|
|---|---:|---:|---:|
|server_admin_request_codec_loop|71|0|4.505|
|net_server_command_line|15|0|4.002|
|net_server_console_channel|25|0|4.044|
|gateway_relisten_acceptance|38|0|15.268|

新 loop 主 PID15108，用 CountingCodec 子类仅计数并 super 调用，断言实际 poll 调用 read_request/decode_command，不是只做模块单元测试；合法请求改真实 relay 配置，同ID重投停止在 codec/execute 之前。检查 exact4096 字节请求仍合法，额外字段、自报信任、新 action/args 信封、数组、wrong arity、invalid filename/tmp/response、整数/规范 PID、非本机来源以及消费 owner 门。foreign response/request 四字段及 request_id 通过真实 channel.execute→_room_result→codec 文件读取链拒绝；这部分注册是受控文件接缝，明确**不冒充原生进程监督证明**。

真正的独立 worker/native supervision 证据来自 PID9180 的 gateway_relisten_acceptance：原 manager 创建独立 worker，原 room control 实际持久化房间状态、发布关联保存关闭回执；直到真实 EXITED/release 后才完成监督，recovery.json 保留，旧实例关闭历史不能证明替换后的 UNKNOWN。旧 console channel 同时仍跑真实 WebSocket/WebRTC 管理和直接游戏连接专项。

原日志：最终 owner/evidence 下四套 stdout/stderr.log；实际新 user output 日志均未见 SCRIPT ERROR/ERROR；frozen-source 保留 channel/codec/关键 owner 源码。

### 扩展失败不覆盖

`E:/scratch/isolated-2cbf0ca123594d528ab53756258d7ec0/manifest.json`，顶层 passed=false，net_server_console_save 根 PID37884，Job 回收后 exit125，budget_failure=timeout，所有 owned processes=0。原 stdout 先证明：

- 保存提交为 pending 且 saved=false；实际房间子进程保存完成、磁盘可读日志/hash 与回执对应。
- 原 int64 seed 与磁盘头一致，路径穿越 request ID 被拒绝。
- 后续中局恢复阶段 `恢复后客户端错误立即终止同步等待：房间连接已断开` 和 `中局恢复失败后立即短路，不级联等待至测试预算耗尽` CHECK false；随后进入原保存关闭收尾，180秒门终止。

未查明该恢复失败根因，不能说是既有问题或已修复；涉及只读 Session/worker/manager 边界，交主代理继续定位。没有擅改这些 actor、没有扩大超时、没有把这条日志称通过。这个扩展冻结内前四套通过，也不追加进最终149。

其他失败原件保留：e29b2b52 冻结导入因一次补丁缩进使 request 越界，已在独占 channel 内纠正；570f0f/e1bf59 的扩展专项缺显式根/根目录不存在，已修**外部 runner 参数**而非生产/test 源码。早期旧专项的硬编码 E:/Projects/Godot/FateDomination/test 输出路径未自动删除；最终 runner 仅把冻结的两份旧 test 输出前缀换成 UUID/generated/legacy-test，原测试源码不改，转换名和冻结摘要都在 manifest。

## 独占 E、预算及引擎

执行器：`E:/scratch/round50-admin-codec/run.py`，调用只读 `tools/run_isolated_godot_test.py` 的既有 Windows Job/物理路径/RESULT/清理原语。

- 每套180秒，生成树监控2,000,000,000 bytes，最低剩余1,000,000,000 bytes；这是测试监控预算，不是新增生产政策，也不是 OS 硬盘配额。
- copied engine SHA256=`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；原 D 盘非_console 引擎 hash 未变，不改引擎、不改 global TEMP。
- application/threading 原配置保留，真实 main/OS.create_process worker 的 user:// token/回执由现有 probe 证明物理 E；pool20 保持，不动默认15秒校验声明。
- 冻结仅关本地副本 VCS 自动启动、明确 test main scene，以及上述旧测试输出前缀；真实资源导入后真实 autoload 导入均 exit0且没有 ERROR；不是补造 .godot。
- 最终 source_drift=[]、frozen_drift=[]。全部 Job 自有进程退出、ActiveProcesses=0、日志句柄释放；generated 树已按 UUID owner manifest 消费，原日志/源码/manifest 保留。没有按进程名称回收，没有 GUI，没有读用户身份/secret 文件。

## 源码 SHA256 及只读边界

最终执行前、执行后、交付读回以下 hash 均一致。channel 的 RED 原hash为 `1fb5a02c645dc249d42c48be97ae7d2cced0552fcd155296097594ff970dd58d`。本轮生产写入的hash：

|文件|SHA256|
|---|---|
|server_console_channel.gd|91ebbc0632def2a5a0b537e75752b23dd1547eb72c77aa868fae98c27715a240|
|server_admin_request_codec.gd|970c86654563b2d3a9b87ded76229bbd6d1466ba3a5ada05a8f5e3d647b91a89|
|server_admin_request_codec_loop_test.gd|e798c339a994c93214a4d5014a88303e9b5e08a30147179bc17eeb1adb837236|
|server_admin_request_codec_loop_test.tscn|80f94c68f67ca8c774127dd2767651442fa5e8d065b69f185744ec0e6c04af04|

以下 actor 从 RED 冻结起到最终及交付完全一致，且本人无写入：

|scripts/net/server 下文件|SHA256|
|---|---|
|server_room_control.gd|296edf36916d77d767e67fceeb33808554e8e487dabb92a43ac0fa5703630997|
|server_room_manager.gd|65a19312d7e3afbeed6dd238d03bf4437613ad9e915555c4316a58f8091cdddb|
|server_gateway.gd|c93b92cba86fa317c7f8eed027d3ae73dc544650869e142d2ad38dcb084a4112|
|server_room_worker.gd|2c93c8ef26e48a32e37d098beb43590114fd1c8494ab785c8ccc08741bc85a4a|
|server_cli.gd|8ecc943bd496ef2c85e16e66c3495a6b37b63818d56e94e2e398c0a94ddfaf6a|
|temporary_cleanup_ledger.gd|387d17b398eefa76d81794af97de98cd1ac673bfa4bf626ad0f5dd298778d1c5|
|temporary_cleanup_executor.gd|e11bf2d764b9c43a89795152623ededc23d654ee0878d8b087b6c09beadf58a0|
|temporary_cleanup_policy.gd|1267c21231bc52b9592efde775828fcfcec8f599b9ee4f70e8f374803e10dc51|

project.godot 原源hash=`986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a`，RED/最终/读回一致。所有被复制源码（含 native .dll/.gdextension）前后hash及场景参数在 manifest.source_before/source_after/frozen_before/frozen_after 可复核。git diff --check 当前 channel 无问题；没有 commit/push。新测试被仓库现有 `.gitignore:47:/tests/` 忽略，文件已真实生成和运行，未擅改 ignore 或执行 git add，后续收集产物必须显式包含这两个路径。
