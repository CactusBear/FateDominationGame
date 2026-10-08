# 公共视图隐私静态审计

## 结论与边界

- 仅静态读取代码；未运行 Godot、未执行测试、未修改任何生产文件。唯一交付文件为本报告。
- 在当前正式生成链中，未发现普通客机/公共观战直接收到隐藏牌牌面、未解放从者来源技能名称或内部效果诊断的确定路径。该结论不等于动态隐私验收通过。
- **房主诊断是明确例外**：房间 owner 可收到其他玩家隐藏来源牌和效果名称；专服房主也是接收者，不仅是实际运算进程。若需求是“所有非本人连接都不可获知”，此例外不满足需求；现有测试明确锁定该例外，不能直接作为 bug 修改。
- 镜像校验存在防御纵深缺口；主要依赖可信权威正确生成，而不能独立保证所有牌区及附属 actions 的隐私。

## 五类检查

| 项目 | 当前生产路径 | 判定 |
|---|---|---|
| 网关传输诊断 | `server_gateway.gd:376–405` 只取可信路由 room/PID/instance_id、整数序号、固定 stage/code/channel；不复制 kind/args/牌面/密钥/票据，不打印任意 reason。`enet_transport.gd:12–14,97–104` 拒包元数据由本地生成 | 静态未见业务秘密泄露；PID/房间实例元数据仍会回给该连接，属于运维元数据公开，不是牌面公开 |
| 规则异常诊断 | `match_authority.gd:283–297` 直接输出来源牌 shown name 和 effect shown name；`lobby_session.gd:1502–1506` 仅 owner 收到 diagnostic，其他连接仅 paused/can_continue | 普通客机/观战不收到；owner 存在有意的跨玩家秘密访问例外 |
| 出牌 | `view_builder.gd:51,153–179` 调用统一 card_view；明置也必须 publicly_identifiable。`public_log():108–135` 将 play.object 清空，仅保留 concealed；格式化器 `tactical_board_ui.gd:4968–4973` 因此不显示来源牌名 | 未发现确定的牌面泄露；公开牌出牌日志也不显示名称是保守处理，不是隐私漏洞 |
| 弃牌/游戏外牌 | `view_builder.gd:42,45–50` 同样统一 card_view；`publicly_identifiable():186–204` 追原规则对象来源，不按牌区决定公开；未登记 BaseServant 来源失败关闭 | 正常来源链保留时，未解放从者技能移入弃牌/游戏外/出牌仍不可见；未在运行时验证来源链生命周期 |
| 隐藏牌及未解放技能 | `card_view():156–161` own 之外，concealed 或来源不可公开时，只输出 id/concealed/visible/空 back_image；未觉醒 BaseSkill 一律 visible=false。`build():36,54` 非本人且未解放时 servant={}、servant_skills=[]；BUFF `137–144` 同样查来源 | 未见牌名/图/说明/数值/effect ID/专属卡背向公共快照泄露；未解放但明置技能不因此公开 |

### 公开说明与公共日志

- `view_builder.gd:206–234` 公共说明仅卡面字段、shown_name、shown_option_name，不回退内部效果名/函数/参数；`get_shown_name()` 在隐藏对象上根本不调用，不能仅因该接口会回退内部名而判定公共泄露。
- `public_log` 有类型白名单并排除 secret_choice，不发送 effect/option_used/time_point；保留 delta/count 等公共数值事实。place/phase 为文本，生产端假设它们来自公开地图/阶段；本轮未穷尽每个 GameLog.record 写入方，不能宣称任意扩展效果均安全。
- 公开 power_breakdown 是数值分量，不含对象与来源名（`view_builder.gd:28–33`）；合计值、费用变化等可能允许玩家推断牌型，不应混同为直接泄露。是否隐藏数值侧信道需另定游戏规则口径。

## 网络消息入口与权限链

1. `match_authority.gd:63–82` 从服务器端 controllers 将连接映射到 seat，无法操作的连接 observer=-1；不是使用客户端自报 observer。
2. `lobby_session.gd:1511–1528` 为每个实际房间成员单独发送 match_bind/state/pending/actions；不是广播某一玩家的私有快照。
3. `lobby_session.gd:519–521,617–630` 客户端只收 sender=1，绑定 observer 后才接受快照；mirror 要求版本、递增 seq 和 observer 匹配。
4. `server_gateway.gd:316–322` 回包需 sender=1、路由绑定与当前 worker 匹配，只转发给该路由对应 peer；网关本身不重新生成视图，也不能替代权威过滤。
5. `match_authority.gd:503–531,562–592` pending 仅 trigger seat 收到，旁观者 actions={}（会话再添加公开暂停/连接状态）；效果标签与候选 ID 不向所有连接广播。
6. `view_builder.gd:17` 的 controller 是规则内控制者玩家 ID，不是网络 peer ID；`system/operations/AddPlayer.gd:22–25`、`global/game_data_manager.gd:48–54` 支持分身共享可见权，不能误报为 seat/peer 命名空间混用。

