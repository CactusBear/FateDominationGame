# Round64：安全保存失败诊断边界（未接生产）

## 结论

- 新增单职责纯投影器 `scripts/net/server/recovery_save_diagnostic.gd`；不做保存、授权、清理、重试、日志、回执存储或业务回滚。
- 真实 Godot / 原生产 atomic wrapper / 原 DLL：`RESULT checks=56 failures=[]`、exit0、stderr空，无 SCRIPT ERROR；CHECK 数与 RESULT 数逐条核对。
- 新普通文件受控故障：共享删除锁返回 `native_replace / 32`；目标目录冲突返回 `open_target / 5`。这是本轮控制案例，不是旧偶发保存失败原因。
- 原失败的原生结果已丢失，旧 saved receipt 仍为 **unknown**；Round60 的86PASS复跑不能反推原故障原因。本轮没有读取、覆盖或删除旧 receipt，也没有读取真实恢复档、records、keys。
- 所有现有 production/native 源、lobby、console、manager 只读；不接 lobby，不动其他 actor 的 scripts/io wrapper，不启动28100、不导出、不跑full。

## 已读真实契约、为什么不能直接复用

1. `scripts/io/atomic_file_replace.gd:8–26`：成功/失败均是 Dictionary；原生结果原样返回。wrapper 自身失败以 `native_error=0` 表示没有捕获 OS 错误。
2. `addons/fate_server_signals/src/atomic_file_replace_binding.cpp:33–54`：准确 schema 为 `ok:bool, stage:String, native_error:int64, durability_guaranteed:false`。没有 path/PID/request identity 字段。
3. `atomic_file_replace_core.cpp:16–109`：只有 same-directory filesystem error、volume、open、stat、native_replace、filesystem_exception 分支确实携带错误来源；其他预检返回0。Windows 的 native_replace 是 SetFileInformationByHandle(FileRenameInfoEx)，不是删旧目标再 MoveFile。
4. `scripts/net/server/server_console_shared_output.gd:13–21` 已读：适合共享 stdout，故意不保留错误详情、路径、PID/请求/实例；输出只有 response_valid/ok/count/pending，无法恢复 stage/native_error。不能改它的共享隐私边界来承载此诊断。
5. `server_gateway.gd:464–477` 已读：`_diagnostic_context` 依赖当前routes/pending/manager，只投影transport可信绑定与request_seq，不处理native保存结果；外围 `_record_send_failure/_log_transport_diagnostic` 有状态/信号/IO，不能将其私有上下文投影耦合到此纯模块。`room_data_assembler.gd:diagnostic` 是组装 phase/index 的有状态输出，也不是此 schema。
6. `validated_file_content.gd:3–13` 只给 bool，校验长度及完整字节相等，**不是哈希函数**；没有原生错误接口可复用。

因此新增模块只承担“真实错误结果 → 白名单失败诊断”缺口。没有新增保存业务原语。

## 精确接口

```gdscript
static func project(stage:Variant, result:Variant = null, godot_error:Variant = null) -> Dictionary
```

- 固定 caller stage：`path / seat / snapshot / write / hash / native_commit / initial_commit`。其他值为 `unknown`，不能传自由文本。
- 失败固定五字段：`version=1, stage, native_stage, native_error, godot_error`；没有 error 文本、数据、路径或身份字段。
- native_commit 读取真实四字段 schema，严格 bool/String/int，不接受float/bool冒充整数，拒绝矛盾成功结果、非false durability、缺字段及越界错误。额外字段只丢弃，不复制或dump。
- 原生成功严格为 `ok=true / stage=published / native_error=0 / durability_guaranteed=false`，返回 `{}`；不得新增 error 或覆盖 caller 旧错误。
- 未知原生stage只输出 `native_stage=unknown / native_error=null`，不把某个整数关联到未知操作。
- 真实已采集、schema范围内的正整数原样保留；wrapper/预检0及无原生捕获能力为 `null`。非 native 分支绝不将 Godot Error 当 WinAPI errno。Godot Error 单独存正整数枚举；没有捕获就null。
- `hash` 是当前调用方内容校验分类名，**不意味着这里计算或保存任何哈希**。
- 不接收任何路径。如果main需要定位对象，只能在可信caller授权后追加批准相对标识；绝不能从 raw result 复制或截断绝对路径。
- PID、process实例及request-instance由caller当前上下文独立绑定；native字典中的同名字段全丢弃。诊断不负责认证与旧receipt更新。
- 非native分支仅在caller明确失败后调用；成功、未配置或非host未尝试保存，不凭一个stage字符串制造失败。

