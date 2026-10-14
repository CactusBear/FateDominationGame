# Round 32：共享令咒镜像契约复核

## 结论

- 两项争议不能一起归为漏洞：原测试向**同一 command_spells 数组**追加同 ID 卡，是有效负向；mirror 原来未去重，属于接收验证缺口。跨集合重复 ID 本身不非法，builder 的 held/手牌或技能区、residue/played、事件弃牌/来源分类都是同对象多投影。
- 原“删一张令咒的 zoom_kind 必须拒绝”断言过严。`_card` 原来已允许省略；`BaseObject` 与正式 board 的既定策略是缺声明/空串不给放大、不猜图片尺寸、路径或卡名。本轮改成合法接受并调用正式 UI 绑定验证禁用放大。
- 原 mirror 还在 identity/held 的完整声明检查强制要求 zoom，本轮仅取消该字段必填，提供时仍必须是 String。未新增字段、视图版本、业务规则或客户端资格判定。
- 新增跨投影同 ID 冲突检查，但不全局去重，也不要求公私投影字典完全相等；隐私边界没有放宽。

## 生产输出与显式网络版本

只读核对 `view_builder.gd`：可见卡面目前总输出 zoom_kind，值来自 `get_zoom_kind()`，没有声明时为空串；隐藏卡不输出该字段。identity 当前也输出声明。当前生产者字段齐全，不能据此将可选放大声明改成全部历史视图的强制字段。

builder 根视图显式 `v=1`，mirror 只接受整数 1。客户端 `client_match_inbox.accept_local_state` 仍组合 `accepts_pending` 与 `accept`，`NetworkBattleSource.read_view` 仍读取 session 镜像。没有新增协商或借用 recovery/result 的独立版本号；v=2 负向仍拒绝。

## 中文代码说明与耦合评估

改动使用 V4A；没有改 builder、query、source、board、presenter 或 session。mirror 仍只检验基础类型，不反查 NetIds 或规则对象，不重算资格。原有容器校验负责类型/隐私，新增一个纯投影一致性函数负责跨容器身份；没有复制第二套规则或 UI。

1. `_cards`：每次调用独立记录 seen ID，拒绝同数组重复；数组元素必须是有身份的卡面，不能用 `{}` 绕过检查。根 situation 单卡的空字典仍合法。
2. `_zone_entries`：同一包装容器也去重，并拒绝空 card；held 自带去重继续保留。
3. `_card_references_consistent`：在全部现有类型/隐私校验成功后，收集明确牌容器、包装中的 card、地图事件、局势及来源弃牌。对同 ID 比较共同已声明的 concealed/name/image/kind/cost/power/zoom_kind；缺字段不补猜。effects、description、back_image 与可见性可能经过公私过滤，不要求相等。检查失败不会替换已接受快照。
4. identity/held：仅 zoom_kind 从必填改为可选；其余原必填字段、公开身份状态、隐藏从者 placeholder 与卡面白名单不变。错误 zoom 类型仍拒绝，隐藏牌也不能借可选声明携带正面字段。
5. 共享测试：保证真实令咒夹具非空，避免 mutation 未执行；缺 zoom 改正向，错误类型保留负向。正式 board 脚本仅创建无树实例以调用绑定函数，验证 zoom_disabled=true 且无 zoom_img，不实例化场景或打开窗口。实际 builder 的 held/牌区同对象引用单独断言；command/special 同 ID 的派生投影夹具只检验镜像一致性，不宣称正常令咒获得特殊牌业务资格。
6. ENet 坏包在发送前改字段，再 var_to_bytes、真实收包、bytes_to_var、mirror；不是收包后修改冒充网络回归。新增专项进一步检查拒绝保留旧快照、容器去重、own/public 可见性差异、隐藏字段、数值/ID 类型、raw 和 pending。

## 真实 RED / GREEN

证据根：`E:/scratch/round32-mirror-ca9025e1de614a16858efe542e27068c`。

扩展断言但尚未修 mirror 的真实 RED：`isolated-dba0adb94d13474cb2202b687cc6d195`，scene exit 1，`RESULT checks=70`，12 条失败（包含拒绝后镜像状态配对断言）。定位为同容器重复、跨容器冲突以及全视图省略 zoom 被 identity/held 强制字段拒绝；已有 raw、隐私、错误类型负向正常通过。这不是对历史 28 项的重新执行计数。