## 缺口/风险（未作生产修复）

### P2：power_breakdown 未执行嵌套键白名单

- 证据：`view_mirror.gd:44–49` 只验证固定数值键存在且有限，不拒绝额外键；`_primitive():203–216` 允许额外字符串/字典。例如权威误加 `power_breakdown.hidden_card_name` 会被镜像接受并保留。
- 当前 builder 不输出该额外字段，**这是确定的校验缺口，不是已证明的正式发送泄露**。
- 建议：对此子对象使用严格固定键白名单；补“合法数值键+额外秘密字段应拒绝”测试。

### P2：镜像不能识别混入 played/discard/out_of_game 的明置未解放技能

- 证据：`view_mirror.gd:69–71` 仅要求 servant 和 servant_skills 为空；其他牌区 `_card():158–195` 只检查 visible/concealed/基础字段，无法识别技能来源、未觉醒状态。错误地宣告 visible=true 的明置技能可通过校验。
- 当前 builder 用来源链统一过滤，暂未找到其实际绕过；**不能把 mirror 接受视图当成语义隐私证明**。
- 建议：回归应直接检查 builder 的出牌/弃牌/游戏外/BUFF 全链路；若需客户端再防御，须设计可信公开声明，不允许根据客户端同名模板推断秘密身份。

### P2：pending/actions 不在 Mirror 白名单内

- 证据：`lobby_session.gd:625–628` 只检查两者是 Dictionary，随后深复制；`view_mirror.gd:8` ROOT 不包含它们。可信权威误放任意 diagnostic/牌面字符串时客户端不会拒绝。
- 当前 owner 判断在发送端，未见普通客机正式收到 diagnostic。此缺口与上项一样属于权威回归/误配置风险，不是恶意客机可直接注入他人状态的路径。
- 建议：新增 pending/actions 按 kind/角色的基础类型白名单；诊断仍只由已认证会话 owner 决定发送。

### 既有测试失配及未覆盖项

- `tests/match_view_test.gd:24` 仍断言玩家不含 buffs，但当前 `view_builder.gd:43` 明确生成受过滤 buffs；该断言与当前 schema 静态矛盾，应改为验证公开 BUFF 来源过滤，而不是删生产字段。
- 该套件 `:33–38` 仅覆盖暗牌 name/image 与伪造 name，`:27–28` 仅覆盖 servant/servant_skills；本轮读取中未见它覆盖专属 back_image、未觉醒卡、技能转出牌/弃牌/游戏外、关联 BUFF 和公共说明内部诊断的完整矩阵。
- `tests/net_guard_rollback_test.gd:110,153` 明确要求房主看到来源且客机没有 diagnostic；`tests/net_runtime_guard_test.gd:59–61` 限制客机公共 guard 键。这是源码中的测试意图，**本轮没有执行，不能引用为通过结果**。

## 主代理后续验收建议（本轮禁止运行）

- 在实际规则对象上分别生成 observer=-1/他人/本人视图，覆盖暗牌、明置未解放从者技能、未觉醒技能、真名释放/重新隐藏、出牌后移入弃牌和游戏外、从者来源 BUFF、未登记从者来源。
- 对每个隐藏条目检查仅白名单 id/concealed/visible/back_image，且公共 back_image 为空；检查所有公共日志/说明无内部 effect/option/func/来源标识。
- 从真实 LAN/P2P/专服消息入口验证普通客机与旁观者 actions.guard 没有 diagnostic；单独记录 owner 诊断的已批准例外。
- 修正 buffs 旧断言后再运行相关套件。动态验收与多机验收由主代理另行串行执行，不能把本报告称为 Godot 测试通过。

## 文件与问题

- 创建：`scratch/net-batch-10/privacy.md`。
- 生产文件改动：无。
- 未执行：Godot、测试场景、运行探针、生产修复、技能写入（用户限定只能写本报告）。
- 无执行环境阻塞；主要边界是用户明确要求静态审计，以及 owner 诊断例外是否符合最终隐私政策需主代理按既有约定确认。
