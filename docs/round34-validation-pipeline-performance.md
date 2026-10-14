# Round34：校验流水线性能与发布拒绝

**已实施单一消重复磁盘副本候选；未证明完整准备链提速。最终聚焦 7 套中 6 套通过，模拟专项真实 RED，整体不能 PASS。**

## 产物与范围
- 修改 `scripts/net/validation/room_data_validation_worker.gd`：分段计时、保留二次定长复读/摘要/JSON，复用现有 verified-source 登记，组装后释放；正常生产无 user 路径输出，本地验收才启用真实回执。
- 修改 `scripts/net/validation/room_data_validator.gd`：新增默认关闭的纯计时，不改变 `validate(directory, files)` API、返回值、引用检查或顺序；原默认 `file_worker_count=20` 保持。
- 新增 `tests/validation_pipeline_performance_test.gd/.tscn`：实际 1–20 正负等价、源变更、阶段边界、发布负向、正式完整准备/采用/恢复。
- 追加授权后修改 `scripts/net/content/room_data_assembler.gd`：只增加失败诊断，原 check/write/hash/readback/rename 与拒绝语义保留，不加入重试；修改 `tests/net_validation_hard_timeout_test.gd` 的诊断标签，明确第二次成功不等于原失败复现。模拟测试未改。
- cache、validation_task、准备器、Session、规则、项目配置均未由本代理修改。工作树原有其他作者改动未回滚；无 git add/commit。

## 耦合与安全解释（改前已中文说明并用 V4A）
初检仅约 0.1 秒，二次 JSON 约 0.01 秒，不为这两项强行引入可选字节/JSON缓存。定位瓶颈后只取消 worker 的临时 blob 磁盘物化，使用既有 `register_verified_source`，没有反向 Session 依赖。
原二次复读保留且补读错误/读后长度检查，SHA256 必须匹配批准 manifest；JSON 分析只解析这次复读字节。登记时以及 assembler 每次 fetch 时都沿批准根检查路径、大小和摘要；可变源改变只会拒绝，不信任 mtime。assembler 输出仍临时写入、摘要读回后发布，采用/dataACK/规则引用不跳过。
源登记只保存 path/root/size/hash 元数据，沿原 20,000 文件清单预算；不累计 PackedByteArray。复读与登记调用栈最多两份单文件缓冲，各沿原 64MiB 单文件上限；这不是整个 Godot 进程 128MiB 内存承诺，原 JSON/模板对象仍占内存。documents 在分析后 clear，assembler/cache 引用在组装后释放；没有跨请求信任缓存。

## 实测根因：不是线程初检
首次有效完整 205 文件静态任务：task=7.834s；ready_since_engine=2.421s；initial=0.083s；reread=0.054s；cache.store=2.054s；second JSON=0.010s；loop analysis=0.020s；assembly=2.495s；load=0.482s。模拟另一次为1.378s，未跳模拟。
这证明可消的重复是「源→临时 blob→组装」磁盘副本，不是 JSON。启动至 ready 包括 Godot/脚本/autoload，计时原点是引擎 ticks，不是 OS CreateProcess 精确分解；task 总墙钟另含启动包装、退出和轮询。
批准整目录 manifest=205 文件，总声明字节=95950610；按 hash 去重的中间副本字节=95676770，候选真实 `validation-cache` 无文件。正式房主勾选条目+明确基础文件为204文件，不包括未选 tag_list.json；这两个集合不混计。

## 前后交替测量（秒，原始值，无倍数推断）
相同短 E 根/依赖冻结、相同计时器；每次 fresh task cache/assembly，顺序 A3/B3/B4/A4。A 是旧 store 流程，B 是登记候选。OS cache 未受控且有机器并行负载，不称冷盘或独占 CPU。基线只显式跳过新 helper 专属边界调用，保留真实完整流水线，中间副本断言仍 RED；失败样本不冒充功能通过。
|样本（205文件静态）|task总|引擎至ready|初检|复读|复读hash|cache.store|源登记|二次JSON|分析|assembler|加载|
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
|paired-A3|5.577|1.451|0.074|0.044|0.000|1.534|0.000|0.009|0.017|1.915|0.338|
|paired-B3|5.021|1.443|0.069|0.039|0.186|0.000|0.580|0.008|0.017|2.043|0.418|
|paired-B4|5.397|1.591|0.076|0.036|0.192|0.000|0.617|0.008|0.021|2.306|0.351|
|paired-A4|5.677|1.513|0.077|0.042|0.000|1.503|0.000|0.008|0.019|2.009|0.366|

|正式完整准备（204文件）|catalog|准备主进程墙钟|准备poll累计|child ready|child初检|child缓存/登记|child复读hash|child组装|child加载|含采用总墙钟|
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
|paired-A4|0.434|4.834|4.798|1.569|0.085|1.521|0.000|1.999|0.351|11.055|
|paired-B3|0.467|4.931|4.892|1.563|0.081|0.841|0.188|2.703|0.378|11.459|
|paired-B4|0.446|4.982|4.944|1.516|0.085|0.863|0.191|2.666|0.359|11.402|
|delivery-pipeline|0.478|5.341|5.300|1.790|0.086|0.937|0.194|2.839|0.439|12.362|