最终四套采用相同源码文件 SHA-256 集合，程序验证 owned 文件与冻结 manifest 一致：

| 专项 | checks / failures | scene 时间 | 最终 run_id |
|---|---|---|---|
| shared_spell_view_contract | 87 / [] | 3.625s | 6f78e4fc4ed345dfb855cb38766192f8 |
| mirror_spell_negative | 73 / [] | 2.244s | 61988607d81c4d9194c592f09df0d4fd |
| match_view_privacy | 137 / [] | 2.019s | f1eed82550a44ed4ad1e62102c39018b |
| match_view | 223 / [] | 11.674s | b082304cae1e430a90c9fcd9b8493b20 |

各 probe/import/scene 实际 exit 0，runner exit 0，唯一 RESULT、空 failures、无 SCRIPT ERROR/ERROR/失败 CHECK。match_view 原专项的真实 AI 对局自然终局通过，覆盖公共观战与 0/1/2 观察席；不是只验证初始化。

shared 专项包含真实 LocalBattleSource/builder/query、稳定对象映射、spent 重查、ENet loopback 正常镜像与同对象引用、无 zoom 正式 UI 不放大；ENet 实际坏包覆盖冲突 ID、同容器重复、隐藏卡带正面、错误 zoom 类型、对手私牌。raw 对象在允许字段及未知字段的本地 primitive 门验证；默认序列化接收不含 raw，未宣称允许对象反序列化的远端攻击验收。

## 运行命令、隔离与收尾

使用现有 `tools/run_isolated_godot_test.py`，每进程 180s，全部 headless：

```bash
python -B tools/run_isolated_godot_test.py \
  --project E:/scratch/round32-mirror-ca9025e1de614a16858efe542e27068c/source \
  --scene res://tests/shared_spell_view_contract_test.tscn \
  --root E:/scratch/round32-mirror-ca9025e1de614a16858efe542e27068c \
  --godot E:/scratch/round32-mirror-ca9025e1de614a16858efe542e27068c/Godot.exe \
  --timeout 180 --max-bytes 6000000000 --min-free-bytes 1000000000 --freeze \
  --include scripts --include data --include assets \
  --include addons/godot_ai --include addons/godot-git-plugin --include icon.svg \
  --include tests/shared_spell_view_contract_test.gd --include tests/shared_spell_view_contract_test.tscn \
  --include tests/mirror_spell_negative_test.gd --include tests/mirror_spell_negative_test.tscn \
  --include tests/match_journal_test.gd \
  --include tests/match_view_test.gd --include tests/match_view_test.tscn \
  --include tests/match_view_privacy_test.gd --include tests/match_view_privacy_test.tscn
```

后三套只替换 --scene。没有整体复制 tests、旧 test 或缓存目录。Windows Job 管理自有进程，真实主/worker user:// 回执均在物理 E 树。

首次两次冻结导入因现有 editor VCS 自动启用报 `Cannot get class 'GitPlugin'`（第二次显式包含插件仍报错），尚未进入游戏。随后独占 source 副本仅将 `version_control/autoload_on_startup=true` 改 false；游戏/autoload/线程/数据配置原样，生产 project.godot 未改。没有降低 runner ERROR 门。

源码副本和引擎副本已回收，重跑需重建显式白名单 source 与同一编辑器配置差异，并重新复制 E 引擎。引擎 SHA-256：`ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。

收尾程序核对所有归档日志摘要、全部 Job ActiveProcesses=0、进程退出与日志句柄释放；精确查询自有引擎路径进程数 0，重验无 reparse point 后删除 source 456048056 bytes、引擎 180858888 bytes，所有 generated 子树不存在。仅保留最小证据，不清扫别人的进程、项目或存档。

证据索引：`final-runs.json`、`verified-summary.json`、`cleanup.json`；独占基线增量补丁 `round32-mirror.v4a` 与 `patch-validation.json`（按原基线逐 hunk 重建验证完全相等）。未提交、未推送；共享 tscn 无需改动。全程无窗口，未宣称原生窗口视觉验收或跨网真人验收。