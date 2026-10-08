# 公共视图隐私 v3 静态交接

## 修改范围
仅改 `scripts/match/view_builder.gd`、`scripts/match/view_mirror.gd`、`scripts/net/server_gateway.gd` 的公共消息/视图过滤边界；未改身份继承核心、UI、worker、effect，未启动 Godot，未 commit。

- 网关按消息类型显式重建信封、业务 args 字段。join 不接受客户端 gateway_identity；gateway_inheritance 仅在清洗后由现有认证连接重建。分片与 blob 保留各自的显式信封字段。嵌套业务 payload 仍由原业务入口验证，不解释为认证上下文。
- 任意出牌/弃牌/技能区共用 card_view；沿原对象来源查从者公开状态，不以“已出牌/已弃牌/明置”替代真名公开。未知从者来源、无声明来源技能失败关闭。御主来源技能不受从者真名限制。
- 隐藏公共牌 back_image 为空，不发送来源专属路径。非本人牌不发送效果 ID；公共说明只读取显式卡面字段与声明的展示文案，不回退内部效果名。本人保留原完整说明、效果 ID、卡背。
- 公共日志从白名单事实重建，不复制对象、任意 data、效果或选项参数；数值、已声明支付用途、胜者 ID 保留。
- 镜像拒绝非本人未公开从者身份/技能列表、隐藏牌夹带字段或专属卡背、暗置但公开牌面、公共效果 ID。本人卡牌路径使用独立 private_view 参数保留合法私有信息。
- 固定发送审计仍仅含连接、通道、阶段、错误码、入队状态；本交接无真实 token/key。

## 实测静态结果
执行：`uv run --with gdtoolkit python scratch/public-view-privacy-v3/static_check.py`
- 3 份生产脚本 + 1 份反例夹具，gdtoolkit 语法解析成功。
- 14/14 源码结构契约检查通过。
- 3/3 静态删守卫负控制通过。它只证明源码检查能发现守卫删除，不是业务行为运行测试。
- `git diff --check -- scripts/match/view_builder.gd scripts/match/view_mirror.gd scripts/net/server_gateway.gd` 退出码 0。

## 产物
- `negative_cases.gd`：真实 GDScript helper 反例；覆盖伪造上下文、隐藏牌字段/卡背、公共效果 ID、本人合法私有数据；run_snapshot 接受真实权威公共快照后夹带未公开从者。
- `static_check.py`、`static_results.json`：可复跑静态契约与结果。
- `worktree.diff`：三个独占文件当前相对 git 基线的完整 diff，**包含本轮之前已存在的未提交改动**，不得视为全部由本子代理产生。

## 缺口与后续验收
指定 `public-view-privacy-audit` 在仓库与 C:/Users/Administrator 范围检索未找到，不能声称已阅读该审计；hermesWarning.txt 已阅读。
没有执行 Godot，故未证明 Godot 类型检查、真实局面生成、网络往返和 UI 接线。反例夹具也未执行。主代理需在所有写入者退出后串行跑受影响 Godot 专项：未解放从者技能明置/出牌/弃牌仍不公开，解放后公开；御主来源技能仍可公开；本人完整信息可用；无来源技能失败关闭；公共快照 mirror.accept 可接受；继承/加入/目录分片/blob 请求不回退。
规则暂停诊断的传输授权在独占范围外 `lobby_session.gd`；只读确认当前 `_match_actions` 仅对 room.owner 添加 guard_diagnostic，保留主机权威完整诊断。没有改这条接线，也未将该只读确认称为运行验收。
