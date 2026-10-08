# 第二轮发行包静态审计（export-audit-v6）

范围：只读审计；未启动 Godot、未导出、未运行服务端。

结论：BLOCK=0，REVIEW=1，PASS=20

## 阻断项

## REVIEW
- **signal-bin-extras**：["libfate_server_signals.linux.x86_64", "libfate_server_signals.windows.x86_64"]

## PASS 重点
- bootstrap-entry
- stdout-flush
- newnet-layout
- legacy-net-references
- FateServer Linux-dedicated-exclusions
- FateServer Linux-feature
- FateServer Linux-config-template
- FateServer Windows-dedicated-exclusions
- FateServer Windows-feature
- FateServer Windows-config-template
- server-platform-pair
- signal-extension-platforms
- config-template-policy
- config-simulation-fields
- bootstrap-routes
- bootstrap-conflict-reject
- signaling-autoload-guard
- signaling-relay-only
- arg-strip
- scratch-resource-risk

## 未覆盖
- 静态检查不能证明Godot导出解析、PCK内容、GDExtension ABI/依赖、真实启动、信号、网络或完整对局。
- all_resources下是否实际带入未排除资源须在导出后索引PCK确认；本轮按静态泄漏风险阻断。
- 工作树含其他未提交改动；本报告不是冻结版本哈希或实际发行包证明。
