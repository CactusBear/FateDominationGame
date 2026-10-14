# Round70：所有牌保留自身声明卡背

## 最终合同与影响范围

最新用户追加“其他牌也是，用自己的牌背就行”覆盖旧的两类限制。本轮所有 `card_view` 支持的模型都直接保留已解析 `_card_back_img`；未声明保持空，不新增 kind、规则数字、中性资源或牌背政策字段，不按类名、图片尺寸、路径内容猜背面。已有可见牌的 kind 字段未新增或扩展。

生产改动仅两处：

1. `scripts/match/view_builder.gd:343` 的 `card_view` 无条件复制模型卡背。原 `visible = own or (...)`、未解放来源判断和 `_is_awakened == false` 强制不可见均不改；正面字段仍只有 visible 才构造。
2. `scripts/match/view_mirror.gd:330` 的 `_card` 撤销隐藏非空卡背禁令，仍严格验证 String。隐藏牌仍禁止 name/image/kind/cost/power/effects/description/zoom_kind，公开私有效果禁令、重复 ID、raw 对象、字段白名单与原子接受逻辑不变。

接收协议不根据图片地址内容判断“这是不是某牌种/角色自己的背面”；真实权威 producer 负责发送模型自身背面。没有扩大正面信息公开。跨容器同一规则对象由 producer 生成同 ID、同背面投影，专项实际验证；不借本轮新增接收端图片分类器。

## 已读模型及 loader 的真实语义

- `BaseCard._card_back_img` 是 String，默认空；`copy_clone_fields` 原样复制。视图层不重新调用 resolve_card_back。
- `BaseAttack` / `BaseSkill` 继承 BaseHandCard → BaseCard。`BaseSkill._is_awakened` 默认 true，但 loader 依据显式 type_name 和 JSON is_awakened 初始化升华技；未觉醒升华技连 own 也不获正面。
- `LoadAttack._create_attack` 解析攻击池的已声明/默认背面；`LoadGame.load_attacks` 则按已有放入牌库的数据流声明选择既有背面，御主附属攻击牌可能合法使用 skill 背面。本轮不更改该语义。
- `LoadGame.load_skills` 按传入的 skill/upgrade_skill 声明解析；`load_other_master_things` 支持专属 card_back_img。
- `LoadCommandSpell.build_command_spell` 用 BaseCard；`LoadEvent.build_event` 用 BaseEvent；`LoadSituation.build_situation` 根据已有 is_climax 声明选已有普通/高潮背面。测试直接取这些 loader 已加载模型，不以路径或牌名猜类别。
- 从者技能在未解放来源时即使非暗置也不可见；隐去正面不再意味着清空已获授权的卡背。御主/从者 identity 与未解放 servant placeholder 是独立协议，不在本轮扩大其字段。

## 修改/新增文件

- 修改：`scripts/match/view_builder.gd`、`scripts/match/view_mirror.gd`。
- 修改：`tests/match_view_privacy_test.gd`：背面与原声明相等；秘密标记检查只排除已获许可的 back_image，所有原未授权面字段仍检查。
- 修改：`tests/mirror_spell_negative_test.gd`：旧令咒“非空专属背必拒”被用户撤销，替换为坏 back 类型及隐藏面字段负向；保留其余冲突、重复、raw、有限数及 pending 安全断言。
- 新增：`tests/round70_declared_card_backs_test.gd/.tscn`。
- 新增：`tools/tests/round70_declared_card_backs.py` 与本文。

未修改 board、presenter、GUI 测试、loader、数据或资源；未提交。仓库原来已有大量脏改，两份生产文件与本轮 RED 归档逐字 diff 仅包含下文两处，不把其原有全量 git diff 归因于本轮。

注意：`.gitignore:47` 忽略整个 `/tests/`，因此四个改/新增测试文件不会出现在普通 git status 中；文件及精确指纹都已实际存在并执行验证。本轮不改 ignore、不暂存、不提交。

## RED → GREEN 证据

### 有效 producer RED

命令：

