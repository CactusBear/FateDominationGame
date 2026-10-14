# Round31 — blob / 数据同步真实业务回归

## 结果

修复三个旧专项的真实前置与接口调用，**未修改任何 production 文件**。同一冻结源码连续复验三项通过，并通过 client blob 112 项、原始 blob、内容 F09。最终 9 次场景共 381 CHECK，全部 exit=0、failures=[]，无 SCRIPT ERROR / timeout。tests 被 gitignore 忽略，不能用 git diff 空声称未修改；未提交。

修改：
- `tests/net_data_sync_test.gd`：正式 RSA/挑战/身份 ACK/稳定 member 前置；publish 后显式 set_room_files，等待真实批准 manifest；失败关闭并 RESULT。
- `tests/net_blob_authorization_test.gd`：三个不同 RSA 身份；稳定 member 与 transport 映射验证；改用生产 `host.create_data_preparation()` 能力组合根；数组前置失败即退出；目录改为隔离 user 物理子目录。
- `tests/net_blob_send_authorization_test.gd`：认证前置失败立即关闭；按稳定 member 撤销在线资格，不按 transport ID 索引；保留真实在线监听端验证撤销后无数据。
- 新增 `tests/net_blob_sync_identity_fixture.gd`：薄组合继承已有 net_window_identity_fixture，仅为额外 provider 生成独立 RSA，复用正式 lan_identity_challenge；不读取用户身份文件、不新增生产 setter。

## RED 与真实根因

首先逐份读取原 manifest `E:/scratch/isolated-b773afee4fab4cd3917423d551a240ef/manifest.json` 的三个 stdout/stderr。

1. net_data_sync 原有 download / assembly / existing room 三红：缺 RSA/member 前置；并且 `publish_blob` 只发布候选字节，不批准清单。不能把授权拒绝改为放行。
2. blob_authorization 三端加入失败：旧夹具未安装挑战器，正式 join 不能建立已认证稳定 member。补完后进一步暴露 `prep.session = host` 无效属性：准备器已采用显式能力注入，必须复用 `host.create_data_preparation()`，不能恢复旧字段。
3. blob_send 原先连接失败仍继续业务；索引 Dictionary key 788681313 脚本错误后无 RESULT，180 秒超时。真实连接未建立时该值只是 transport ID，不是批准的稳定 member。

本轮修前真实复现（下列目录都含 manifest 和 evidence/scene.stdout.log、scene.stderr.log）：
- `E:/scratch/isolated-5753884fbdcc4745b99f63aaac32b758/`：data sync RED。
- `E:/scratch/isolated-468c570f8afc42b9a14f65e7e041b38b/`：三端 join RED。
- `E:/scratch/isolated-28e982b4219e4fe28e1889a92ccea413/`：发送 Dictionary 脚本错误 + timeout。
- `E:/scratch/isolated-28ba851f0afd4b28887aefbc879fbfe7/`：身份已成功后的 preparation.session 接口 RED。
- `E:/scratch/isolated-696a144ae6da43719467d911e5d946cd/`：并行 ENet 端口检查/实际绑定竞态；已正常失败 RESULT，后续串行验证。

追读实际 source：Session `_receive` 保留 LAN gate、connection→stable member、生命周期/在线/seq；非主机仍先拒绝 sender!=1，然后交给 blobs.receive_client。download_provider_blob 用已登记目录及稳定 provider 创建 receiver 来源批准；_queue_blob/_pump_blobs 保留当前批准哈希、在线 member、偏移、预算和撤销复核。RoomDataSync 复用正式 receiver/cache/assembler；blob_receiver 保留来源、分块顺序、摘要与预算释放。补正确夹具后上述真实生产链全部通过，无依据改生产授权逻辑。

## 冻结 GREEN

结果索引：`E:/scratch/round31-blob-sync-results.json`。每行 manifest 的 `source_files` 哈希映射程序化比较完全相同；最终重新对主仓库三个测试、新夹具、blob_receiver、room_data_sync、lobby_session 校验，均等于冻结哈希。

