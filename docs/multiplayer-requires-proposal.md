# requires 建议清单（待确认，尚未写入任何 JSON）

由脚本扫描 `data/` 下 69 个条目生成：11 个条目扫出引用，其余 58 个没有扫出跨条目引用。只列出扫描到的引用，不做推断。每一类引用写不写进 `requires`，需要你逐类确认。

## A. 牌库构成引用（强依赖：缺了牌库就少牌）

从者 `specials.ATTACKS` 中的 `属性:威力` 和 `special:名字`，由 `LoadAttack.resolve` 解析为具体攻击牌。解析规则：先找基础牌，再找职阶牌。

| 条目 | 解析到的攻击牌 |
|---|---|
| `servants/artoria_pendragon` | `physical_attack_0_2`（strength:2）、`physical_attack_0_3`（strength:3）、`physical_attack_0_4`（strength:4）、`physical_attack_1_5`（strength:5）、`precision_strike_0_3`（agility:3）、`magic_blast_0_2`（magic:2）、`magic_blast_0_3`（magic:3）、`surveil`（special:surveil）、`luck`（special:luck） |
| `servants/emiya` | `physical_attack_0_2`（strength:2）、`physical_attack_0_3`（strength:3）、`precision_strike_0_2`（agility:2）、`precision_strike_0_3`（agility:3）、`precision_strike_0_4`（agility:4）、`magic_blast_0_2`（magic:2）、`magic_blast_0_3`（magic:3）、`magic_blast_0_4`（magic:4）、`surveil`（special:surveil）、`preparation`（special:preparation） |
| `servants/cu_chulainn` | `physical_attack_0_2`（strength:2）、`physical_attack_0_3`（strength:3）、`precision_strike_0_2`（agility:2）、`precision_strike_0_4`（agility:4）、`precision_strike_1_5`（agility:5）、`magic_blast_0_2`（magic:2）、`magic_blast_0_4`（magic:4）、`magic_blast_1_5`（magic:5）、`surveil`（special:surveil） |
| `servants/medusa` | `physical_attack_0_2`（strength:2）、`physical_attack_0_3`（strength:3）、`physical_attack_1_5`（strength:5）、`precision_strike_0_2`（agility:2）、`precision_strike_0_3`（agility:3）、`precision_strike_0_4`（agility:4）、`precision_strike_1_5`（agility:5）、`magic_blast_0_3`（magic:3）、`surveil`（special:surveil）、`preparation`（special:preparation） |
| `servants/medea` | `precision_strike_0_2`（agility:2）、`precision_strike_0_3`（agility:3）、`precision_strike_0_4`（agility:4）、`magic_blast_0_2`（magic:2）、`magic_blast_0_3`（magic:3）、`magic_blast_0_4`（magic:4）、`magic_blast_1_5`（magic:5）、`surveil`（special:surveil）、`luck`（special:luck）、`preparation`（special:preparation） |
| `servants/sasaki_kojirou` | `physical_attack_0_2`（strength:2）、`physical_attack_0_3`（strength:3）、`physical_attack_0_4`（strength:4）、`precision_strike_0_2`（agility:2）、`precision_strike_0_3`（agility:3）、`precision_strike_0_4`（agility:4）、`precision_strike_1_5`（agility:5）、`surveil`（special:surveil）、`luck`（special:luck） |
| `servants/heracles` | `physical_attack_0_2`（strength:2）、`physical_attack_0_3`（strength:3）、`physical_attack_1_5`（strength:5）、`berserker_class_strength_3_7`（strength:7）、`berserker_class_strength_5_9`（strength:9）、`precision_strike_0_2`（agility:2）、`precision_strike_0_4`（agility:4）、`berserker_class_agility_3_7`（agility:7）、`luck`（special:luck） |
| `servants/angra_mainyu` | `physical_attack_0_2`（strength:2）、`physical_attack_0_3`（strength:3）、`precision_strike_0_2`（agility:2）、`precision_strike_0_3`（agility:3）、`precision_strike_0_4`（agility:4）、`magic_blast_0_2`（magic:2）、`magic_blast_0_3`（magic:3） |

