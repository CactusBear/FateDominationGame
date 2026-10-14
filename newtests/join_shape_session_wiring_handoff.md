# join 两字段 shape 接线交付

生产唯一改动：`scripts/net/session/lobby_session.gd:1108`，旧 inline `name is String && spectator is bool` 改为 `_host_identity_request_codec.validate(message.kind,args).ok`。合法分派 `_join_identity(connection,args)` 原样；非法 shape 不使用 codec reason，仍落到原末尾 `请求无效`。精确字节比较证明除此一行外全部 Session 不变，包括密码/ack/继承、认证/seq、成员绑定、owner 初始化、room_files、match_bind/selection 发布及末尾错误处理。

Session 修改前 SHA256：`dfa448a286ca698b3f88b70baac5567aaa3f7bd1f581f4c1c414ff328d598886`

Session 修改后 SHA256：`f79786169f0b655196dcf775bd6cf1790a4de53692fec5a24986657620f20019`

codec 未写入，读取 SHA256：`3cf4c8ee29f22b310265ccd8bbf1d81bc1e612b7a9f767f02318a84513113116`

命令（仓库根目录）：

```text
python -B newtests/join_shape_session_wiring_runner.py red
python -B newtests/join_shape_session_wiring_runner.py green E:/scratch/pw-27b3ce34
```

- E 盘引擎/旧 DLL/工程及 user 目录冻结；先真实 `--headless --editor --path <freeze> --import --quit` 导入：PID 38420、exit 0、ERROR 0、Job 活跃 0。
- 原 inline RED：PID 14676、42 CHECK、exit 1、ERROR 0、Job 活跃 0；codec 调用断言真实失败；runner exit 0（成功验证预期 RED）。
- 接线 GREEN：PID 38916、42 CHECK 全部 true、唯一 RESULT checks=42/failures=[]、Godot exit 0、runner exit 0、ERROR 0、Job 活跃 0、日志句柄已释放、精确仅一行改动 true、源码与冻结 SHA256 完全相同。
- 公开客户端 request → fixture 传输 → 真实 Session `_receive` → 真实 codec → 真实 `_join_identity`/Room：合法创建绑定、额外字段不变、认证昵称及 dedicated owner 初始化；错字段类型/缺字段拒绝不建 member；旧 seq 在 codec 前拒绝；认证/协议前置不进入 codec；合法 shape 携带错误 resume 仍保留具体身份错误。
- codec 观察夹具只把非法结果 reason 替为哨兵，GREEN 仍收到原 `请求无效`，证明未新增 codec wire reason。传输仅记录 kind/seq/reason，不记录或打印 token/password。
- 最初夹具遗漏 Room 的 ai_count/capacity，触发 SCRIPT ERROR；已修夹具并重新导入/运行上述有效 RED→GREEN。首轮不算验收。
- 发布方法仅作边界计数；不声称真实 Room 文件/选择/对局发布整链经过运行验收，这些由 exact-one-line 字节证据保证本轮未改。
- 未运行全量/57 modulecheck/测速/GUI/RSA多机/长局；未监听端口，未接 choose/content。

证据归档：`newtests/join_shape_session_wiring_evidence/`（导入与 RED/GREEN stdout/stderr/JSON、session-before.gd、session-local.diff、冻结清单）。归档逐文件 SHA256 读回一致；两次自有 E 盘生成根已回收，读回不存在，见 `cleanup.json`。最初失败夹具证据保存在 `fixture-first-attempt/`。

本轮写入范围：Session 仅上述一行；新增 `newtests/join_shape_session_wiring_{test.gd,test.tscn,runner.py,handoff.md}` 及证据归档。Session 写入所有权已释放，后续独立接线可接管；本代理不会再写 Session。
