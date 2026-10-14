# Round47：服务端目录与状态协议收件提取

## 交付与边界

生产仅修改 `scripts/net/session/lobby_session.gd`，新增 `scripts/net/session/server_data_status_inbox.gd`；保持进入本轮时已有未提交补丁。没有修改 room、其他 inbox API、validation task/worker/preparation/simulation、server_data_approval、room_data_panel、GUI fixture 或 cfg。

客户端 `server_data_catalog`、`server_data_catalog_part`、`server_data_status` 迁入同一无 Session/Room/回调反向引用的组件。组件唯一持有 Dictionary，Session 的 `server_data` getter 保持生产 UI 原读取形状；无旧私有字段别名、泛用服务定位器、download/blob 副本。目录验证复用 DataCatalog，分片复用 Session 已有 `_catalog_transfer.accept`；发送端仍是原 `send_catalog_message`。

组合根保留来源 sender=1、恢复/启动/请求重置门和当前 view.owner/view.phase 资格判断；组件消费已识别但格式无效的消息。changed/rejected 仍由 Session 显式发出。目录成功清除 Session.error 的原副作用也显式保留。

## 保留的协议与状态契约（GUI owner 交接）

- 没有增加线协议字段，倒计时只传既有 `state.text`，不制造第二套 UI；status/report/origins 仍深复制原消息，未增加路径、密钥、恢复票据暴露。
- 当前 owner 且当前 phase=lobby 才接受管理投影，失去资格时清空状态与候选目录待拼装分片；旧 owner 投递不接收。host 端批准请求分派没有迁移或改规则。
- 旧 request_id 不覆盖当前状态。同一 request_id 的 catalog_revision 固定；目录本身可以刷新到新 revision，正在准备的旧 snapshot 仍可进入 ready/commit/applied。**不要求 status.catalog_revision 等于最新目录 revision。**
- ready 是“校验完成、风险/批准待确认”，不是批准终态；同 request 的迟到 preparing 不倒退 ready，但 applied/error/cancelled 回执仍可接收。仅 applied/error/cancelled 为终态，同 request 后续状态不复活该事务；更大 request_id 正常进入新 preparing。没有另加 stage 类型、时限、非负限制或猜测规则。
- reset 接入已有 `_begin_request_reset`：代际加一后、`request_associations_invalidated` 发出前重置 inbox 与 catalog fragments；close/join/rejoin 复用这一入口。公开 reconnect 不继承旧管理状态/高水位。
- 本轮不修“倒计时归零不能宣布成功”的生产完成链；该问题仍由 GUI/validation 唯一写者负责。这里不会将归零 text 判断成 ready，更不会自动批准。

GUI owner 可沿原 `session.server_data.status`、`changed` 接线，不需要改 fixture 猜字段。交付生产 SHA256：

| 源 | SHA256 |
|---|---|
| lobby_session.gd | `89f250bc71372ea70e4a8d011e4334b931f78537aea1165d5f0a0a002d26c005` |
| server_data_status_inbox.gd | `c46b44bd9e19ccef1fe408491fb0ce0896941a2714a429509d41294e1785f9c3` |

其余批准/validation/panel 的完整冻结与当前源摘要见 `reports/refactoring/round47-server-data-inbox/handoff-source-hashes.json`，交付时逐项匹配。并发其他写者的后续版本需由主代理整合重验，不能把本轮冻结通过当其新版本通过。

## 真实 RED → GREEN

证据根：`reports/refactoring/round47-server-data-inbox/`。

