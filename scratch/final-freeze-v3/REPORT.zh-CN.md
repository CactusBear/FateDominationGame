# 最终十路合并冻结前检查报告 v3

## 结果

**工具已交付并通过 Python 单元测试；最终冻结未获批准，Godot 动态验收全部未运行。**

- 新增仅在 `tests/final_verification_v3/` 和 `scratch/final-freeze-v3/`。未修改生产、未启动/关闭 Godot、未改 .gitignore/index、未触碰真实凭据或游戏存档。
- 读取了 hermesWarning、引擎技能/testing reference、现有 v2 工具/计划与 `final-security-audit-v2/报告.zh-CN.md`。v2 证据实际位于 Hermes cache scratch，不在项目 scratch；本工具复用仓库的 `tests/final_verification_v2/verify.py`。
- 工具验证：21 个 Python 单元测试通过，原始退出码 0，见 `tool-unit-tests-final.log`。合成日志仅用于解析器/门槛测试，不是 Godot 通过结果；临时合成文件测试结束即清理。保留三组 RED 日志和最终 GREEN 日志。
- 真实静态扫描：`inspect-final.json`，退出码 **2（前置拒绝）**。扫描得到 **340 个场景、481 个场景×模式条目，其中340个必须验收条目**。headless 窗口比较项是诊断，不将跳过包装为通过。
- 本次快照有 **9579 个未跟踪测试文件，其中2076个是 .gd/.tscn/.py/.json/.tres 源码/夹具**；9579项都保存了 check-ignore 来源。源码清单3886项。计数仅针对该快照，其他代理后续写入会改变数量，冻结时必须重扫。
- 进程检查当时没有命中的 Godot 引擎进程；`godot-ai.exe` 是已知 MCP 桥，单独列出而不误认引擎写入者。v2 的宽泛名字查询误报已用单元测试复现并在 v3 排除。没有执行杀进程。
- user:// 兼容路径解析为 **E:/Projects/Godot/FateDomination/test**，前置目录检查通过；这不证明未来各子进程没有自行覆盖 user-data-dir，动态回执仍要逐个给真实数据 namespace。

## 当前阻断（不可伪装完成）

1. 尚未收到恰好十份唯一、停止且经主代理审核的交接。无引擎进程不代表生产写入者已停止。
2. R8：仍有未跟踪/被忽略测试源码；主代理需明确版本化并完成干净克隆复现，工具不擅改用户忽略策略。
3. 本轮没有真实执行回执；所有逐套 ledger 是 NOT_RUN，exit/checks/错误计数为未知，不能填0或引用旧绿。
4. R1/R2/R3/R4/R7/R8 标号沿用独立安全审计反例分类，并不是声称当前修复仍有同样漏洞。任何之后的新修复都要以最终冻结版本重新运行。

## 新增反例清单与真实入口证据

| ID | 必须抓住的反例 | 要求证据（当前全部未运行） |
|---|---|---|
| R1 | 普通客户注入 gateway_inheritance/actor_key/profiles；查询后撤销再提交；过期revision/重复sequence | 真实网关正常继承与恶意拒绝、恢复文件原字节不变、认证房主及候选来源 |
| R2 | LAN/P2P规则仍在UI进程；dedicated在客机spawn；relay加载规则/转发流量；旧PID/instance就绪 | 三模式同机归属、UI/authority不同PID、room/PID/instance参数与ready/管理/恢复一致 |
| R3 | 已进入延迟通知队列的回滚事实下一帧仍发布；只撤子效果；外部续行丢/重 | 同帧record→pause→skip→下一帧、正常commit一次、父子全根资源/牌区身份/随机/事实/待答对比 |
| R4 | 内存skipped/规则日志冒充持久审计；审计写盘失败却继续 | begin/abort/commit/restore_failed独立链；store/flush/rename故障、重复skip、恢复失败、合成秘密检索 |
| R7 | 保存继承后票据发送失败却宣称成功；同昵称无用户名消歧；公开UI显示指纹/票据 | 故障后“已保存未送达”状态、幂等重发、全部列表真实窗口输入与原生复核、旧凭据撤权 |
| R8 | 只看diff漏掉ignored tests；当前机器有夹具但干净克隆没有 | Git源码纳入与产物/凭据排除、干净克隆独立复现，不只本机扫描 |

每个事实在 `gates.json` 中都有固定标识；导入证据须提供文件SHA与行/截图定位，静态scope自动拒绝。专用多RESULT、无checks和故意错误仍保留拒绝，不能自动归零。

## 跨平台 release / NAT / 中局恢复矩阵

| 环境 | 权威位置与发布 | 网络验证 | 存档恢复链 | 状态 |
|---|---|---|---|---|
| Windows LAN 房主+客机 | 当前冻结导出包；房主机器独立worker，UI不同PID | 真双端、可靠大清单/真实卡图与独立冷缓存 | save→crash→新instance/新日志→认证重连→data屏障→真实中局 | NOT_RUN |
| Windows P2P 本机/局域网 | 房主本机worker，不让信令加载规则 | 真WebRTC可靠通道，停信令双向对局继续 | 原真人不由AI接管；原钥/票据绑定 | NOT_RUN |
| Windows P2P 异地NAT | 两个网络的房主/客机发布包 | 记录选中ICE、无TURN游戏中继、信令游戏字节0、停信令继续 | 中局断线与重连后恢复实际局面，非仅大厅 | NOT_RUN |
| Windows dedicated + 异机房主 | worker在工作服务端；管理房主不迁计算位置 | 网关和各worker/客机独立完整日志与退出码 | 保留登记/配置/存档，wrong-key有效票据拒绝、旧档缺绑定失败关闭 | NOT_RUN |
| Linux dedicated + Windows客机 | 实际Linux/WSL新包与构建SHA，实际stdin与关闭/重启 | 实时端口地址、逐进程room/PID/instance；数据目录映射到指定E盘根 | 同一串行恢复链；不能Windows静态读文件冒充Linux执行 | NOT_RUN |
| Linux P2P房主 + Windows客机 | Linux房主同机worker，发布扩展真正加载 | 两机WebRTC及异地NAT，信令停机/抓包同上 | 实际保存/重启/原真人重连/恢复 | NOT_RUN |
| Windows/Linux signaling-only | 不读规则、不保存对局、不spawn规则worker | 仅信令/打洞，无游戏字节；不可用dedicated网关成功替代 | 无游戏恢复职责，不计为恢复通过 | NOT_RUN |
| 暂停/异常中局恢复 | 完整根回滚与进程崩溃恢复分别报告 | 权限拒绝不推进待答；未认证/错钥不占原席位 | 存档含真人绑定与必要状态；restoring全部原真人到齐再playing | NOT_RUN |

## 交付与下一执行者

- 工具：`tests/final_verification_v3/freeze.py`、`test_freeze.py`、`gates.json`、`README.zh-CN.md`。
- 报告、静态盘点、逐套NOT_RUN ledger、RED/GREEN日志、输出哈希：`scratch/final-freeze-v3/`。
- `inspect-final.json` SHA256：`559927bae1c8a35c533f03f5486521205953362c64b476c57232144c21258d5e`；同名sidecar可复核。每个新批次自动生成不可覆盖JSON、批次日志及两者SHA。
- 主代理先完成十路交接与R8策略，再按README生成新冻结；本快照是未批准的检查报告，不能直接作为Godot执行后的最终绿报告。严禁在共享工作树撤生产修复造RED；使用获批独立副本。