## 当前 failure-branch 矩阵

基线为 `lobby_session.gd:_persist_recovery_state:1670–1722`。下列是只读定位及未来建议，不是本轮接线。

|当前分支|分类/准确位置|现保留信息|本轮可投影的信息/缺口|
|---|---|---|---|
|空恢复路径或非host|未尝试，1671|false|不得直接记保存失败；caller决定是否本应保存|
|目标/temp路径授权失败|path，1675|false|stage=path，native_error=null；授权不是OS错误|
|started但recorder或seat_kinds缺失|seat，1683|false|stage=seat，native_error=null|
|seat JSON decode失败|seat，1688–1690|自由文本error后false|stage=seat；不投影或dump座位/身份数据|
|批准快照无效或活动局files空|snapshot，1691–1694|固定文本error后false|stage=snapshot，native_error=null|
|LAN/P2P journal句柄缺失|snapshot，1697|false|stage=snapshot；不打印journal路径/记录|
|identity_path及其temp授权失败|path，1700|false|stage=path，native_error=null|
|首次identity sidecar写入失败|write，1703|write_json的Error被比较后丢失|捕获单次write_json返回作godot_error；内部open/store/rename已合并，不能称WinAPI错误|
|temp FileAccess.open失败|write，1704–1705|null后false|立即捕获FileAccess.get_open_error作为godot_error；native_error=null|
|store/flush失败|write，1707–1712|局部result:Error，最终false|result非OK可原样godot_error；不读取或投影encoded|
|flush后temp/target再次授权失败|path，1712|多个and条件合并|必须拆原条件按原顺序采集；不重复调用授权检查推测失败点|
|长度/完整字节校验失败|hash，1712|matches_bytes bool|native_error=null；read-open/length/read-error/content mismatch仍无法细分|
|已有普通目标原生发布失败|native_commit，1713–1714|只取ok bool，完整stage/native_error丢失|保存一次真实返回并纯投影；保留已捕获整数/无捕获null|
|目标本身为目录，首次分支拒绝|initial_commit，1715|目录条件与rename合并|stage=initial_commit，无原生返回，native_error=null|
|首次目标创建rename失败|initial_commit，1715|Godot Error被比较后丢失|捕获同一次rename返回作godot_error，不能猜WinAPI errno|
|失败后temp清理|1721|remove返回未检查|不是原保存失败原因；本轮不改清理政策、不删除旧receipt|
|成功|1717–1720|true+内存bindings采用|诊断{}；不能增加error，不改变原业务副作用|

其他真实消费者：身份接受371、继承516、房间密码986、凭据确认1002、普通_publish1143、恢复事务1886。`_publish` 当前完全忽略bool；恢复事务1886统一覆盖业务error。密码986还有set_password短路，不能将其拒绝记成落盘故障。协议seq不是保存request-instance，不能从原生结果或请求自报字段取得。

## 交给main的最小 V4A 建议（未应用）

只替换已有目标原生分支的唯一一行；不改变前置授权、内容校验、成功分支、失败清理或bool返回。这里展示本机同步诊断sink，无路径字段。局部RefCounted是caller新建的**本次原生调用attempt**，不是房间/成员/恢复身份；PID也是caller即时取得，绝不从raw结果采信。

```text
*** Begin Patch
*** Update File: scripts/net/session/lobby_session.gd
@@
-			committed = preload("res://scripts/io/atomic_file_replace.gd").replace_validated_file(temporary, recovery_state_path, encoded.size()).get("ok", false) == true
+			var save_attempt := RefCounted.new()
+			var native_result:Dictionary = preload("res://scripts/io/atomic_file_replace.gd").replace_validated_file(temporary, recovery_state_path, encoded.size())
+			committed = native_result.get("ok", false) == true
+			if not committed:
+				var safe_failure:Dictionary = preload("res://scripts/net/server/recovery_save_diagnostic.gd").project("native_commit", native_result)
+				if not safe_failure.is_empty():
+					safe_failure["pid"] = OS.get_process_id()
+					safe_failure["request_instance"] = save_attempt.get_instance_id()
+					print("RECOVERY_SAVE_DIAGNOSTIC ", JSON.stringify(safe_failure))
*** End Patch
```