| 专项 | CHECK | 首次冻结 manifest run_id | 连续复验 run_id |
|---|---:|---|---|
| net_data_sync_test | 14 | 1e093b5b07514e7092548055ec5447aa | b34a7c53a35a49a5a302d3f31fdd4c80 |
| net_blob_authorization_test | 58 | dc82f517a6a04d548287a6f430718935 | 89f31d7b09704aa8859d705ac694e049 |
| net_blob_send_authorization_test | 14 | 0f38b262d970441bb95b00a5cfe6a96e | 6dba539df16b4d5cb7c3ac46db320af7 |
| client_blob_inbox_test | 112 | 3d886298eff94776813cb7561aa23b76 | — |
| net_blob_test | 42 | f78b6e75d42f44cab1ecebe79b302cbc | — |
| host_content_inbox_contract_test（内容 F09） | 55 | 246b98071a754d078e027c18ad7a662f | — |

完整路径均为 `E:/scratch/isolated-<run_id>/manifest.json`，stdout/stderr 和 source SHA256 在其 evidence/manifest 中。

覆盖未批准候选、取消、相同哈希不同路径/来源、当前清单批准、旧哈希撤销、provider 正式目录上传、多分块摘要、provider 真掉线后权威完整副本继续分发、已排队撤销/相同哈希跨 revision 保持、offline member 不送；F09 同时验证资产未安装 ACK 拒绝、当前/旧/未来 revision、稳定 member 确认、seq 与生命周期门。

## 前置失败不能越界

只在独占夹具提供 `FATE_BLOB_SYNC_TEST_FAIL_IDENTITY=1`，真实引擎分别运行三项。全部自然 exit=1、恰好一个失败 RESULT，stderr 空、无超时：
- data sync：3 checks；`E:/scratch/isolated-575eb8d5a69e41efb219471ca303406a/manifest.json`。
- blob authorization：2 checks；`E:/scratch/isolated-4f09fbad4e21414bb5278c0067fe4ecd/manifest.json`。
- blob send：2 checks；`E:/scratch/isolated-0d681b555b184aabb5747c78e4e15e82/manifest.json`。

索引：`E:/scratch/round31-blob-sync-negative-results.json`。这些是期望 RED，不记作业务 GREEN。

## 实际命令、路径及收尾

执行器：`python tools/run_isolated_godot_test.py --project <物理E冻结源> --root E:/scratch --godot E:/scratch/round31-blob-sync-engine/Godot.exe --timeout 180 --max-bytes 2147483648 --min-free-bytes 1073741824 --freeze --include <显式依赖> --scene res://tests/<专项>.tscn`。

冻结驱动脚本：`E:/scratch/round31-blob-sync-runs.py`。实际引擎命令：`Godot.exe --headless --fixed-fps 60 --path <isolated-run/generated/project> --scene res://tests/<专项>.tscn`。

执行器先由真实 Godot 主进程及其 OS child 在 E 独占 APPDATA 写回执，验证实际 user 路径与物理落盘、child exit=0；不是只检查环境字符串。首项实证主/child 物理路径为 `E:/scratch/isolated-1e093b5b07514e7092548055ec5447aa/generated/appdata/FateDomination`。每次 180 秒上限、无窗口、只回收自有 PID；最终 9 轮 27 个执行器记录均 exited=true、active_owned_processes=0、log_handles_released=true，全部 generated_removed。所有日志/哈希在回收前归档。

冻结配置边界：原配置 `version_control/autoload_on_startup=true` 使新冻结第一次 editor import 报 GitPlugin 类不存在；`acbcc5ea3e4445dcb907fdb31ed4815a` / `66b1c685dfb44549be6286a64432c662` 留存导入 RED。仅独占冻结源关闭编辑器 VCS 自动启动，正式 project.godot 未改，application/user/network/threading 不变；receipt 为 `E:/scratch/round31-blob-sync-source-receipt.json`。因此不宣称原配置的全新 editor 导入通过。

冻结源及本轮独占引擎已在全部退出后回收，最小源码/配置归档到 `E:/scratch/round31-blob-sync-source-evidence/`。本轮不覆盖窗口、多机/跨网、独立主管 worker 拓扑；本次三端身份证据为同进程真实 ENet + 正式 RSA 挑战 + 稳定 member。已有 production 工作树差异属于此前/其他代理，不是本轮修改。