直接205文件静态任务在这组样本有约半秒减少；正式204文件整条准备链没有稳定改善（候选有更深源路径的逐次安全检查，assembler 部分更慢）。最终交付样本也保留，不能选最快样本宣称提速。已证实收益是去掉中间副本/写入，不是用户体感总等待解决。

### 初检并行 I/O/hash/JSON 观测
各文件 read/hash/json 累计值不能相加当墙钟；file_phase_wall 包括 manifest预检/任务调度/等待，references_wall 保留主线程引用检查及统计汇总。以下为交付静态205文件实际值：
```json
{
  "file_phase_wall_usec": 64309.0,
  "hash_sum_usec": 287755.0,
  "json_sum_usec": 10054.0,
  "read_sum_usec": 55358.0,
  "references_wall_usec": 7280.0
}
```

## 有效 RED/GREEN（不是解析错误）
- 中间副本消失断言先 RED：`red-intermediate-copy` 218 checks、exit1，两个 trial 都准确失败；候选 GREEN 后两次均无 blob 物化。
|冻结副本变异|exit|实际checks|精准失败|
|---|---:|---:|---|
|red-mutant-hash|1|254|reject hash workers=1；另有 19 条失败|
|red-mutant-size|1|254|reject size workers=1；另有 19 条失败|
|red-mutant-json|1|254|reject JSON workers=1；另有 59 条失败|
|red-mutant-count|1|244|empty manifest workers=1；另有 40 条失败|
|red-mutant-source|1|254|same-size mutation after initial validation rejected by actual worker reread|
五项变异只写本代理拥有的 validator/worker 冻结副本；原字节 finally 恢复且摘要相等。每个变异 exit1、无 SCRIPT ERROR/ERROR，最终当前正式流水线260 checks GREEN。count变异同时遇到一次真实组装失败，计数拒绝断言本身也明确 RED；不拿该偶发失败替代 count RED。
覆盖同长度源改动在初检→复读、登记→预组装、assembler check→write三个边界；尺寸、64MiB单文件预算、JSON语法/根型、未知操作、空/20,001清单、重复路径、1–20错误顺序和profile开关等价。保留源变化拒绝与真实第二JSON解析，不缓存内容快照。

## 原始发布失败：定位与未解决边界
round33原 `ASSEMBLY_DIAGNOSTIC reproduced=true reason=` 对应第二次 assemble=true，故该第二个对象 error为空正常；它不能解释第一个临时对象失败。此次改为 `retry_succeeded`，原失败诊断由 assembler 在 cleanup 前记录。
最终 `delivery-simulation` 原始失败：
```json
{
  "phase": "write",
  "index": 204,
  "files": 204,
  "destination_directory_exists": false,
  "destination_file_exists": false,
  "staging_exists": true,
  "destination_length": 138,
  "staging_length": 155,
  "rename_attempted": true,
  "rename_error": 1
}
```
全部204文件已写入并校验，目标不存在且路径短，最终 rename 返回 Godot FAILED=1。发生在调用者主进程预组装，早于 worker 消复制方案；不是旧schema或JSON问题。原 round33未捕获该原始错误码，不能伪称已回溯证明同一OS占锁者。
发布诊断专项先 RED（260 checks、exit1，两条准确缺诊断），后 GREEN：真实目标冲突 `rename_attempted=false,error=32`；真实 Windows FileAccess持有staging文件句柄 `rename_attempted=true,error=1`；均拒绝且不发布。只证明锁句柄是一种可复现机制，不能断言原现场是杀毒软件、索引器或本进程哪一个持有者。未引入重试或放宽门，历史/当前真实发布失败仍未解决。

## 最终同版本聚焦专项（不拼先前GREEN）
最终 user 回执观测接入后只统计 delivery-* 七套；未重跑66。此前 focused-* 的35/37通过单独保留，不覆盖下表本次simulation RED。
|suite|exit|实际CHECK=RESULT checks|判定|
|---|---:|---:|---|
|validation_pipeline_performance_test|0|260|PASS|
|net_validation_simulation_test|1|13|RED：explicit chosen data assembles under approved scratch root|
|net_validation_hard_timeout_test|0|37|PASS|
|room_data_preparation_dependencies_test|0|34|PASS|
|lobby_content_environment_restore_test|0|1544|PASS|
|net_data_sync_test|0|14|PASS|
|net_recovery_state_test|0|29|PASS|
合计实际CHECK=1931，RESULT声明=1931；6/7通过，最终import exit0/错误0。所有最终专项日志无SCRIPT ERROR/ERROR；simulation失败是业务断言而非引擎解析错误。
真实恢复/完整准备的通过不冲抵发布失败；没有窗口、多机、跨网或发行包验收。layer/private gate真实 exit0：80 findings/80 allowlist，NEW=0、STALE=0；自有生产diff --check exit0。