限制：这个attempt ID仅在本次同步调用活期内唯一，不是跨重启/长时异步关联凭证。main若需要持久本机回执或异步UI消费者，应绑定已有可信process-instance与其独立request-instance生命周期，不能直接采用此局部ID作为持久身份；本轮不新增这类接口、不接manager。建议不得把打印内容发给共享console projector或远端客户端，也不追加raw result / encoded /自由文本。此补丁只修“结果丢失”的观测缺口，尚不覆盖矩阵其他分支或根治故障。

其他建议调用点：1703保存write_json单次Error；1705紧邻open失败捕获get_open_error；1709捕获的result供write投影；1712逐条件拆分且不重做检查；1715首次rename保存单次Error。只能由各文件写入者执行；此文不授权改atomic/console/native。

## 确定性验收与原始证据

实际命令：

```text
python -B newtests/run_recovery_save_diagnostic.py
```

最终原件：`E:/scratch/round64-save-diagnostic-6d33bb9b6763480f99e4db431393a3d5/evidence/`，包含manifest.json、完整stdout.log、stderr.log。180s独占PID看门狗；实际Godot PID38940自然exit0。APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR及OS.get_user_data_dir实测E，最小独立工程只复制真实所需脚本、descriptor、正式DLL，未启动正式lobby或网络worker。

- 56条CHECK，包括原生真实成功无error、未知字段/恶意绑定丢弃、输入不变、输出修改不影响输入、malformed严格拒绝、未知stage、Godot Error/OS error分离、重复纯投影不改新普通文件。
- Python父进程 CreateFileW(GENERIC_READ, FILE_SHARE_READ) 持有新locked.old，明确无共享删除；真实wrapper/DLL的SetFileInformationByHandle失败返回32。独立WinAPI对同一fixture请求DELETE的CreateFileW也捕获32，**两API不同，不混称同一调用**。
- 新目录fixture使用与core一致的CreateFileW(FILE_READ_ATTRIBUTES, SHARE_READ|SHARE_DELETE, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT)，同线程立即捕获5；真实wrapper原生open_target也返回5。目录冲突不是regular_single_link_required，也不是推测的rename errno。
- wrapper/DLL失败后独立readback确认旧普通target、两个temp字节不变，目录仍在；纯投影不发布/删任何文件。原生成功消费的是本次新temp，属于原组件副作用，不是projector副作用。
- 日志不包含真实恢复内容。无SKIP，无错误日志。manifest检查source/frozen与只读lobby/wrapper/console/manager/native源码前后SHA未漂移。
- DLL SHA256：`92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`。
- projector SHA256：`96d66505708d7e2bd0980a2df3648a827bfe9eed9ee02bae2db72d919bc089a9`。
- stdout SHA256：`cffd77e0dd07f74fdc2d0f01e8b69c9da53505ca18273fa8a08f04cdd4b5e193`。
- manifest SHA256：`5fecdd7c05b2dba3bf688f5590b750ab304e4be0e1fbb08a691c8e9ca64f3107`；终末独立读回日志及本轮source SHA一致。
- 自动提取core/wrapper全部失败stage与projector白名单集合严格相等；V4A旧行唯一匹配、内存应用后的完整结果保留原失败cleanup，未写回production。纯模块静态核对无FileAccess/DirAccess/OS/Time/load/print/signal调用；建议补丁尚未经过整份lobby生产运行验收。

TDD原件另保留：接口缺失RED exit1（f6be919df8764c9dbefacc81d924b20c）；成功接口GREEN exit0（507bb97281d24d59a50305e5be6eae9b）；政策预检伪造OS错误RED exit1（c23b18e40bce4c28819aec56f37ce9a1）。均无SCRIPT ERROR，不用解析错误冒充RED。

## 未验收/仍未知

没有生产接线、完整保存事务、真实秘密恢复档、用户窗口、专用worker、冷导出/发行或旧故障重放。控制error32/error5不是旧save failure原receipt；旧故障仍unknown，禁止删旧回执、加重试、改保存业务或声称component绿色即根治。