1. `frozen-original-red`：生产提取前真实 ENet、公开 join/transfer/reconnect、RSA 挑战；exit1，53 checks，7 条精确业务失败：ready→preparing、applied→preparing、cancelled→preparing、error→ready 覆盖，以及重连旧状态未清/重连失效信号前未清/close失效信号前未清。没有解析或引擎错误。其余原 owner 门、目录刷新、ready后commit结果、分片收件已通过。初始夹具身份/分片泵送问题日志也保留，不能混称业务 RED。
2. `qualification-mutation-red`：只在独占物理 E 副本删除 qualified 收件门；exit1，62 checks，精确捕获“旧owner投递不接收”“重新授权不沿用旧owner请求高水位”“非lobby当前phase投递不接收”。共享生产树未变异。
3. `revision-mutation-red`：只在独占副本移除同request revision绑定；exit1，62 checks，唯一失败为“同request_catalog_revision绑定不可变”。
4. 最终 `delivery-green` **同一冻结**：
   - `server_data_status_inbox_contract_test`：PID31552，exit0，65 checks，failures=[]，2.555s，无 SCRIPT ERROR/ERROR。覆盖真实 ENet 当前目录/分片/status/text/risk report、ready→commit回执、各终态稳定、旧request、固定revision但允许目录刷新、格式无效无changed、owner/phase资格、公开reconnect/close代际与真实首分片清理。倒计时字符串为协议夹具，不声称这代替真实GUI倒计时。
   - `server_data_status_inbox_approval_test`：PID32744，exit0，22 checks，failures=[]，38.491s，无 SCRIPT ERROR/ERROR。完整继承当前正式 `net_server_data_approval_test.run` 与全部断言：公开网关→真实权威worker→真实提供者上传JSON/图片→准备/隔离加载→ready→取消→旧commit拒绝→新准备→ready→当前commit→applied→双方相同新revision→批准JSON逐字节下载读回。
   - 主/派生 user-data 物理 E 探针成功，Windows Job ActiveProcesses=0；自有引擎、副本与生成目录已回收，`E:/HermesScratch/round47-server-data-inbox` 无剩余独占树。原引擎/编辑器未关闭。

最终复跑命令：

```text
python reports/refactoring/round47-server-data-inbox/run_round47.py delivery-green --approval
```

内部真实场景命令为独占 E `Godot.exe --headless --fixed-fps 60 --path <owned E project> --scene res://tests/<suite>.tscn`；每进程180秒，生成字节预算3000000000，最小剩余1000000000。完整命令、PID、退出码、主/worker落盘探针与原日志均在 `delivery-green-*-manifest.json` 和 `delivery-green-result.json`。

## 正式测试前置适配与已见问题

- 原正式套件无显式 `manager.approved_data_root`，初次5 checks停在创建worker，并报“批准数据根必须由本机部署入口显式提供”。自有继承夹具只补当前部署根与workers目录，不覆盖任何正式批准流程/断言。
- 正式套件硬编码提供者输出根；仅冻结副本转换为本次独占物理 E 子目录，以便Job退出后全部回收。原正式测试文件不改。转换前后hash与唯一改动见 fixture_transforms；GUI夹具没有修改。
- 中间 `final-current-green` 曾在原22秒就绪等待后只完成5 checks，worker未入房且该日志没有具体错误；保留该失败，不猜原因。后续 `final-verified` 与最终 `delivery-green` 均完整22 checks通过，未延长等待、删断言或降低预算。
- `git diff --check -- scripts/net/session/lobby_session.gd` exit0。全仓 `python tools/check_layer_deps.py` 为FAIL：findings=62/allowlist=80/new=0/stale=18（既有其他文件白名单漂移）；没有越权更新白名单，不能称全仓门通过。
- 本轮没有窗口输入、GUI成功宣布、risk真人确认或跨网验收；交主代理/唯一GUI owner整合验证。

## 当前库存与文件

自有新增测试 `tests/server_data_status_inbox_contract_test.gd/.tscn`、`tests/server_data_status_inbox_approval_test.gd/.tscn`（tests被gitignore，交付时注意显式纳入）；自有运行脚本和最小证据位于上述reports根。

程序化枚举剩余 Session `match message.kind` 的16个字面kind（`kind-inventory.json`）：identity_candidates、identity_inherit、room_password、server_data_catalog、server_data_prepare、server_data_commit、server_data_cancel、identity_ack、preview_group、begin_match、match_command、broadcast_confirm_absent、match_finished_lobby、join、start、choose_master。前三类客户端协议收件迁出；host批准入口四类命令仍原分派，身份/凭据、房间、选人、对局、guard/content等职责保持其现有分层。