## E盘、冻结、所有权与归档
归档：`E:/Projects/Godot/FateDominationGame-master/reports/refactoring/round34-validation-pipeline-b7ce1621a49a4c8f937c129b24f422ff`。旧长根尝试归档：`reports/refactoring/round34-validation-pipeline-c8b009f8fe4f45db8777cda71e257b28/`。
执行脚本：`E:/scratch/round34-validation-pipeline-owner/verify.py`（归档也留副本）。实际命令形态：
```text
python -B E:/scratch/round34-validation-pipeline-owner/verify.py prepare
python -B E:/scratch/round34-validation-pipeline-owner/verify.py baseline paired-A3
python -B E:/scratch/round34-validation-pipeline-owner/verify.py scene paired-B3 validation_pipeline_performance_test
python -B E:/scratch/round34-validation-pipeline-owner/verify.py mutant hash
python -B E:/scratch/round34-validation-pipeline-owner/verify.py mutant size
python -B E:/scratch/round34-validation-pipeline-owner/verify.py mutant json
python -B E:/scratch/round34-validation-pipeline-owner/verify.py mutant count
python -B E:/scratch/round34-validation-pipeline-owner/verify.py mutant source
python -B E:/scratch/round34-validation-pipeline-owner/verify.py final-import
python -B E:/scratch/round34-validation-pipeline-owner/verify.py scene delivery-<label> <suite>
python -B E:/scratch/round34-validation-pipeline-owner/verify.py cleanup
```
引擎真实形态：`E:/v34/isolated-<UUID>/generated/engine/Godot_v4.7.2-stable_win64.exe --headless --fixed-fps 60 --path <独占冻结工程> --scene res://tests/<suite>.tscn`；完整argv/PID/exit/墙钟在manifest.processes，原stdout/stderr、child报告/批准manifest/配置与日志均有摘要。
真实最小主/child user://token物理E回执已读回，池20；最终正式校验worker另有7个实际pid/user路径/20池回执（每份user JSON真实落盘后读回，路径均在本轮E generated）。APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR仅对子进程显式指定，不修改全局。
全部已记录执行的Windows Job自有PID树已退出、active_owned_processes=0且日志句柄释放；不按Godot进程名清扫。连续运行触发3GiB预算的一次paired-A2被终止，早期执行器只在成功时保存过程回执，故该次exit/PID回执缺失，明确记录为不可用、不纳入样本；已修finally持久化。回收前额外按唯一E可执行路径查询无活进程，不能把该查询冒充缺失的历史退出码。
两份generated均归档后回收；本轮cleanup=generated_removed、exists_after=false，D盘源引擎hash未变。每轮正式数据夹具先归档再只清自有子树，避免继续积累多份中间数据。归档原始日志逐文件SHA256读回全部相等。
只在隔离project副本做已批准[editor]两字段VCS转换；生产project/threading不改，20保持。最终源相对最终候选的外部漂移为 `["scripts/game_scene/battle_board_v2.gd"]`；自有六个交付文件均匹配验收冻结。不得把七套结果包装为当前整仓最终freeze PASS。

### 自有最终SHA256
- `scripts/net/content/room_data_assembler.gd` `f39d01f8b8a48a3298c461a69fdcee986e68559066b29e69957e0899f76d282e`
- `scripts/net/validation/room_data_validation_worker.gd` `86e281f0c0987e7b76a2736373bb046ec9e0c278bef71d0d82424fe8da407a9c`
- `scripts/net/validation/room_data_validator.gd` `5a6a7fd6f8e2a9a8d91aae488ad5988bd9130ef3a8d355993427bd7eaa67efd1`
- `tests/validation_pipeline_performance_test.gd` `c4f47dcfca671a8f23a73e34e6960a0aa264cc7a770ef607caae0bbe3eec2726`
- `tests/validation_pipeline_performance_test.tscn` `9ae2cbf2883242bfe8369127904e7d32cbf6928222cad89a9f4fcd69c8ed9558`
- `tests/net_validation_hard_timeout_test.gd` `1630a3e830849e9e0d10c541494239ded2dad9ca0b57eb7e522a82b8ca7d002a`

## 其余真实问题与结论
- 首跑独占LOCALAPPDATA批准scratch尚未建立，前置1-check RED；执行器仅补建立批准根，不放宽Paths。
- 两次长根发布失败归档保留；后来短根也出现rename失败，长路径不是本轮已证实根因。
- 准备依赖首次调用收到反斜杠绝对根并被规范路径门拒绝，执行器用显式E:/参数后34-check GREEN；失败日志保留，生产路径规则未动。
- 单一消复制候选已真实运行并通过安全负向，但整体等待问题未闭环：主准备约5秒、启动/加载及安全源fetch仍占大头，发布阶段存在真实OS失败。不能称已解决服务器整体校验慢或已经完整验收。