```bash
python tools/tests/round70_declared_card_backs.py --label producer-red --scenes round70_declared_card_backs_test match_view_privacy_test
```

归档：`E:/scratch/round70-card-backs-producer-red/isolated-c414d9d8e139402fbd01978feccb6c7b/manifest.json`。

新专项 checks=216，15 个失败全部为各实际模型声明卡背未保留；privacy checks=137，8 个失败全部为同类背面断言；两套 exit=1，无解析/引擎错误。首次 runner 漏记 generated 所有权字段导致安全清理拒绝；已补精确字段，使用原保守清理器消费该 UUID 生成树，原 RED 日志未改。

### producer 已绿、旧 mirror 独立拒绝

归档：`E:/scratch/round70-card-backs-mirror-red/isolated-bea5dfb1605349918dfc4bb76b137a2c/manifest.json`。

仅改 producer 后 privacy 137 项全绿；所有声明背面夹具通过，但 mirror 的合法基线被旧非空禁令拒绝。该次 ENet 后续测试另暴露无实际等待的 fixed-fps 轮询超时及级联错包，原件保留，不把这部分称为纯 mirror RED。后续夹具在有界轮询中给出 OS 调度时间，并在有效基线失败时立即停止。

### 最终同一冻结 GREEN

```bash
python tools/tests/round70_declared_card_backs.py --label final-v2-green
```

最终命令 exit=0。权威证据：

`E:/scratch/round70-card-backs-final-v2-green/isolated-aa8843e09164442d92573129aa8cb79d/manifest.json`

| 场景 | checks | exit | failures |
| --- | ---: | ---: | --- |
| round70_declared_card_backs_test | 320 | 0 | [] |
| match_view_privacy_test | 137 | 0 | [] |
| mirror_spell_negative_test | 94 | 0 | [] |
| match_view_test | 224 | 0 | [] |
| view_builder_non_card_objects_test | 11 | 0 | [] |

Python 聚合共 786 项检查。match_view 含真实 AI 自然终局，其循环检查数随对局不同；不与先前冻结的 785/790 项结果相加或混用。

- 新专项实际覆盖攻击、技能、升华技、令咒、事件、普通局势、高潮局势和其他 BaseCard 的现有声明资源。实际 own/public 卡面与原模型一致，隐藏面各字段均缺失，未觉醒 own 保持隐藏。
- 两端使用正式 MatchEnetTransport，在 OS 分配的回环端口建立真实 ENet；合法快照发送、序列化、接收后逐值比对，再原样交 mirror。不是接收后补造牌背。
- 8 个隐藏面字段负向使用本身类型合法的值；6 种非 String 卡背负向单独发送。全部发送前构造，接收后不改；每次拒绝均验证上一份完整镜像不变。
- producer 同对象跨 played/discard 的 ID 和背面完全等价。缺声明对象即使正面路径像牌背也保持空。另验证合法 opaque 字符串不被接收者按内容分类；这个样例的两份同 ID 投影同时修改，未顺带制造背面冲突。
- 仅 headless。1642 个白名单依赖由 autoload、声明脚本类、显式 load/preload/extends 递归收集；动态 operations、正式 addons/DLL、数据目录显式保留。未纳入 battle_board、v2_view_presenter 或 GUI 测试。
- 保留原 Godot 引擎、正式 DLL、15 秒配置预算和 20 线程池；每个自有 Job 看门狗为 180 秒。主/worker 物理 E 探针成功，所有 Job ActiveProcesses=0，未接触用户 PID 28100。
- 源码冻结 drift={}，自有源码 drift={}，错误/警告门通过，证据 SHA256 读回通过，最终 generated_removed。实际日志在该 manifest 同级 `evidence/`。

中间还保留两类隔离失败：宽冻结复制时有非本任务脚本变化，拒绝了 copy drift；收窄后首次缺 PNG `.import` 伴随文件，引起 cold-import autoload 无 resource loader。最终依赖收集保留 `.import/.uid`，未放宽 ERROR 门。两类失败都不是业务 RED，原证据分别位于 all-green 与 minimal-green 根。

