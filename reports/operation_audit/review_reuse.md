# 新增候选的最终复核记录

复核子任务因 API 超时退出，未产出完成报告。本文件由主代理依据已读取的源码及分批报告补齐；没有将失败子任务记为通过，也没有运行实现测试。最终交付以 ../FD3.9卡牌operation增补分析.md 为准。

## 删除或降级为已有组合

| 分批候选 | 复核取舍 | 源码依据 |
|---|---|---|
| transfer_card_at_position、置顶、置底、前N随机插入 | 删除独立新增建议。已支持 to_index；卡面第X张转为下标由调用方处理。 | DrawCardByCard.gd:7；DrawCardByIndex.gd:6；AddToArray.gd:5 |
| sum_property、count_distinct_values、get_array_slice | 不因循环只返回末次结果就新增。先建外部累加BaseNumber或结果数组，循环读值并就地加/追加；去重先is_in_array。 | ForeachFunc.gd:7；ForFunc.gd:8；EditNumAndReturn.gd:4；IsInArray.gd:5 |
| 普通骰子、每种标记单独原语 | 删除；随机整数、Buff、BaseNumber、具名数组组合。 | RandomInt.gd；CreateBuff.gd:4；ManageBuff.gd:4；SetPlayerData.gd:4 |
| round_number 必须新增 | 降级。EditNumAndReturn 已有乘法取整分支；先按卡面实际数域验证组合。对负数、浮点边界不能宣称现有分支全部正确。 | EditNumAndReturn.gd:4—18；CalculateNumber.gd:7 |
| is_prime 必须新增 | 不保留为必需原语。可先验证用计数器、余数、循环、比较实现；不写死质数表。 | CalculateNumber.gd 的 mod；ForFunc/WhileFunc；CompareNumber |
| copy_skill_with_overrides、普通换角色 | 降级为宏组合。复制、字段修改、入技能区、登记已有；多角色槽另论。 | CloneObject、AddSkillToSkillZone；RegisterObjectEffects.gd:5；UnregisterObjectEffects.gd:5；DealPlayerCards.gd:7 |
| create temporary card | 删除重复创建接口建议，CreateCard/BuildCard 已存在。 | CreateCard.gd:9；BuildCard.gd:11 |
| gain/spend/restore_command_spell 一律新增 | 不采纳一律新增。普通计数与实例移区复用；支付替代、类型、控制者、费用来源属于资源模型。 | GetPlayerCommandSpell.gd:4；EditDataNumber；CreateCard |
| card_matches_rule_traits | 普通现有字段比较用getter与布尔组合。印刷/运行态、多身份、单次判定伪装另归模型缺口。 | GetProperty.gd:6；HasAttribute；GetAttackPrintedPower；CardHasEffect |
| 所有游戏获胜都未实现 | 纠正。已有 victory_override 并支持多胜者；缺的是任意时点立即结束/淘汰替代/复活接线。 | global/victory_resolver.gd:14—25；global/game_progress.gd:143、222—225 |
| 项目完全没有选项交互 | 纠正。已有效果options、选牌/选玩家/选位置与多人可选队列；复杂秘密、关联、排序等单独列缺口。 | QueueOptionalEffectForPlayers.gd:11；EffectManager现有选择流程 |

## 保留或改为框架缺口

- 全局牌库/弃牌区访问：保留只读入口候选。GetGameDataValue 取 GameData，不是 MapData；现有 GetEvents/GetSituations 只覆盖场上集合，不等于全局牌库均可取得。
- 安全切面：保留同一实体定义切换候选。SetCardConcealed 只负责明暗置。
- 效果挂卸与指定能力调用：保留候选，但实施前再验证能否由现有效果克隆、绑定、登记组合完整表达；不能只为缩短JSON新增包装。
- 控制权：改为 owner/controller 模型先行的条件候选。普通移区不必新加转移原语。
- 位置交换：仅规则要求同时发生且中间态有语义时保留原子交换候选；一般成组移动仍用循环。
- 附件、专属牌堆、秘密可见性、地图拓扑、多实体、NPC、来源修正、支付替代、反应链、回合重跑：归框架，不能以一个万能 manage_* 伪装完成。
- 普通状态机/任务/连续次数：计数和转移优先数据组合；缺少的历史字段与UI单列，删除笼统 TrackObjective 必须新增结论。

## 不能依赖分批草稿直接实施的其他问题

- batch_1 在标记段引用 #599/#600，超出其自身范围；该机制在后续批次实际纳入，不当作本批新增覆盖。
- 部分分批说明把牌堆顶底能力误列为缺失；最终报告已纠正。
- 部分 non_rule 判断来自文件名与OCR而非原图。总OCR风险索引收集全部明确空白，不因此排除。
- MoveLocation.gd 注释容易误导：实际第54行调用 SetLocation，会改变位置，不能把它用作无副作用的预检。

所有结论为静态分析。实现时必须以真实 Godot JSON 效果链测试确认变量上下文、选择暂停、归属迁移与事件顺序；本轮未修改游戏源码。
