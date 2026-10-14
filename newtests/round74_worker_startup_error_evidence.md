# Round74：worker 启动失败精确错误投影

## 交付范围

只修改 `scripts/net/server/server_room_manager.gd` 的既有启动失败错误出口，新增一个无状态只读 `_startup_failure`。不修改 worker、启动预算、argv builder、原生 DLL、session/loader/transport/console/CLI/shutdown 或规则。UNKNOWN 仍只报告 manager.error，不写入触发 terminate 的 room.error；已有 close_supervision 分支保持先返回。

错误提供 stage、role、room、原 PID、instance、mode、native_state、ready_report 原因和准确 report_path；不读配置内容、不扫描日志、不打印 token/密钥、不持久化新诊断状态。READY 的原始校验和接受条件不变。失败报告读取最多16384字节，仅作为诊断读取上限，不是启动期限。退出/release 前保留原绑定文本，后续撤销句柄不能抹去首错。

## Round73 原首红

- 原件 owner：`E:/scratch/isolated-04d85ad08c0e44368a323e16e9b8ddc7`。
- suite manifest：`round73-continuation-7d1e41e07ecf4ae0bfdeaef23f879593-manifest.json` 的 suites[39]、processes[43]；不能读另一个 net_server_gateway worker 的 READY 日志替代本次失败。
- 父 PID38384，exit1，48.037秒，Job ActiveProcesses=0，日志句柄已释放。
- fixture：`generated/f/isolated-50b0b2ceb8c04265b6468938a6f25c20/generated`。
- 本房间：`worker-rooms/e8b080e966247d4ad04f6f612694d323`，worker PID21564，instance `53dfd0904d2f2dcba1d895a17d099c9a`，dedicated，内部端口46387。
- `config.json` 安全白字段与 `supervisor.json` PID/instance一致；data_root为原冻结工程data，directory为本fixture子目录。配置SHA：`53386fbd1647be044e97cc3862b986db8618b5369a1b58f4dc6d1f96c9839db1`。
- 原 child log仅3行引擎/helper banner，无ERROR；最终ready.json、ready.json.tmp、stored_jsons.dat均无；data与cache目录有，cache元数据203个文件。
- 已确认：创建检查成功，随后真实句柄/READY未达成，保存请求未实际发起。原时刻 child真实argv、native launch receipt/状态/退出码未采集；不能用配置推导值冒充原观测。最终文件缺失也不能单独证明其从未短暂出现。
- **历史首红根因仍UNKNOWN**。不能证明10并发竞争、DLL故障、保存失败或超时具体卡在哪个worker调用。上述产物只约束调查在READY之前的启动边界。

## 局部RED/GREEN和一次真实READY

证据根：`E:/scratch/isolated-ae624eecf1e34f66b864522490d7903f`。复用已有OwnedJob执行器，每进程180秒，独占物理E输出，系统分配单内部端口，不碰28100。引擎为原E Godot.exe，SHA `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`；descriptor正式旧DLL SHA `92a42bd2860af19ca432321400bdaa514a2a9c11f9289a43c76e19a2e2bd68cd`，未重建替换。

实际命令：

```text
python newtests/round74_worker_startup_error_runner.py prepare
python newtests/round74_worker_startup_error_runner.py import <owner>
python newtests/round74_worker_startup_error_runner.py import-fixed <owner>
python newtests/round74_worker_startup_error_runner.py red <owner>
python newtests/round74_worker_startup_error_runner.py green <owner>
python newtests/round74_worker_startup_error_runner.py smoke <owner>
```

- 第一次import exit0但有2条VCS插件错误，原日志保留；只在独立freeze关闭正确的editor `version_control/autoload_on_startup` 后import-fixed exit0无ERROR。未修改源project.godot。
- RED：使用修改前manager与相同新夹具，Godot exit1，9 CHECK，其中4条诊断断言false，无引擎ERROR。实际机制：真实native创建worker后仅推进夹具时钟至既有绝对deadline，原生产30秒未改。
- GREEN：Godot exit0，9/9 CHECK，5.145秒；精确截止原因、创建PID/实例、产品room info消费和EXITED/release后首错保留均通过。真实失败文本样本在 `generated/green/startup-evidence.json`：`stage=startup_deadline ... pid=37672 ... native_state=RUNNING ready_report=missing`。
- SMOKE：Godot exit0，7/7 CHECK，18.776秒总场景时间；默认30秒下真实生产worker READY，worker PID10360、parent39668。Win32_Process实际CommandLine与原角色builder逐参数匹配；真实owner.verify/state为RUNNING，报告PID/实例/模式和capabilities通过原valid_ready_report。当时报告投影与OS原观测保存在 `generated/smoke/startup-evidence.json`，不是事后重建；未保存READY原始字节。
- 以上全部Job0、日志句柄已释放；GREEN/SMOKE的父日志和本次child所有文本engine日志均无ERROR/SCRIPT ERROR。测试收尾只是本次自有空大厅显式清理，不宣称正常保存、shutdown、恢复或原38-check relisten验收通过。没有重跑历史首红套件或长全恢复。

最终manager SHA：`ea4f181aacb86400ec4c46143298cf7edab3ceed952a1ba12ba78ef81f9123e4`；worker未改，SHA `2c93c8ef26e48a32e37d098beb43590114fd1c8494ab785c8ccc08741bc85a4a`。源码与GREEN/SMOKE冻结字节相同，原baseline source hashes与candidate hashes分开保留在manifest。

## 未解决与下一单变量

本单交付错误可观测性，**不宣称READY不稳定已修**。下一最窄可证伪假设：固定数据组装/校验在原截止前未完成；若获批准继续，仅在同worker的数据组装入口/出口记录绑定阶段，不改预算、数据、并发或后续恢复链。当前原日志不能证实此假设。本单到此停止，不把单次READY绿色样本升级为真人包/整恢复验收。
