# Worker READY 前启动阶段可观测性：窄正确性证据

## 交付及语义

产品只改 `scripts/net/server/server_room_worker.gd`：沿真实 `_ready()` 初始化、目录扫描/计划、缓存填充、组装、固定副本校验、内容环境安装/规则重载、host、资源发布及 READY 发布的完成点写已有 engine 日志。格式仅 `SERVER_ROOM_STARTUP stage=<固定阶段名> result=<结果码>`；1=进入，0=当前调用/门禁或条件分支完成，-1=原拒绝出口。每文件循环不逐项输出、不记录时间、路径、身份、票据、配置或内容。不把可选分支完成理解为该可选调用执行；void 调用返回也不是语义校验或 READY 授权。

`_ready()` 复用单一局部 stage，内容加载子调用也用局部 stage；无新持久状态、新 IPC 文件、新控制协议。启动 `_fail` 传递当前阶段，先记录拒绝再走原错误与清理；其他 `_fail` 调用默认不记录启动拒绝。deadline、原校验条件与调用次数、READY 报告/接受、安全关闭均未改。

对 round74 上一冻结 worker 去除纯观测行/助手并还原 `_fail` 参数后，完整产品代码逐字比较相等（仅首尾空白不计）；旧 worker SHA `2c93c8ef26e48a32e37d098beb43590114fd1c8494ab785c8ccc08741bc85a4a`。本次产品源码与实际运行冻结 SHA 相同：`a1d935675ce6d6a3f804ac9000104b15d95c2c279c8cf13c459acdd3920107eb`。manager/gateway/Session/原生源码与 DLL 均未写；manager/gateway/Session 和正式 DLL 与本次冻结指纹一致。`git diff --check` exit0；工作树原有其他修改未动。

## 一次真实 READY + 一次显式无效数据拒绝

执行器：`newtests/round74_worker_startup_stages_runner.py`；专属场景：`newtests/round74_worker_startup_stages_test.{gd,tscn}`。仅 headless 单空大厅 worker，产品 manager/native spawn、原30秒期限、系统分配单内部端口，不碰28100。每进程180秒看门狗，独占物理 E freeze/output，OwnedJob，保留原始证据。

证据根 `E:/scratch/isolated-e3d7105dae1b44edb5d78c0c5691082a`，manifest `manifest.json`；原 E engine SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。实际 descriptor 旧正式 DLL SHA `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`，没有重建/替换。仅隔离副本关闭 editor VCS 自动启动，源 project.godot 未改。

实际命令（各 exit0）：

```text
python newtests/round74_worker_startup_stages_runner.py prepare
python newtests/round74_worker_startup_stages_runner.py import E:/scratch/isolated-e3d7105dae1b44edb5d78c0c5691082a
python newtests/round74_worker_startup_stages_runner.py ready E:/scratch/isolated-e3d7105dae1b44edb5d78c0c5691082a
python newtests/round74_worker_startup_stages_runner.py invalid E:/scratch/isolated-e3d7105dae1b44edb5d78c0c5691082a
```

- 导入 exit0，无 ERROR/SCRIPT ERROR。
- READY：9/9 CHECK，RESULT failures=[]，父 exit0；通过原真实 native 身份/READY 报告门。child `evidence/ready-worker-engine.log` 有52条阶段标记，顺序逐项完全匹配；`ready_publication result=0` 之后保留原 SERVER_ROOM_READY。父/child 无 ERROR/SCRIPT ERROR。
- 拒绝：10/10 CHECK，RESULT failures=[]，父 exit0。仅在独立冻结 data 的 `card_backs/startup_invalid.json` 写 JSON 标量私有哨兵；真实 catalog/base/缓存/assembler 接收并组装，原 validator 拒绝 JSON 标量根。child `evidence/invalid-worker-engine.log` 有22条标记，最后完成 `data_assembly result=0`，随后 `data_validation result=1`、`data_validation result=-1`；无后续阶段/READY。manager 观察真实 worker_exit_before_ready，不 fake READY/截止。
- child 唯一预期 ERROR 精确为 `JSON 根节点不是对象或数组：card_backs/startup_invalid.json`；独立 Python 校验整份 child ERROR 列表恰为此一条，不宽泛白名单、不吞 SCRIPT ERROR。原错误/栈保留，私有哨兵内容不出整份 child 日志。新增标记逐行白名单正则/有限阶段检查，绑定ID/PID/路径/配置/票据字段不出。
- 两场景只显式清理本次自有空大厅，先退出再读/归档日志，不扫描活体发布目录。所有运行 Job ActiveProcesses=0，日志句柄释放。`generated/{ready,invalid}/stage-evidence.json` 保存实际阶段序列与断言，原始日志/manifest 保留。
- 改前静态 RED 为缺失阶段输出断言 exit1；没有为 RED 再启动一轮长校验。仅上述两个真实业务启动，无保存恢复、整 gateway/full、随机15秒模拟或测速对照。

## 保留边界

历史 PID21564 日志仍只有 banner，cause=UNKNOWN；本次正负样本不能回推它卡在哪个调用，也不宣称 READY 不稳定或历史故障已修。未来日志可读最后 result=0 与随后未完成/拒绝阶段；若连第一个标记都没有，只能说明未观测到 `_ready()` 内阶段（或日志不可用），不能伪造阶段成功。未验收恢复分支、LAN/P2P、正常保存/安全关停、真人包、全量；本单到此停止。
