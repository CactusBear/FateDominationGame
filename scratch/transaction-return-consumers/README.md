# 事务审计返回值消费者交接

## 本轮生产文件
- `scripts/net/match_authority.gd`：submit 前后审计门禁；命令/录制结果消费；录制失败返回 false 并废弃旧视图；恢复、开局、重开最终写入确认；续行失败失效旧视图。
- `scripts/system/global/effect_manager.gd`：start/child 返回 bool 及全部调用者检查；pause、尾部登记/消费失败关闭；费用支付和提交接口完成后检查审计；skip/resume 最终 flush。

既有未提交修改原样保留；没有改 journal、replay、checkpoint、gateway、UI，也没有凭证操作或 git commit。

## 重要契约
`defer_until_runtime_guard_complete()` 的 true 表示尾部已由暂停机制接管，而非审计写入成功。调用方在 false 时会同步执行尾部。因此登记写失败仍保留尾部并返回 true，设置 audit_write_failed；consume_tail 在故障下不能执行，网络成功回执返回 false。不要把该布尔值改为普通成功回执而不一起改调用方。

规则恢复成功后，旧展示事实 generation 仍在 rollback 完成审计之前 abort。完成审计失败不能复活旧事实；commit append 失败不放行 pending generation。没有改变 intent → restore → abort generation → rollback receipt 的既有规则恢复顺序。

## 新专项源码
- `transaction_return_consumers_test.gd`
- `transaction_return_consumers_test.tscn`

使用真实生产消费者，只在写入器/录制器/检查点边界注入故障。覆盖 start、child、tail_registered、两条 commit 路径、resume、rollback_intent、rollback、提交后 flush、录制返回 true 但提交失败。

主代理在所有写入者退出后串行运行（本代理禁止运行 Godot，未执行）：

```bash
"$GODOT" --headless --fixed-fps 60 --path . --scene res://scratch/transaction-return-consumers/transaction_return_consumers_test.tscn
```

## 已执行的验证
- gdtoolkit parser：两个生产 .gd 与专项 .gd 均解析通过。
- `git diff --check`：授权生产文件通过。
- 静态调用扫描：EffectManager audit/audit_event/consume_tail 没有裸调用。
- 静态顺序断言：rollback generation abort 先于完成回执。

静态解析不是 Godot 编译或运行验收。专项源码的断言尚未执行；恢复档案/真实网络联调需要主代理串行验证。
