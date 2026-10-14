# round30-spell-view.md

## 结论

现有生产契约足够承载共享 UI 令咒/抽屉资源；本轮没有新增字段，也没有修改只读的 board/presenter/session/adapters。

验证入口：`tests/shared_spell_view_contract_test.tscn`。

## UI 可用字段（精确口径）

### `player`

- `id`, `controller`, `player_name`, `own`
- `command_spell_count`：本方令咒余额；不是特殊令咒卡的独立次数
- `command_spells`：仅本方实际持有的完整卡面数组
- `special_command_spells`：公开的特殊令咒种类；不携带本方私有效果身份
- `master`, `servant`, `servant_present`, `servant_released`, `servant_class`
- `hand_cards`, `discard`, `played_cards`, `held_cards`, `zone_hand_entries`, `buffs`

### 可见 `card_view`

- `id`：当前 builder/session 的稳定对象 ID
- `concealed`, `visible`, `back_image`
- `name`, `image`, `kind`, `cost`, `power`, `effects`
- `zoom_kind`：显式声明，不能按尺寸、图片路径或卡名推断
- `description`

隐藏卡仅保留 `id`, `concealed`, `visible`, `back_image`；公开对手不接收本方私有牌面、效果 ID 或专属卡背。

### `actions`

- `deploy_areas`, `move_areas`, `move_costs`
- `cards`, `effects`, `flip_cards`, `can_end`
- `effects` 的 `id`/`label` 来自现有 authority/action query；可用性由查询结果决定，不在 UI 重算。

### `card_choice`

- `cards`, `required`, `card_views`, `min`, `max`, `allow_cancel`
- `verb`, `secret`, `confirm_text`

## 身份、恢复与网络边界

- 本方使用完整牌面；公开对手按身份释放状态过滤；隐藏身份只给通用 servant placeholder。
- `NetIds.object_for(id)` 只在同一当前会话映射对象；恢复后必须重新建立 builder/query，不跨会话猜 ID。
- `LocalBattleSource` 只缓存 view；`actions`/`pending` 每次回到共享规则查询。
- `NetworkBattleSource` 只消费 session 基础类型镜像，不接收本地 raw 对象。
- ENet 测试只传 `var_to_bytes(view)`，接收端通过 `MatchViewMirror` 验证。

## round30 验收矩阵

`shared_spell_view_contract_test` 覆盖：

1. 真实单机 builder/source/query 链；
2. 本方/公开对手/隐藏身份隐私；
3. spent 后重新查询 actions，不使用旧可用性；
4. 稳定 ID 与对象恢复再投影；
5. 显式 `zoom_kind`；
6. 真实 ENet loopback 序列化与 mirror 接收；
7. 六类负向：raw object、对手私牌泄露、重复 ID、隐藏牌带正面字段、缺 zoom、观察者错配。

规则资格仍由 `EffectManager`、`RegularPlay` 与现有 authority/query 生成；本测试不创建第二套资格判定。