## 精确生产/测试指纹与窗口交接

| 文件 | SHA256 |
| --- | --- |
| scripts/match/view_builder.gd | `9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e` |
| scripts/match/view_mirror.gd | `8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20` |
| tests/match_view_privacy_test.gd | `291b62fdd3d311da0849634c287c1780dfddf5580fce3be296e3724f0d3e4766` |
| tests/mirror_spell_negative_test.gd | `1fdac36d68d00c6a914f90faf62adeb4f6943239185dc32c8709247616e54379` |
| tests/round70_declared_card_backs_test.gd | `dffa7a4c70371f9489e690f276fbfc08d739bdee4f8ddc85bfa95a8aaa8fc78e` |
| tools/tests/round70_declared_card_backs.py | `37ee9e1c09b4ea7c0995b68e74925120f3abd37d36703647b2ffc14aa096b6b3` |

以下样例均来自最终运行的 DECLARED_BACK_SAMPLES，资源存在断言已通过，main 可直接交唯一 GUI owner 用新冻结验证，不要沿用旧中性/空背冻结：

| 实际模型内部名 | 已声明 back_image | 窗口价值 |
| --- | --- | --- |
| yin_qi_bullet（攻击对象） | res://data/card_backs/skill_card_back.png | 证明不能按 BaseAttack 重算攻击背面 |
| snake（攻击对象） | res://data/card_backs/attack_card_back.png | 另一真实攻击对象的不同声明背面 |
| kanshou_and_bakuya / mana_resistance | res://data/card_backs/skill_card_back.png | 不同技能正面均保留原背并隐藏正面 |
| caliburn / jewel_sword_zelretch | res://data/card_backs/upgrade_skill_card_back.png | 未觉醒 own 也不能见正面 |
| normal_command_spell | res://data/card_backs/command_spell_card_back.png | 原旧令咒背面禁令已撤销 |
| contain_third_party / cooperation | res://data/card_backs/event_card_back.png | 事件暗置背面 |
| battle_of_shinto / calm_before_storm | res://data/card_backs/situation_card_back.png | 普通局势背面 |
| gate_of_hell / heavens_feel | res://data/card_backs/climax_situation_card_back.png | 高潮局势背面 |
| jewel_card | res://data/masters/00002_tohsaka_rin/00002_tohsaka_rin_jewels_back.png | 真实专属资源，证明不替换为中性/通用牌背 |

新专项对 loader 对象调用既有 CloneObject、设 `_is_concealed=true`，放入对手 played/discard 后由 builder.build(0) 构造完整包。窗口夹具可复用同样的生产入口，不要在 guest 收包后伪改。完整正面路径也保存在 manifest.samples。

**未验收边界：**本任务不运行或修改 GUI；正式 board 的实际绘图、hover/zoom、modal 保持目标及窗口视觉由唯一 GUI owner 接手。无跨机器网络或发行 EXE 验收声明。

## 本轮最小生产 V4A

```diff
*** Begin Patch
*** Update File: scripts/match/view_builder.gd
@@
-	# 隐藏牌不携带专属卡背路径（其中可能包含从者名/职阶/来源目录）。
-	var result := {"id": ids.id_for(card), "concealed": concealed, "visible": visible, "back_image": str(card._card_back_img) if visible or own else ""}
+	# 所有牌均保留模型已声明的自身卡背；缺声明保持空，不按类型或图片路径猜测。
+	var result := {"id": ids.id_for(card), "concealed": concealed, "visible": visible, "back_image": str(card._card_back_img)}
*** Update File: scripts/match/view_mirror.gd
@@
 	if not value.visible:
-		if not private_view and value.get("back_image", "") != "":
-			return false
+		# 所有隐藏牌允许自身声明的卡背字符串；协议不按图片地址推断身份。
+		# back_image 的 String 类型已在上方校验，未授权正面字段仍全部拒绝。
 		for field in ["name", "image", "kind", "cost", "power", "effects", "zoom_kind", "description"]:
*** End Patch
```