**注意**：`属性:威力` 是一个查询，不是固定的名字。如果客机数据里加入了另一张同属性、同威力的基础攻击牌，解析结果可能就变了。例如 `heracles` 的 `strength:7` 现在解析到职阶牌 `berserker_class_strength_3_7`，一旦有人加入一张 7 威力的基础力量牌，就会改为解析到那张牌。所以方案在 5.3 节新增一条规则：**合成数据里如果有两张以上的攻击牌能匹配同一个 `属性:威力`，就按冲突处理，由房主选定**。

写入方式有两种：
1. 写解析后的模板名，如 `{"category":"attacks","name":"physical_attack_0_2"}`。这种写法直观，但会把「查询」固化成「固定名字」。
2. 写查询本身，如 `{"category":"attacks","query":"strength:2"}`，由验证器按 `LoadAttack.resolve` 的同一套规则解析，解析不到就报缺失。
我建议用第 2 种：它与牌库的实际语义一致，也不会因为改了名字而失效。

## B. 效果中按名字查询其他条目（是否算依赖待定）

| 条目 | 引用对象 | 位置 | 原文 |
|---|---|---|---|
| `masters/matou_shinji` | `masters/matou_sakura` | `/specials/BUFFS[0]/effects[1]/funcs[6]` | `get_objects_by_name_fr_arr` |
| `masters/matou_sakura` | `masters/matou_shinji` | `/effects[0]/funcs[17]` | `if_func` |
| `masters/illyasviel_von_einzbern` | `situations/heavens_feel` | `/upgrade_skill[0]/effects[2]/funcs[1]` | `get_objects_by_name_fr_arr` |
| `servants/angra_mainyu` | `attacks/avenger_class` | `/specials/SKILLS[2]/effects[0]/options[0]/funcs[0]/parameters[1][13]` | `get_cards_by_name_fr_arr` |

这几处都是运行时查询，例如 `get_objects_by_name_fr_arr` 和 `if_func`，含义是「场上有没有这个对象」。对象不存在时查询结果为空，效果会走「没有」的分支，不会报错。具体情况：
- `matou_shinji` 和 `matou_sakura` 互相查询对方是否在场，形成一个依赖环。
- `illyasviel_von_einzbern` 查询局势 `heavens_feel`。
- `angra_mainyu` 在 `verg_avesta` 中按名字查询自己牌库里的 `avenger_class`，这张牌已经在 A 类里了。

建议：B 类**不写进 `requires`**，因为缺了它们效果仍然正确，只是条件不满足。可以另设一个可选字段 `mentions`，仅用于在勾选时提示「此条目会查询某某」，不阻止开局。这是否需要，由你决定。

## C. 卡背

- 通用卡背来自 `data/card_backs`，按 `LoadHelper.CARD_BACK_FILES` 的固定映射取用，几乎所有条目都隐式依赖它们。建议不写进 `requires`，而是**永远采用主机的通用卡背**，作为房间的基础集合。如果客机提供了同名卡背，仍按 5.3 节由房主选择。
- `tohsaka_rin` 的特殊卡背 `00002_tohsaka_rin_jewels_back.png` 放在条目自己的目录里，会随条目一起移动，不需要声明。

## D. 没有扫出引用的类别

事件（16）、局势（13）、令咒（1）和其余御主都没有扫出跨条目引用。令咒通过 `specials.COMMAND_SPELLS` 声明，本次扫描没有发现任何条目声明这个字段，所以都回退到通用令咒 `normal_command_spell`。建议把它和通用卡背一样，归入「主机基础集合」。

## 扫描方法

- 读取每个条目 JSON 中所有的字符串值，从以下两类里匹配：一是牌库构成串（`属性:威力`、`special:名字`），按 `LoadAttack.resolve` 的规则解析；二是与其他条目模板名完全相同的字符串（排除 `*_name` 字段本身）。
- 不覆盖的情况：在运行时拼接出来的名字，或者从变量里取出的名字。这类引用扫不到，只能靠加载验证和对局前模拟（方案第 10.5 节）来发现。
